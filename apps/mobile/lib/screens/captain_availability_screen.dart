import 'dart:async';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/json_utils.dart';
import '../core/location_service.dart';
import '../core/policy_acknowledgement.dart';
import '../core/texts.dart';

const _green = Color(0xFF19785F);
const _ink = Color(0xFF23362C);
const _muted = Color(0xFF829087);
const _line = Color(0xFFE8ECE7);
const _danger = Color(0xFFD9534F);
const _surface = Color(0xFFF7F8F5);

/// How long a single offer card stays on screen before it is hidden locally
/// and the list is refreshed (inDrive-style countdown).
///
/// The window is purely a client-side convenience: it is NOT a server offer
/// deadline. The backend only expires an unassigned search globally
/// (`ORDER_SEARCH_EXPIRY_MINUTES`, 15 min from `createdAt`) and has no
/// per-captain offer timer, so running out of time here never calls the API.
const kOfferCountdownSeconds = 30;

/// The order feed is refreshed from the server on this cadence.
const _pollInterval = Duration(seconds: 5);

/// The captain's position is re-sent to the server on this cadence while she
/// is online (the backend stores it as her last known location).
const _heartbeatInterval = Duration(seconds: 20);

/// Camera default used only until the device position resolves. It is never
/// shown as the captain's location: no fix means an explicit error state.
const _mapFallbackCenter = LatLng(30.0444, 31.2357);

/// Deep-linkable page for `/captain/availability`.
///
/// The same body is embedded directly in [CaptainHome], which is the main
/// delivery screen; this route exists so old links keep working.
class CaptainAvailabilityScreen extends StatelessWidget {
  const CaptainAvailabilityScreen({
    super.key,
    this.countdownSeconds = kOfferCountdownSeconds,
  });

  /// Offer window per card, forwarded to [CaptainAvailabilityView].
  final int countdownSeconds;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('حالة التوفر والطلبات القريبة'),
        backgroundColor: _surface,
        foregroundColor: _ink,
      ),
      body: SafeArea(
        child: CaptainAvailabilityView(countdownSeconds: countdownSeconds),
      ),
    ),
  );
}

/// Screens 12 & 13 merged — the captain's delivery screen.
///
/// * the online switch and the service radius (inside the admin band),
/// * an OpenStreetMap view centred on the device position with the service
///   radius circle and the pickups of the live offers,
/// * a draggable sheet of offer cards: price, distance, net earnings, a
///   countdown bar, accept and skip. New requests slide in at the top,
///   accepted / skipped requests slide out. When a card's countdown ends it
///   is hidden locally only (no server call); the feed is re-fetched from the
///   server whenever the app returns to the foreground.
class CaptainAvailabilityView extends ConsumerStatefulWidget {
  const CaptainAvailabilityView({
    super.key,
    this.countdownSeconds = kOfferCountdownSeconds,
    this.pollInterval = _pollInterval,
    this.heartbeatInterval = _heartbeatInterval,
  });

  /// Offer window per card (injectable so tests can use a short one).
  final int countdownSeconds;
  final Duration pollInterval;
  final Duration heartbeatInterval;

  @override
  ConsumerState<CaptainAvailabilityView> createState() =>
      _CaptainAvailabilityViewState();
}

class _CaptainAvailabilityViewState
    extends ConsumerState<CaptainAvailabilityView>
    with WidgetsBindingObserver {
  final _listKey = GlobalKey<AnimatedListState>();
  final _sheetController = DraggableScrollableController();
  final _mapController = MapController();

  Timer? _pollTimer;
  Timer? _heartbeatTimer;

  LatLng? _point;
  LocationFailure? _locationFailure;
  bool _locating = false;
  bool _mapReady = false;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _isOnline = false;
  double _radiusKm = 10;
  double _minRadius = 0.5;
  double _maxRadius = 15;

  /// Wallet snapshot shown above the feed so the captain can see why orders
  /// may be paused (the server hides the feed below the minimum balance).
  double? _balance;
  double? _minimumBalance;

  List<Map<String, dynamic>> _orders = [];
  final Set<String> _busy = {};
  final Set<String> _everSeen = {};
  final Set<String> _dismissed = {};
  String? _highlightedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _point = ref.read(captainLocationProvider);
    _locate(post: true);
    _pollTimer = Timer.periodic(widget.pollInterval, (_) {
      if (mounted) _refresh(silent: true);
    });
    _heartbeatTimer = Timer.periodic(widget.heartbeatInterval, (_) {
      if (mounted) _locate(post: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  /// Coming back from the background re-fetches the feed so offers that
  /// expired while we were away are dropped and new ones appear.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(silent: true);
  }

  /// Resolves the device position; on success it also becomes the captain's
  /// server-side location (the availability heartbeat).
  Future<void> _locate({bool post = false}) async {
    if (_locating || !mounted) return;
    setState(() => _locating = true);
    final result = await ref.read(locationServiceProvider).current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.point != null) {
        _locationFailure = null;
      } else {
        _locationFailure = result.failure;
      }
    });
    final point = result.point;
    if (point == null) return;
    _applyPoint(point);
    if (post) await _postLocation(point);
    await _refresh(silent: true);
  }

  void _applyPoint(LatLng point) {
    final first = _point == null;
    if (mounted) setState(() => _point = point);
    ref.read(captainLocationProvider.notifier).state = point;
    if (!_mapReady) return;
    try {
      if (first) {
        _mapController.move(point, _mapController.camera.zoom);
      } else {
        _mapController.move(point, _mapController.camera.zoom);
      }
    } catch (_) {
      // The map is not attached yet; it will pick the position up on build.
    }
  }

  Future<void> _postLocation(LatLng point) async {
    try {
      await ref.read(apiClientProvider).post(
        '/captains/location',
        data: {'latitude': point.latitude, 'longitude': point.longitude},
      );
    } catch (_) {
      // Keep the last known position; the feed refresh surfaces real errors.
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    final api = ref.read(apiClientProvider);
    if (!silent) setState(() => _loading = true);
    try {
      final profile = await api.getMap('/captains/me');
      if (!mounted) return;
      setState(() {
        _isOnline = asBool(profile['isOnline']);
        _radiusKm = asDouble(profile['serviceRadiusKm'], fallback: _radiusKm);
        final band = profile['radiusBand'];
        if (band is Map) {
          _minRadius = asDouble(band['min'], fallback: _minRadius);
          _maxRadius = asDouble(band['max'], fallback: _maxRadius);
        }
        if (_maxRadius < _minRadius) _maxRadius = _minRadius;
        _radiusKm = _radiusKm.clamp(_minRadius, _maxRadius).toDouble();
      });

      // A wallet failure must not hide the feed, so it has its own guard.
      try {
        final wallet = await api.getMap('/captains/wallet');
        if (!mounted) return;
        setState(() {
          _balance = asDoubleOrNull(wallet['balance']);
          _minimumBalance = asDoubleOrNull(wallet['minimumWalletBalance']);
        });
      } catch (_) {
        // Keep the last known balance; the wallet screen shows the error.
      }

      final point = _point;
      if (point == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final items = await api.getList(
        '/orders/available',
        query: {'latitude': point.latitude, 'longitude': point.longitude},
      );
      if (!mounted) return;
      _merge(
        items
            .map((item) => Map<String, dynamic>.from(item as Map))
            .where((order) => !_dismissed.contains(order['id']))
            .toList(),
      );
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (silent) return; // keep the last good feed while polling
      setState(() {
        _loading = false;
        _error = ApiClient.errorMessage(error);
      });
    }
  }

  /// Reconciles the freshly fetched offers with what is on screen: gone
  /// orders slide out, new ones slide in at the top (nearest first), and the
  /// data of the offers we already show is refreshed in place.
  void _merge(List<Map<String, dynamic>> incoming) {
    final listState = _listKey.currentState;
    final incomingIds = {for (final order in incoming) order['id'] as String};

    for (var index = _orders.length - 1; index >= 0; index--) {
      final id = _orders[index]['id'] as String;
      if (incomingIds.contains(id)) continue;
      final removed = _orders[index];
      setState(() => _orders.removeAt(index));
      listState?.removeItem(
        index,
        (context, animation) => _buildCard(removed, animation),
        duration: const Duration(milliseconds: 260),
      );
    }

    for (final order in incoming) {
      final index = _orders.indexWhere((item) => item['id'] == order['id']);
      if (index == -1) continue;
      _orders[index] = order;
    }
    setState(() {});

    final fresh = incoming.where((order) => !_everSeen.contains(order['id'])).toList()
      ..sort(
        (a, b) => (asDoubleOrNull(a['distanceToPickupKm']) ?? double.infinity)
            .compareTo(
              asDoubleOrNull(b['distanceToPickupKm']) ?? double.infinity,
            ),
      );
    if (fresh.isEmpty) return;

    // The first paint seeds the list instead of animating every card in.
    if (_orders.isEmpty && listState == null) {
      for (final order in fresh) {
        _everSeen.add(order['id'] as String);
      }
      setState(() => _orders = fresh);
      return;
    }

    for (var offset = 0; offset < fresh.length; offset++) {
      final order = fresh[offset];
      _everSeen.add(order['id'] as String);
      setState(() => _orders.insert(offset, order));
      listState?.insertItem(offset, duration: const Duration(milliseconds: 280));
      _cardFeedback();
    }
  }

  /// Removes a card and (unless it was accepted) marks the order as passed for
  /// this captain so the server never offers it again.
  Future<void> _dismiss(
    Map<String, dynamic> order, {
    required bool notifyServer,
    String? toast,
  }) async {
    final id = order['id'] as String;
    _dismissed.add(id);
    _removeCard(id);
    if (toast != null && mounted) _toast(toast);
    if (!notifyServer) return;
    try {
      await ref.read(apiClientProvider).post('/orders/$id/skip');
    } catch (_) {
      // The local hide already happened; the next poll re-syncs anyway.
    }
  }

  void _removeCard(String id) {
    final index = _orders.indexWhere((order) => order['id'] == id);
    if (index == -1) return;
    final removed = _orders[index];
    setState(() => _orders.removeAt(index));
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildCard(removed, animation),
      duration: const Duration(milliseconds: 260),
    );
  }

  Future<void> _accept(Map<String, dynamic> order) async {
    final id = order['id'] as String;
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      var current = await _acceptOnce(id);
      // The API may ask for more than one acknowledgement (terms, then a
      // sensitive-category or invoice acknowledgement). Handle them in order.
      while (current != null && PolicyAckNotice.from(current) != null) {
        if (!mounted) return;
        final agreed = await handlePolicyAcknowledgement(context, ref, current);
        if (!agreed) return;
        current = await _acceptOnce(id);
      }
      if (current != null && mounted) {
        await _handleAcceptError(order, current);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// Performs the accept call and returns the error, if any, so ACK_REQUIRED
  /// can be handled by the caller without duplicating the success navigation.
  Future<Object?> _acceptOnce(String id) async {
    try {
      await ref.read(apiClientProvider).post('/orders/$id/accept');
      if (!mounted) return null;
      _cardFeedback();
      _dismissed.add(id);
      _removeCard(id);
      _toast('تم قبول الطلب، بالتوفيق!');
      context.push('/captain/trip/$id');
      return null;
    } catch (error) {
      return error;
    }
  }

  Future<void> _handleAcceptError(
    Map<String, dynamic> order,
    Object error,
  ) async {
    if (_isOrderTaken(error)) {
      // Someone else won the race: drop the card locally and re-sync.
      await _dismiss(
        order,
        notifyServer: false,
        toast: 'عذرًا، لم يعد هذا الطلب متاحًا — تم قبوله من مندوب آخر.',
      );
    } else {
      _toast(ApiClient.errorMessage(error));
    }
    await _refresh(silent: true);
  }

  /// True when the server refused the accept because the order is gone
  /// (409) or its message says it is no longer available.
  bool _isOrderTaken(Object error) {
    if (error is! DioException) return false;
    if (error.response?.statusCode == 409) return true;
    final data = error.response?.data;
    final message = data is Map ? '${data['message'] ?? ''}' : '';
    return message.toLowerCase().contains('no longer available');
  }

  Future<void> _save({bool? online, double? radiusKm}) async {
    final api = ref.read(apiClientProvider);
    final previousOnline = _isOnline;
    final previousRadius = _radiusKm;
    setState(() {
      _saving = true;
      if (online != null) _isOnline = online;
      if (radiusKm != null) _radiusKm = radiusKm;
    });
    try {
      final body = <String, dynamic>{'isOnline': online ?? _isOnline};
      if (radiusKm != null) body['serviceRadiusKm'] = radiusKm;
      await api.patch('/captains/me/availability', data: body);
      if (!mounted) return;
      if (online == true) {
        final point = _point;
        if (point != null) await _postLocation(point);
      }
      _toast(online == false ? 'تم إيقاف استقبال الطلبات' : 'تم تحديث حالة التوفر');
      await _refresh(silent: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isOnline = previousOnline;
        _radiusKm = previousRadius;
      });
      _toast(ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickArea() async {
    final result = await context.push<Map<String, dynamic>>(
      '/map-picker?title=Set%20delivery%20area',
    );
    if (result == null || !mounted) return;
    final point = LatLng(asDouble(result['lat']), asDouble(result['lon']));
    if (!mounted) return;
    setState(() {
      _point = point;
      _locationFailure = null;
    });
    ref.read(captainLocationProvider.notifier).state = point;
    if (_mapReady) {
      try {
        _mapController.move(point, _mapController.camera.zoom);
      } catch (_) {}
    }
    await _postLocation(point);
    await _refresh(silent: true);
  }

  void _focusOrder(Map<String, dynamic> order) {
    final id = order['id'] as String;
    setState(() => _highlightedId = id);
    if (!_sheetController.isAttached) return;
    if (_sheetController.size < 0.5) {
      _sheetController.animateTo(
        0.6,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        body: Stack(
          children: [
            Positioned.fill(child: _map()),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: _availabilityCard(),
                ),
              ),
            ),
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.42,
              minChildSize: 0.16,
              maxChildSize: 0.75,
              snap: true,
              snapSizes: const [0.16, 0.42, 0.75],
              builder: (context, scrollController) => _sheet(scrollController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _map() {
    final point = _point;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: point ?? _mapFallbackCenter,
            initialZoom: 13,
            minZoom: 4,
            maxZoom: 18,
            onMapReady: () => _mapReady = true,
            onTap: (_, _) {
              if (_highlightedId != null) setState(() => _highlightedId = null);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.waslny.orders',
            ),
            if (point != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: point,
                    radius: _radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: _green.withValues(alpha: 0.10),
                    borderColor: _green.withValues(alpha: 0.45),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (point != null)
                  Marker(
                    point: point,
                    width: 46,
                    height: 46,
                    child: const _CaptainMarker(),
                  ),
                for (final order in _orders) ..._orderMarkers(order),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        if (point == null) _locationOverlay(),
      ],
    );
  }

  List<Marker> _orderMarkers(Map<String, dynamic> order) {
    final latitude = asDoubleOrNull(order['pickupLatitude']);
    final longitude = asDoubleOrNull(order['pickupLongitude']);
    if (latitude == null || longitude == null) return const [];
    final id = order['id'] as String;
    final selected = _highlightedId == id;
    return [
      Marker(
        point: LatLng(latitude, longitude),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _focusOrder(order),
          child: Icon(
            Icons.location_on,
            size: selected ? 40 : 32,
            color: selected ? _danger : _green,
          ),
        ),
      ),
    ];
  }

  Widget _locationOverlay() {
    final failure = _locationFailure;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: _locating,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 26),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  failure == null
                      ? Icons.my_location
                      : Icons.location_disabled_outlined,
                  size: 34,
                  color: failure == null ? _green : _danger,
                ),
                const SizedBox(height: 10),
                Text(
                  failure == null
                      ? 'جارٍ تحديد موقعك...'
                      : LocationService.message(failure),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'الطلبات القريبة تُحسب من موقعك الحقيقي.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                if (_locating)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    onPressed: () => _locate(),
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('إعادة المحاولة'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _availabilityCard() {
    final point = _point;
    final locationLine = point != null
        ? 'موقعك الحالي: ${point.latitude.toStringAsFixed(4)}, '
              '${point.longitude.toStringAsFixed(4)}'
        : _locating
        ? 'جارٍ تحديد موقعك...'
        : LocationService.message(_locationFailure ?? LocationFailure.unknown);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isOnline ? const Color(0xFF00A868) : _muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isOnline
                      ? 'متصل — تصلك الطلبات القريبة'
                      : 'غير متصل — لن تصلك طلبات',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              Switch(
                value: _isOnline,
                activeThumbColor: _green,
                onChanged: _saving ? null : (value) => _save(online: value),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 15, color: _muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  locationLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'إعادة تحديد الموقع',
                onPressed: _locating ? null : () => _locate(post: true),
                icon: const Icon(Icons.gps_fixed, size: 18),
              ),
            ],
          ),
          const Divider(height: 14),
          Text(
            'نطاق الخدمة: ${_km(_radiusKm)}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          Text(
            'تظهر لك الطلبات داخل هذا النطاق '
            '(المسموح من ${_km(_minRadius)} إلى ${_km(_maxRadius)}).',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          Slider(
            value: _radiusKm.clamp(_minRadius, _maxRadius).toDouble(),
            min: _minRadius,
            max: _maxRadius,
            divisions: ((_maxRadius - _minRadius) / 0.5).round().clamp(1, 400),
            label: _km(_radiusKm),
            activeColor: _green,
            onChanged: _saving
                ? null
                : (value) => setState(() => _radiusKm = value),
            onChangeEnd: (value) => _save(radiusKm: value),
          ),
        ],
      ),
    );
  }

  Widget _sheet(ScrollController scrollController) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 46,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD3DAD4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'الطلبات القريبة (${_orders.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: _ink,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _pickArea(),
                  icon: const Icon(Icons.location_searching, size: 16),
                  label: const Text('تحديد موقعي'),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: () => _refresh(),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
          ),
          _balanceLine(),
          const Divider(height: 1),
          Expanded(child: _offerList(scrollController)),
        ],
      ),
    );
  }

  /// Compact balance/minimum strip above the offers. Uses the shared money
  /// formatter so the currency reads ج.م in Arabic and EGP in English, exactly
  /// like the wallet, trip and order-review screens.
  Widget _balanceLine() {
    final balance = _balance;
    final minimum = _minimumBalance;
    if (balance == null || minimum == null) return const SizedBox.shrink();
    final low = balance < minimum;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: low ? const Color(0xFFFDECEC) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: low ? _danger.withValues(alpha: 0.45) : _line,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 16,
            color: low ? _danger : _green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              low
                  ? 'رصيدك ${moneyLabel(balance)} أقل من الحد الأدنى ${moneyLabel(minimum)}'
                  : 'الرصيد: ${moneyLabel(balance)} · الحد الأدنى: ${moneyLabel(minimum)}',
              style: TextStyle(
                fontSize: 12,
                color: low ? _danger : _muted,
                fontWeight: low ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
          if (low)
            TextButton(
              onPressed: () => context.push('/wallet'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('شحن الرصيد'),
            ),
        ],
      ),
    );
  }

  Widget _offerList(ScrollController scrollController) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final padding = EdgeInsets.fromLTRB(0, 6, 0, 18 + bottomInset);

    if (_point == null) {
      return ListView(
        controller: scrollController,
        padding: padding,
        children: [
          _stateBox(
            Icons.location_disabled_outlined,
            'الموقع غير متاح',
            _locating
                ? 'جارٍ تحديد موقعك...'
                : LocationService.message(
                    _locationFailure ?? LocationFailure.unknown,
                  ),
            action: TextButton(
              onPressed: () => _locate(post: true),
              child: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      );
    }
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _orders.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: padding,
        children: [
          _stateBox(
            Icons.error_outline,
            'تعذر تحميل الطلبات',
            _error!,
            action: TextButton(
              onPressed: () => _refresh(),
              child: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      );
    }
    if (!_isOnline) {
      return ListView(
        controller: scrollController,
        padding: padding,
        children: [
          _stateBox(
            Icons.power_settings_new,
            'أنت غير متصل الآن',
            'فعّل «متصل» ليظهر لك الطلبات القريبة.',
          ),
        ],
      );
    }
    if (_orders.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: padding,
        children: [
          _stateBox(
            Icons.near_me_outlined,
            'لا توجد طلبات قريبة',
            'سيظهر هنا أي طلب جديد داخل نطاق خدمتك.',
          ),
        ],
      );
    }
    return AnimatedList(
      key: _listKey,
      controller: scrollController,
      initialItemCount: _orders.length,
      padding: padding,
      itemBuilder: (context, index, animation) =>
          _buildCard(_orders[index], animation),
    );
  }

  Widget _buildCard(
    Map<String, dynamic> order,
    Animation<double> animation,
  ) {
    final id = order['id'] as String;
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: _OfferCard(
            key: ValueKey(id),
            order: order,
            countdownSeconds: widget.countdownSeconds,
            busy: _busy.contains(id),
            highlighted: _highlightedId == id,
            onTap: () => setState(
              () => _highlightedId = _highlightedId == id ? null : id,
            ),
            onAccept: () => _accept(order),
            onSkip: () =>
                _dismiss(order, notifyServer: true, toast: 'تم تخطي الطلب'),
            onExpired: () =>
                _dismiss(order, notifyServer: false, toast: 'انتهى وقت هذا الطلب'),
          ),
        ),
      ),
    );
  }

  Widget _stateBox(
    IconData icon,
    String title,
    String subtitle, {
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: _muted),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }

  String _km(double value) {
    final rounded = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rounded كم';
  }
}

/// A single live offer with its countdown bar.
class _OfferCard extends StatefulWidget {
  const _OfferCard({
    super.key,
    required this.order,
    required this.countdownSeconds,
    required this.busy,
    required this.highlighted,
    required this.onAccept,
    required this.onSkip,
    required this.onExpired,
    required this.onTap,
  });

  final Map<String, dynamic> order;
  final int countdownSeconds;
  final bool busy;
  final bool highlighted;
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  final VoidCallback onExpired;
  final VoidCallback onTap;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.countdownSeconds;
    if (_remaining <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired();
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _remaining <= 0) return;
      setState(() => _remaining--);
      if (_remaining <= 0) widget.onExpired();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final price = asDouble(order['price']);
    final commission = asDouble(order['commission']);
    final distance = asDoubleOrNull(order['distanceToPickupKm']);
    final total = widget.countdownSeconds <= 0 ? 1 : widget.countdownSeconds;
    final progress = (_remaining / total).clamp(0.0, 1.0);
    final urgent = _remaining <= 5;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.highlighted ? _green : _line,
          width: widget.highlighted ? 2 : 1,
        ),
        boxShadow: widget.highlighted
            ? const [
                BoxShadow(
                  color: Color(0x2219785F),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      urgent ? Icons.timer_outlined : Icons.timelapse,
                      size: 17,
                      color: urgent ? _danger : _green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_remaining ث',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: urgent ? _danger : _green,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 1, end: progress),
                          duration: const Duration(seconds: 1),
                          builder: (context, value, _) => LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            backgroundColor: _line,
                            valueColor: AlwaysStoppedAnimation(
                              urgent ? _danger : _green,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: _green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${categoryLabel(order['category'])} · '
                        '${order['reference'] ?? ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(
                      moneyLabel(price),
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (distance != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.near_me_outlined,
                        size: 14,
                        color: _muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${distance.toStringAsFixed(1)} كم من موقعك',
                        style: const TextStyle(fontSize: 12.5, color: _muted),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                _routeLine(
                  order['pickupLabel'] as String? ?? '',
                  order['deliveryLabel'] as String? ?? '',
                ),
                const SizedBox(height: 10),
                // The API only returns `price` and `commission` for an offer;
                // there is no captain net-earnings field yet, so the net is
                // derived here as price - commission.
                Text(
                  'صافي ربحك: ${moneyLabel(price - commission)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.busy ? null : widget.onSkip,
                        icon: const Icon(Icons.close, size: 17),
                        label: const Text('تخطي'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _green),
                        onPressed: widget.busy ? null : widget.onAccept,
                        icon: const Icon(Icons.check, size: 17),
                        label: Text(
                          widget.busy ? 'جارٍ...' : 'قبول الطلب',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _routeLine(String pickup, String delivery) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.trip_origin, size: 14, color: _green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(pickup, style: const TextStyle(color: _ink)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.place_outlined, size: 14, color: _danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(delivery, style: const TextStyle(color: _ink)),
            ),
          ],
        ),
      ],
    );
  }

}

class _CaptainMarker extends StatelessWidget {
  const _CaptainMarker();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1D6FE0).withValues(alpha: 0.22),
      shape: BoxShape.circle,
    ),
    child: const Center(
      child: Icon(Icons.navigation, size: 20, color: Color(0xFF1D6FE0)),
    ),
  );
}

/// Light haptics + click on a new offer; web has neither, so it is skipped.
void _cardFeedback() {
  if (kIsWeb) return;
  try {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);
  } catch (_) {
    // Feedback is a nice-to-have; never let it break the feed.
  }
}
