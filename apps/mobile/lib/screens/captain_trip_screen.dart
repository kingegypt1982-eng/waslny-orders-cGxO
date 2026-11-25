import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/chat_config.dart';
import '../core/json_utils.dart';
import '../core/location_service.dart';
import '../core/texts.dart';
import '../core/url_opener.dart';
import '../widgets/rating_input.dart';

const _green = Color(0xFF19785F);
const _ink = Color(0xFF23362C);
const _muted = Color(0xFF829087);
const _line = Color(0xFFE8ECE7);
const _dark = Color(0xFF22342B);

class TripProofPhoto {
  const TripProofPhoto(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

typedef TripProofPicker = Future<TripProofPhoto?> Function();

/// Injectable so widget tests can exercise the proof flow without a camera.
final tripProofPickerProvider = Provider<TripProofPicker>((ref) {
  return () async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null) return null;
    return TripProofPhoto(await image.readAsBytes(), image.name);
  };
});

/// Screens 14 & 15 — the captain trip.
///
/// Screen 14: the trip progress with the single valid action for the current
/// status. Pickup and delivery confirmations require proof photos, so those
/// steps call POST /orders/:id/proof/pickup|delivery instead of a plain
/// status patch. Screen 15: the trip summary and earnings, shown once the
/// order is delivered/completed.
class CaptainTripScreen extends ConsumerStatefulWidget {
  const CaptainTripScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<CaptainTripScreen> createState() => _CaptainTripScreenState();
}

class _CaptainTripScreenState extends ConsumerState<CaptainTripScreen> {
  static const _pollInterval = Duration(seconds: 10);
  static const _heartbeatInterval = Duration(seconds: 20);
  static const _activeTripStatuses = <String>{
    'ACCEPTED',
    'ARRIVED_AT_PICKUP',
    'PICKED_UP',
    'ON_THE_WAY',
  };

  static const _statusLabels = <String, String>{
    'PENDING': 'بانتظار مندوب',
    'SEARCHING_CAPTAIN': 'جارٍ البحث عن مندوب',
    'ACCEPTED': 'تم قبول الطلب',
    'ARRIVED_AT_PICKUP': 'وصلت لموقع الاستلام',
    'PICKED_UP': 'تم استلام الشحنة',
    'ON_THE_WAY': 'الشحنة في الطريق',
    'DELIVERED': 'تم التسليم',
    'COMPLETED': 'الطلب مكتمل',
    'CANCELLED': 'تم إلغاء الطلب',
  };

  Timer? _timer;
  Timer? _heartbeatTimer;
  bool _sendingHeartbeat = false;
  bool _loading = true;
  bool _busy = false;
  bool _showingPickupProof = false;
  bool _cancelledExitStarted = false;
  Map<String, dynamic>? _rating;
  bool _ratingBusy = false;
  bool _ratingHidden = false;
  bool _ratingRequested = false;
  int _ratingStars = 5;
  final TextEditingController _ratingComment = TextEditingController();
  String? _error;
  Map<String, dynamic> _order = const {};
  List<dynamic> _events = const [];
  List<dynamic> _proofs = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_pollInterval, (_) {
      if (!mounted || _busy || _loading) return;
      _load(silent: true);
    });
    // The server needs a fresh captain position for the client's live map.
    // 20 seconds matches the availability heartbeat and stays inside the
    // global API rate limit for a single trip.
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeat();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    _ratingComment.dispose();
    super.dispose();
  }

  String get _status => _order['status'] as String? ?? '';

  Future<void> _load({bool silent = false}) async {
    final api = ref.read(apiClientProvider);
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.getMap('/orders/${widget.orderId}'),
        api.getList('/orders/${widget.orderId}/events'),
        api.getList('/orders/${widget.orderId}/proofs'),
      ]);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _order = results[0] as Map<String, dynamic>;
        _events = results[1] as List<dynamic>;
        _proofs = results[2] as List<dynamic>;
        if (_status != 'ARRIVED_AT_PICKUP') _showingPickupProof = false;
      });
      if (_status == 'CANCELLED') {
        _leaveTrip('تم إلغاء الطلب من العميل، والعمولة مردودة');
        return;
      }
      if ((_status == 'DELIVERED' || _status == 'COMPLETED') &&
          !_ratingRequested &&
          !_ratingHidden) {
        _ratingRequested = true;
        _loadRating();
      }
      // Send one immediate fix when the trip is first shown (or refreshed);
      // the 20-second timer covers the rest of the journey.
      if (!silent) _sendHeartbeat();
    } catch (error) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _loading = false;
        _error = ApiClient.errorMessage(error);
      });
    }
  }

  /// Best-effort position update for the trip. A missing GPS fix or a network
  /// blip never interrupts the captain; PostgreSQL keeps the last good point.
  Future<void> _sendHeartbeat() async {
    if (!mounted || _sendingHeartbeat || !_activeTripStatuses.contains(_status)) {
      return;
    }
    _sendingHeartbeat = true;
    try {
      final result = await ref.read(locationServiceProvider).current();
      final point = result.point;
      if (point == null) return;
      ref.read(captainLocationProvider.notifier).state = point;
      await ref.read(apiClientProvider).post(
            '/orders/${widget.orderId}/location',
            data: {'latitude': point.latitude, 'longitude': point.longitude},
          );
    } catch (_) {
      // Heartbeats are telemetry, not a user action: retry on the next tick.
    } finally {
      _sendingHeartbeat = false;
    }
  }

  Future<void> _openNavigation() async {
    final target = _navigationTarget();
    if (target == null) return;
    final origin = ref.read(captainLocationProvider);
    await ref.read(urlOpenerProvider)(mapsDirectionsUri(
      destinationLatitude: target.latitude,
      destinationLongitude: target.longitude,
      originLatitude: origin?.latitude,
      originLongitude: origin?.longitude,
    ));
  }

  Future<void> _callRecipient() async {
    final phone = _order['recipientPhone']?.toString().trim() ?? '';
    if (phone.isEmpty) {
      _toast('لا يوجد رقم هاتف للمستلم');
      return;
    }
    await ref.read(urlOpenerProvider)(telephoneUri(phone));
  }

  /// Pickup until the parcel is handed over, delivery once it is picked up.
  LatLng? _navigationTarget() {
    const pickupStages = <String>{
      'ACCEPTED',
      'ARRIVED_AT_PICKUP',
      'PICKED_UP',
    };
    final toPickup = _showingPickupProof || pickupStages.contains(_status);
    return _point(
      _order[toPickup ? 'pickupLatitude' : 'deliveryLatitude'],
      _order[toPickup ? 'pickupLongitude' : 'deliveryLongitude'],
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load(silent: true);
    } catch (error) {
      if (mounted) _toast(ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transition(String status) => _run(() async {
        await ref
            .read(apiClientProvider)
            .patch('/orders/${widget.orderId}/status', data: {'status': status});
        if (mounted) _toast('تم تحديث حالة الطلب');
      });

  /// The single retryable start-delivery request. Used by the PICKED_UP button,
  /// by the automatic step after pickup proof, and after a failed auto-attempt.
  Future<void> _startDeliveryRequest() async {
    await ref
        .read(apiClientProvider)
        .patch('/orders/${widget.orderId}/status', data: {'status': 'ON_THE_WAY'});
    if (mounted) _toast('تم بدء التوصيل');
  }

  Future<void> _startDelivery() => _run(_startDeliveryRequest);

  Future<void> _uploadProof(String type, String label) async {
    final photo = await ref.read(tripProofPickerProvider)();
    if (photo == null) return;
    await ref.read(apiClientProvider).uploadFile(
          '/orders/${widget.orderId}/proof/$type',
          photo.bytes,
          photo.name,
          field: 'photo',
        );
    if (mounted) _toast(label);
  }

  Future<void> _submitPickupProof() => _run(() async {
        await _uploadProof('pickup', 'تم تأكيد استلام الشحنة');
        if (mounted) {
          setState(() => _showingPickupProof = false);
        }
        try {
          await _startDeliveryRequest();
        } catch (_) {
          // The server has already moved to PICKED_UP. Keep the same button
          // visible so the captain can retry without losing the proof.
          if (mounted) {
            _toast('تعذر بدء التوصيل تلقائيًا، اضغط «ابدأ التوصيل».');
          }
        }
      });

  Future<void> _submitDeliveryProof() =>
      _run(() => _uploadProof('delivery', 'تم تأكيد تسليم الشحنة'));

  Future<void> _loadRating() async {
    try {
      final data = await ref
          .read(apiClientProvider)
          .getMap('/orders/${widget.orderId}/rating');
      if (!mounted) return;
      setState(() {
        _rating = data.isNotEmpty ? Map<String, dynamic>.from(data) : null;
      });
    } catch (_) {
      // A rating is optional; retry on the next poll without blocking the trip.
      if (mounted) setState(() => _ratingRequested = false);
    }
  }

  Future<void> _submitRating() async {
    if (_ratingBusy || _rating != null || _ratingHidden) return;
    setState(() => _ratingBusy = true);
    try {
      final comment = _ratingComment.text.trim();
      await ref.read(apiClientProvider).post(
            '/orders/${widget.orderId}/rating',
            data: {
              'stars': _ratingStars,
              if (comment.isNotEmpty) 'comment': comment,
            },
          );
      if (mounted) {
        setState(() {
          _rating = {
            'stars': _ratingStars,
            if (comment.isNotEmpty) 'comment': comment,
          };
        });
        _toast('شكرًا لتقييمك');
      }
    } catch (error) {
      if (!mounted) return;
      if (ApiClient.isConflict(error)) {
        // Another device/session already rated: treat it as done and hide the
        // optional card instead of showing an error.
        setState(() {
          _ratingHidden = true;
          _rating = null;
        });
        _toast('تم تقييمك بالفعل');
      } else {
        _toast(ApiClient.errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  Future<void> _releaseOrder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post('/orders/${widget.orderId}/release');
      if (mounted) _leaveTrip('تم إرجاع الطلب إلى قائمة الطلبات');
    } catch (error) {
      if (mounted) _toast(ApiClient.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaves a trip that can no longer be worked. Timers stop immediately so a
  /// cancelled order never keeps polling from a disposed screen.
  void _leaveTrip(String message) {
    if (_cancelledExitStarted) return;
    _cancelledExitStarted = true;
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8F5),
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text('الرحلة ${_order['reference'] ?? ''}'.trim()),
          backgroundColor: const Color(0xFFF7F8F5),
          foregroundColor: _ink,
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ListView(
                        padding: const EdgeInsets.all(18),
                        children: [_errorBox(_error!)],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
                        children: [
                          _stepCard(),
                          if (kChatEnabled &&
                              (_status == 'ACCEPTED' ||
                                  _status == 'ARRIVED_AT_PICKUP' ||
                                  _status == 'PICKED_UP' ||
                                  _status == 'ON_THE_WAY')) ...[
                            const SizedBox(height: 14),
                            _chatButton(),
                          ],
                          if (_status == 'ACCEPTED' || _status == 'ON_THE_WAY') ...[
                            const SizedBox(height: 14),
                            _navigationCard(),
                          ],
                          const SizedBox(height: 14),
                          _mapCard(),
                          const SizedBox(height: 14),
                          _routeCard(),
                          const SizedBox(height: 14),
                          if (_status == 'DELIVERED' ||
                              _status == 'COMPLETED') ...[
                            _summaryCard(),
                            const SizedBox(height: 14),
                            if (!_ratingHidden) ...[
                              _ratingCard(),
                              const SizedBox(height: 14),
                            ],
                          ],
                          _timelineCard(),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  /// Opens the real chat screen with the client's Waslny user id and role.
  Widget _chatButton() {
    final clientId = _order['clientId']?.toString() ?? '';
    final client = _order['client'];
    final name = client is Map ? client['name']?.toString() ?? '' : '';
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('trip-chat-button'),
        onPressed: clientId.isEmpty
            ? null
            : () => context.push(
                  '/chat/${widget.orderId}',
                  extra: {
                    'counterpartId': clientId,
                    'counterpartRole': 'CLIENT',
                    'counterpartName':
                        name.isEmpty ? tr(ar: 'العميل', en: 'Client') : name,
                  },
                ),
        icon: const Icon(Icons.chat_bubble_outline),
        label: Text(tr(ar: 'الدردشة مع العميل', en: 'Chat with client')),
      ),
    );
  }

  /// One card, five sequential stages. The stage comes from the server status,
  /// except the local pickup-proof stage entered from ARRIVED_AT_PICKUP.
  Widget _stepCard() {
    final cancelled = _status == 'CANCELLED';
    final action = _actionLabel();
    final foreground = cancelled ? const Color(0xFFA03040) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cancelled ? const Color(0xFFFDECEF) : _dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                cancelled ? Icons.cancel_outlined : Icons.local_shipping_outlined,
                color: foreground,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stepTitle(),
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if ((_statusLabels[_status] ?? _status) != _stepTitle())
                      Text(
                        _statusLabels[_status] ?? _status,
                        style: const TextStyle(
                          color: Color(0xFFC9D6CE),
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showingPickupProof) ...[
            _stageAddress(pickup: true),
            const SizedBox(height: 8),
            const Text(
              'ارفع صورة واضحة للشحنة قبل بدء التوصيل.',
              style: TextStyle(color: Color(0xFFC9D6CE), fontSize: 12.5),
            ),
          ] else if (_status == 'ACCEPTED' ||
              _status == 'ARRIVED_AT_PICKUP' ||
              _status == 'PICKED_UP') ...[
            _stageAddress(pickup: true),
          ] else if (_status == 'ON_THE_WAY') ...[
            _stageAddress(pickup: false),
          ],
          if (_status == 'DELIVERED') ...[
            const Text(
              'في انتظار تأكيد العميل لاستلام الشحنة لإكمال الطلب وتحويل الأرباح.',
              style: TextStyle(color: Color(0xFFC9D6CE), fontSize: 12.5),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            _primaryAction(action, _busy ? null : _performAction),
          ],
          if (_status == 'ACCEPTED') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('trip-release-button'),
                onPressed: _busy ? null : _releaseOrder,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'اعتذار',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stageAddress({required bool pickup}) => _lineRow(
        pickup ? Icons.trip_origin : Icons.place_outlined,
        pickup ? _green : const Color(0xFFD9534F),
        pickup ? 'الاستلام' : 'التسليم',
        (pickup ? _order['pickupLabel'] : _order['deliveryLabel'])?.toString() ??
            '',
      );

  Widget _primaryAction(String label, VoidCallback? onPressed) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('trip-primary-action'),
          onPressed: onPressed,
          style: FilledButton.styleFrom(backgroundColor: _green),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      );

  String _stepTitle() {
    if (_showingPickupProof) return 'استلام الأوردر';
    switch (_status) {
      case 'ACCEPTED':
        return 'التوجه للعميل';
      case 'ARRIVED_AT_PICKUP':
        return 'الوصول';
      case 'PICKED_UP':
        return 'تم استلام الأوردر';
      case 'ON_THE_WAY':
        return 'التوجه لموقع التسليم';
      case 'DELIVERED':
        return 'تم التسليم';
      case 'COMPLETED':
        return 'اكتملت الرحلة';
      case 'CANCELLED':
        return 'تم إلغاء الطلب';
      default:
        return _statusLabels[_status] ?? _status;
    }
  }

  /// Navigation and phone shortcuts are only offered once the order is
  /// accepted — before that the captain has no recipient to contact.
  Widget _navigationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('trip-navigate-button'),
              onPressed: _openNavigation,
              icon: const Icon(Icons.directions_outlined, size: 18),
              label: const Text('التنقل بالخريطة'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('trip-call-button'),
              onPressed: _callRecipient,
              icon: const Icon(Icons.phone_outlined, size: 18),
              label: const Text('اتصال بالمستلم'),
            ),
          ),
        ],
      ),
    );
  }

  String? _actionLabel() {
    if (_showingPickupProof) return 'تصوير ورفع صورة الاستلام';
    switch (_status) {
      case 'ACCEPTED':
        return 'وصلت';
      case 'ARRIVED_AT_PICKUP':
        return 'استلمت الأوردر';
      case 'PICKED_UP':
        return 'ابدأ التوصيل';
      case 'ON_THE_WAY':
        return 'وصلت لموقع التسليم';
      default:
        return null;
    }
  }

  void _performAction() {
    if (_showingPickupProof) {
      _submitPickupProof();
      return;
    }
    switch (_status) {
      case 'ACCEPTED':
        _transition('ARRIVED_AT_PICKUP');
        return;
      case 'ARRIVED_AT_PICKUP':
        if (mounted) setState(() => _showingPickupProof = true);
        return;
      case 'PICKED_UP':
        _startDelivery();
        return;
      case 'ON_THE_WAY':
        _submitDeliveryProof();
        return;
    }
  }

  /// Pickup and delivery on a map, with the captain's own position when it is
  /// known. Straight line only: the backend does not compute road routes.
  Widget _mapCard() {
    final pickup = _point(_order['pickupLatitude'], _order['pickupLongitude']);
    if (pickup == null) return const SizedBox.shrink();
    final delivery = _point(
      _order['deliveryLatitude'],
      _order['deliveryLongitude'],
    );
    final captain = ref.watch(captainLocationProvider);
    final route = [pickup, ?delivery];
    return _card(
      title: 'خريطة الرحلة',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 210,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: pickup,
              initialZoom: 13.5,
              initialCameraFit: route.length > 1
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(route),
                      padding: const EdgeInsets.all(42),
                    )
                  : null,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.waslny.orders',
              ),
              if (route.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route,
                      strokeWidth: 4,
                      color: _green.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (captain != null)
                    Marker(
                      point: captain,
                      width: 34,
                      height: 34,
                      child: const Icon(
                        Icons.navigation,
                        size: 22,
                        color: Color(0xFF1D6FE0),
                      ),
                    ),
                  Marker(
                    point: pickup,
                    width: 34,
                    height: 34,
                    child: const Icon(Icons.trip_origin, size: 26, color: _green),
                  ),
                  if (delivery != null)
                    Marker(
                      point: delivery,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        size: 36,
                        color: Color(0xFFD9534F),
                      ),
                    ),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  LatLng? _point(Object? latitude, Object? longitude) {
    final lat = asDoubleOrNull(latitude);
    final lon = asDoubleOrNull(longitude);
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  Widget _routeCard() {
    final distance = asDoubleOrNull(_order['distanceKm']);
    return _card(
      title: 'تفاصيل الشحنة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lineRow(Icons.trip_origin, _green, 'الاستلام',
              _order['pickupLabel'] as String? ?? ''),
          const SizedBox(height: 8),
          _lineRow(Icons.place_outlined, const Color(0xFFD9534F), 'التسليم',
              _order['deliveryLabel'] as String? ?? ''),
          const Divider(height: 22),
          _infoRow('المستلم', _order['recipientName'] as String? ?? '-'),
          const SizedBox(height: 6),
          _infoRow('هاتف المستلم', _order['recipientPhone'] as String? ?? '-'),
          const SizedBox(height: 6),
          _infoRow(
            'المسافة',
            distance == null ? '-' : '${distance.toStringAsFixed(1)} كم',
          ),
          const SizedBox(height: 6),
          _infoRow('نوع الشحنة', _categoryLabel(_order['category'] as String?)),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final price = asDouble(_order['price']);
    final commission = asDouble(_order['commission']);
    final completed = _status == 'COMPLETED';
    return _card(
      title: completed ? 'ملخص الرحلة والأرباح' : 'ملخص الأرباح المتوقعة',
      child: Column(
        children: [
          _infoRow('رسوم التوصيل', moneyLabel(price)),
          const SizedBox(height: 6),
          _infoRow('عمولة الشركة', '- ${moneyLabel(commission)}'),
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'صافي ربحك',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
                ),
              ),
              Text(
                moneyLabel(price - commission),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _green,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            completed
                ? 'تم إكمال الطلب وتحويل الأرباح صافية إلى محفظتك.'
                : 'تُخصم العمولة من المحفظة عند القبول وتُرد عند الإلغاء، والربح الصافي يُضاف بعد تأكيد العميل.',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _ratingCard() {
    final saved = _rating != null;
    final savedStars = saved
        ? (_rating!['stars'] ?? _rating!['score'])?.toString() ?? '—'
        : '';
    return _card(
      title: saved ? 'تقييمك لهذه الرحلة' : 'قيّم رحلتك',
      child: saved
          ? Row(
              children: [
                const Icon(Icons.star_rounded, color: _green, size: 22),
                const SizedBox(width: 6),
                Text(
                  '$savedStars من 5',
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            )
          : RatingInput(
              stars: _ratingStars,
              onStarsChanged: (stars) =>
                  setState(() => _ratingStars = stars),
              commentController: _ratingComment,
              busy: _ratingBusy,
              onSubmit: _submitRating,
              foregroundColor: _ink,
              mutedColor: _muted,
              accentColor: _green,
              fieldFillColor: const Color(0xFFF2F5F1),
              buttonForegroundColor: Colors.white,
            ),
    );
  }

  Widget _timelineCard() {
    if (_events.isEmpty) return const SizedBox.shrink();
    final proofsByType = {
      for (final proof in _proofs)
        (proof as Map)['type'] as String? ?? '': proof,
    };
    return _card(
      title: 'سجل الرحلة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final event in _events.reversed) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.circle, size: 8, color: _green),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _statusLabels[(event as Map)['toStatus'] as String? ??
                                ''] ??
                            (event['toStatus'] as String? ?? ''),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      if (event['note'] != null)
                        Text(
                          event['note'] as String,
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (proofsByType.isNotEmpty) ...[
            const Divider(height: 18),
            Text(
              'إثباتات مرفوعة: ${proofsByType.keys.map(_proofLabel).join('، ')}',
              style: const TextStyle(fontSize: 12.5, color: _muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: _ink,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _lineRow(IconData icon, Color color, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: _muted),
              ),
              Text(value, style: const TextStyle(color: _ink)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF5C2CB)),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFA03040))),
    );
  }

  String _categoryLabel(String? category) {
    const labels = <String, String>{
      'PAPERS': 'أوراق',
      'MATERIALS': 'مواد',
      'GOODS': 'بضائع',
      'SPARE_PARTS': 'قطع غيار',
      'PACKAGE': 'طرد',
      'OTHER': 'أخرى',
      'MEDICINES': 'أدوية',
      'PURCHASES': 'مشتريات',
      'FOOD': 'طعام',
      'ELECTRONICS': 'إلكترونيات',
    };
    return labels[category] ?? category ?? '-';
  }

  String _proofLabel(String type) => type == 'PICKUP' ? 'صورة الاستلام' : 'صورة التسليم';
}
