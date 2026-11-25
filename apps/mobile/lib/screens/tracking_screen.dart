import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/chat_config.dart';
import '../core/json_utils.dart';
import '../widgets/rating_input.dart';

/// Dark premium RTL tracking screen for Waslny Orders.
///
/// Data source: `GET /orders/:id` (order + client + captain relations).
/// Refresh: polling every 15 seconds + manual refresh button.
/// There is no live socket in the project, and the API does not expose the
/// captain's live coordinates, so only pickup/delivery pins are drawn.
const _tBg = Color(0xFF03151D);
const _tCard = Color(0xFF092630);
const _tCardLight = Color(0xFF103640);
const _tGreen = Color(0xFF00D875);
const _tMuted = Color(0xFF9FB5BD);
const _tBorder = Color(0xFF24515B);
const _tDrop = Color(0xFFFF7955);
const _tDanger = Color(0xFFFF6B6B);

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, required this.orderId});
  final String orderId;
  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  Map<String, dynamic>? _order;
  String? _error;
  Timer? _timer;
  bool _canceling = false;
  final MapController _mapController = MapController();

  /// Resolves the other party from the order and the signed-in role.
  Map<String, String> _chatCounterpart(Map<String, dynamic> order) {
    final role = ref.read(sessionProvider)?['role']?.toString();
    if (role == 'CAPTAIN') {
      final client = order['client'];
      final name = client is Map ? client['name']?.toString() ?? '' : '';
      return {
        'id': order['clientId']?.toString() ?? '',
        'role': 'CLIENT',
        'name': name.isEmpty ? 'العميل' : name,
      };
    }
    final captain = _trackCaptain(order);
    final name = captain?['name']?.toString() ?? '';
    return {
      'id': order['captainId']?.toString() ?? '',
      'role': 'CAPTAIN',
      'name': name.isEmpty ? 'المندوب' : name,
    };
  }

  void _openChat(Map<String, dynamic> order) {
    final counterpart = _chatCounterpart(order);
    context.push(
      '/chat/${widget.orderId}',
      extra: {
        'counterpartId': counterpart['id'],
        'counterpartRole': counterpart['role'],
        'counterpartName': counterpart['name'],
      },
    );
  }

  /// Latest captain heartbeat (from GET /orders/:id/location). The server is
  /// authoritative; a failed poll simply keeps the previous marker.
  Map<String, double>? _captainPoint;
  DateTime? _captainSeenAt;
  Map<String, dynamic>? _rating;
  bool _ratingBusy = false;
  bool _ratingHidden = false;
  int _ratingStars = 5;
  final TextEditingController _ratingComment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(apiClientProvider)
          .getMap('/orders/${widget.orderId}');
      if (mounted) {
        setState(() {
          _order = data;
          _error = null;
        });
      }
      _loadLocation();
      // The API accepts a rating from DELIVERED onward, so offer it as soon as
      // the captain marks delivery — not only after client confirmation.
      final status = data['status']?.toString();
      final role = ref.read(sessionProvider)?['role'];
      if (role == 'CLIENT' &&
          !_ratingHidden &&
          (status == 'DELIVERED' || status == 'COMPLETED')) {
        _loadRating();
      }
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    }
  }

  /// Polls the captain's last server-side position while a trip is active.
  Future<void> _loadLocation() async {
    const liveStatuses = <String>{
      'ACCEPTED',
      'ARRIVED_AT_PICKUP',
      'PICKED_UP',
      'ON_THE_WAY',
    };
    final status = _order?['status']?.toString() ?? '';
    if (!liveStatuses.contains(status)) {
      if (mounted && _captainPoint != null) {
        setState(() {
          _captainPoint = null;
          _captainSeenAt = null;
        });
      }
      return;
    }
    try {
      final data = await ref
          .read(apiClientProvider)
          .getMap('/orders/${widget.orderId}/location');
      final lat = asDoubleOrNull(data['latitude']);
      final lon = asDoubleOrNull(data['longitude']);
      final seen = data['seenAt'] == null
          ? null
          : DateTime.tryParse(data['seenAt'].toString());
      if (!mounted) return;
      setState(() {
        _captainPoint = lat != null && lon != null
            ? {'lat': lat, 'lon': lon}
            : null;
        _captainSeenAt = seen;
      });
    } catch (_) {
      // Tracking is best effort; the order refresh above still works.
    }
  }

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
      // A rating is optional; never hide the order because it failed to load.
    }
  }

  Future<void> _submitRating() async {
    if (_ratingBusy || _rating != null) return;
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
      await _loadRating();
      if (mounted) _showTrackMessage(context, 'شكرًا لتقييمك الرحلة');
    } catch (error) {
      if (!mounted) return;
      if (ApiClient.isConflict(error)) {
        // Already rated from another device/session: hide the form quietly.
        setState(() => _ratingHidden = true);
      } else {
        _showTrackMessage(context, ApiClient.errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  Future<void> _cancelOrder() async {
    if (_canceling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _tCard,
        title: const Text(
          'إلغاء الطلب؟',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'هل تريد إلغاء هذا الطلب؟',
          style: TextStyle(color: _tMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع', style: TextStyle(color: _tMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _tDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('نعم، ألغِ الطلب'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _canceling) return;

    setState(() => _canceling = true);
    try {
      await ref
          .read(apiClientProvider)
          .post('/orders/${widget.orderId}/cancel');
      await _load();
      if (mounted) _showTrackMessage(context, 'تم إلغاء الطلب');
    } catch (error) {
      if (mounted) {
        _showTrackMessage(context, ApiClient.errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
  }

  Future<void> _confirmDelivery() async {
    try {
      await ref
          .read(apiClientProvider)
          .post('/orders/${widget.orderId}/complete');
      await _load();
    } catch (error) {
      if (mounted) {
        _showTrackMessage(context, ApiClient.errorMessage(error));
      }
    }
  }

  Future<void> _captainTransition(String status) async {
    try {
      await ref
          .read(apiClientProvider)
          .patch('/orders/${widget.orderId}/status', data: {'status': status});
      await _load();
    } catch (error) {
      if (mounted) {
        _showTrackMessage(context, ApiClient.errorMessage(error));
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ratingComment.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _tBg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _THeader(
                    title: 'تتبع الشحنة',
                    subtitle: order == null
                        ? '...'
                        : 'طلب ${order['reference'] ?? ''}',
                    onBack: () => context.canPop() ? context.pop() : context.go('/'),
                    onRefresh: _load,
                    onOpenChat: () => _openChat(order!),
                  ),
                  if (order == null)
                    Expanded(
                      child: _TLoadingState(error: _error, onRetry: _load),
                    )
                  else
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Column(
                          children: [
                            SizedBox(
                              height: constraints.maxHeight * 0.32,
                              child: _TMap(
                                order: order,
                                mapController: _mapController,
                                captainPoint: _captainPoint,
                                captainSeenAt: _captainSeenAt,
                              ),
                            ),
                            Expanded(
                              child: _TBody(
                                order: order,
                                canceling: _canceling,
                                onConfirmDelivery: _confirmDelivery,
                                onCaptainTransition: _captainTransition,
                                onOpenCaptainTrip: () =>
                                    context.push('/captain/trip/${order['id']}'),
                                rating: _rating,
                                ratingBusy: _ratingBusy,
                                ratingHidden: _ratingHidden,
                                ratingStars: _ratingStars,
                                ratingComment: _ratingComment,
                                onRatingStarsChanged: (stars) =>
                                    setState(() => _ratingStars = stars),
                                onSubmitRating: _submitRating,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (order != null && _canCancel(order))
                    _TCancelBar(canceling: _canceling, onCancel: _cancelOrder),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canCancel(Map<String, dynamic> order) {
    final role = ref.watch(sessionProvider)?['role'];
    if (role != 'CLIENT') return false;
    // Mirrors the server cancellation rules: unassigned searching orders,
    // plus assigned orders before pickup.
    return const [
      'PENDING',
      'SEARCHING_CAPTAIN',
      'ACCEPTED',
      'ARRIVED_AT_PICKUP',
    ].contains(order['status']);
  }
}

class _THeader extends StatelessWidget {
  const _THeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onRefresh,
    required this.onOpenChat,
  });
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onOpenChat;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
    child: Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _tMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _tCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _tBorder),
          ),
          child: const Text(
            'Waslny',
            style: TextStyle(
              color: _tGreen,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onRefresh,
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
        ),
        if (kChatEnabled)
          IconButton(
            onPressed: onOpenChat,
            tooltip: 'فتح الدردشة',
            icon: const Icon(Icons.chat, color: Colors.white),
          ),
      ],
    ),
  );
}

class _TLoadingState extends StatelessWidget {
  const _TLoadingState({required this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(child: CircularProgressIndicator(color: _tGreen));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: _tMuted, size: 44),
            const SizedBox(height: 12),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _tGreen,
                foregroundColor: _tBg,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TMap extends StatelessWidget {
  const _TMap({
    required this.order,
    required this.mapController,
    required this.captainPoint,
    required this.captainSeenAt,
  });
  final Map<String, dynamic> order;
  final MapController mapController;
  final Map<String, double>? captainPoint;
  final DateTime? captainSeenAt;

  @override
  Widget build(BuildContext context) {
    final pickup = _tLatLng(order['pickupLatitude'], order['pickupLongitude']);
    final delivery = _tLatLng(
      order['deliveryLatitude'],
      order['deliveryLongitude'],
    );
    if (pickup == null || delivery == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        decoration: BoxDecoration(
          color: _tCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _tBorder),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, color: _tMuted, size: 40),
              SizedBox(height: 8),
              Text(
                'تعذر عرض الخريطة: بيانات الموقع ناقصة',
                style: TextStyle(color: _tMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    final captain = captainPoint == null
        ? null
        : LatLng(captainPoint!['lat']!, captainPoint!['lon']!);
    final points = [pickup, delivery, ?captain];
    final bounds = LatLngBounds.fromPoints(points);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(32),
                  maxZoom: 15,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.waslny.orders',
                ),
                MarkerLayer(
                  markers: [
                    if (captain != null)
                      Marker(
                        key: const ValueKey('live-captain-marker'),
                        point: captain,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.two_wheeler_rounded,
                          color: Color(0xFF4FA8FF),
                          size: 32,
                        ),
                      ),
                    Marker(
                      point: pickup,
                      width: 36,
                      height: 36,
                      child: const Icon(Icons.circle, color: _tGreen, size: 22),
                    ),
                    Marker(
                      point: delivery,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: _tDrop,
                        size: 36,
                      ),
                    ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            if (captainSeenAt != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _tCardLight.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'آخر تحديث للموقع ${_tTime(captainSeenAt!)}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: 'recenter-tracking-map',
                backgroundColor: _tCardLight,
                foregroundColor: Colors.white,
                onPressed: () => mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(48),
                    maxZoom: 15,
                  ),
                ),
                child: const Icon(Icons.my_location_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TBody extends ConsumerWidget {
  const _TBody({
    required this.order,
    required this.canceling,
    required this.onConfirmDelivery,
    required this.onCaptainTransition,
    required this.onOpenCaptainTrip,
    required this.rating,
    required this.ratingBusy,
    required this.ratingHidden,
    required this.ratingStars,
    required this.ratingComment,
    required this.onRatingStarsChanged,
    required this.onSubmitRating,
  });
  final Map<String, dynamic> order;
  final bool canceling;
  final VoidCallback onConfirmDelivery;
  final ValueChanged<String> onCaptainTransition;
  final VoidCallback onOpenCaptainTrip;
  final Map<String, dynamic>? rating;
  final bool ratingBusy;
  final bool ratingHidden;
  final int ratingStars;
  final TextEditingController ratingComment;
  final ValueChanged<int> onRatingStarsChanged;
  final VoidCallback onSubmitRating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = order['status']?.toString() ?? 'PENDING';
    final role = ref.watch(sessionProvider)?['role'];
    final isClient = role == 'CLIENT';
    // Pickup and delivery confirmations require photo proof. The shared trip
    // screen owns that flow, so open it instead of calling PATCH /status here.
    final needsProof =
        status == 'ARRIVED_AT_PICKUP' || status == 'ON_THE_WAY';
    final captain = _trackCaptain(order);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _TStatusCard(order: order, status: status),
        const SizedBox(height: 12),
        _TInfoCard(order: order, status: status),
        if (captain != null) ...[
          const SizedBox(height: 12),
          _TCaptainCard(captain: captain),
        ],
        if (status == 'CANCELLED') ...[
          const SizedBox(height: 12),
          const _TCancelBanner(),
        ] else ...[
          const SizedBox(height: 12),
          _TTimelineCard(status: status),
        ],
        if (status == 'DELIVERED' && isClient) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onConfirmDelivery,
              style: ElevatedButton.styleFrom(
                backgroundColor: _tGreen,
                foregroundColor: _tBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text(
                'تأكيد الاستلام',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
        if ((status == 'DELIVERED' || status == 'COMPLETED') &&
            isClient &&
            !ratingHidden) ...[
          const SizedBox(height: 12),
          _TRatingCard(
            rating: rating,
            busy: ratingBusy,
            stars: ratingStars,
            commentController: ratingComment,
            onStarsChanged: onRatingStarsChanged,
            onSubmit: onSubmitRating,
          ),
        ],
        if (role == 'CAPTAIN' && _captainNext.containsKey(status)) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: needsProof
                  ? onOpenCaptainTrip
                  : () => onCaptainTransition(_captainNext[status]!.$1),
              style: ElevatedButton.styleFrom(
                backgroundColor: _tGreen,
                foregroundColor: _tBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                needsProof ? 'إتمام الخطوة في شاشة الرحلة' : _captainNext[status]!.$2,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
        if (canceling) const SizedBox(height: 12),
      ],
    );
  }
}

const _captainNext = {
  'ACCEPTED': ('ARRIVED_AT_PICKUP', 'وصلت لموقع الاستلام'),
  'ARRIVED_AT_PICKUP': ('PICKED_UP', 'تأكيد استلام الشحنة'),
  'PICKED_UP': ('ON_THE_WAY', 'بدء التوصيل'),
  'ON_THE_WAY': ('DELIVERED', 'تأكيد التسليم'),
};

class _TRatingCard extends StatelessWidget {
  const _TRatingCard({
    required this.rating,
    required this.busy,
    required this.stars,
    required this.commentController,
    required this.onStarsChanged,
    required this.onSubmit,
  });

  final Map<String, dynamic>? rating;
  final bool busy;
  final int stars;
  final TextEditingController commentController;
  final ValueChanged<int> onStarsChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final saved = rating != null;
    final savedStars = saved
        ? (rating!['stars'] ?? rating!['score'])?.toString() ?? '—'
        : '';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _tCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _tBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            saved ? 'تقييمك لهذه الرحلة' : 'قيّم رحلتك',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (saved) ...[
            Row(
              children: [
                const Icon(Icons.star_rounded, color: _tGreen, size: 22),
                const SizedBox(width: 6),
                Text(
                  '$savedStars من 5',
                  style: const TextStyle(
                    color: _tGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (rating!['comment'] != null &&
                '${rating!['comment']}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${rating!['comment']}',
                style: const TextStyle(color: _tMuted, fontSize: 12),
              ),
            ],
          ] else
            RatingInput(
              stars: stars,
              onStarsChanged: onStarsChanged,
              commentController: commentController,
              busy: busy,
              onSubmit: onSubmit,
              foregroundColor: Colors.white,
              mutedColor: _tMuted,
              accentColor: _tGreen,
              fieldFillColor: _tCardLight,
              buttonForegroundColor: _tBg,
            ),
        ],
      ),
    );
  }
}

class _TStatusCard extends StatelessWidget {
  const _TStatusCard({required this.order, required this.status});
  final Map<String, dynamic> order;
  final String status;
  @override
  Widget build(BuildContext context) {
    final searching = status == 'PENDING' || status == 'SEARCHING_CAPTAIN';
    final cancelled = status == 'CANCELLED';
    final color = cancelled ? _tDanger : _tGreen;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _tCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _tBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _tGreen,
                    ),
                  )
                : Icon(_tStatusIcon(status), color: color, size: 30),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trackStatusAr(status),
                  style: TextStyle(
                    color: cancelled ? _tDanger : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _tStatusDesc(status),
                  style: const TextStyle(color: _tMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'رسوم التوصيل',
                style: TextStyle(color: _tMuted, fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                _tEgp(order['price']),
                style: const TextStyle(
                  color: _tGreen,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TInfoCard extends StatelessWidget {
  const _TInfoCard({required this.order, required this.status});
  final Map<String, dynamic> order;
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
    decoration: BoxDecoration(
      color: _tCard,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _tBorder),
    ),
    child: Column(
      children: [
        _TInfoRow(label: 'رقم الطلب', value: '${order['reference'] ?? '—'}'),
        const Divider(color: _tBorder, height: 1),
        _TInfoRow(label: 'من', value: '${order['pickupLabel'] ?? '—'}'),
        const Divider(color: _tBorder, height: 1),
        _TInfoRow(label: 'إلى', value: '${order['deliveryLabel'] ?? '—'}'),
        const Divider(color: _tBorder, height: 1),
        _TInfoRow(label: 'وقت الإنشاء', value: _tDate(order['createdAt'])),
      ],
    ),
  );
}

class _TInfoRow extends StatelessWidget {
  const _TInfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: _tMuted, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TCaptainCard extends StatelessWidget {
  const _TCaptainCard({required this.captain});
  final Map<String, dynamic> captain;
  @override
  Widget build(BuildContext context) {
    final name = captain['name']?.toString() ?? '—';
    final phone = captain['phone']?.toString();
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _tCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _tBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: _tCardLight,
            child: Text(
              name.isEmpty ? '؟' : name.characters.first,
              style: const TextStyle(
                color: _tGreen,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'المندوب',
                  style: TextStyle(color: _tMuted, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (phone != null && phone.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    phone,
                    style: const TextStyle(color: _tMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.two_wheeler_outlined, color: _tGreen, size: 28),
        ],
      ),
    );
  }
}

class _TCancelBanner extends StatelessWidget {
  const _TCancelBanner();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: _tDanger.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _tDanger.withValues(alpha: 0.5)),
    ),
    child: const Row(
      children: [
        Icon(Icons.cancel_outlined, color: _tDanger, size: 30),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'تم إلغاء هذا الطلب ولا يمكن متابعته',
            style: TextStyle(
              color: _tDanger,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TTimelineCard extends StatelessWidget {
  const _TTimelineCard({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final index = _tStepIndex(status);
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 5),
      decoration: BoxDecoration(
        color: _tCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _tBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'مراحل الطلب',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _tSteps.length; i++)
            _TStep(
              title: _tSteps[i].$1,
              subtitle: _tSteps[i].$2,
              done: i < index || (index == 0 && i == 0),
              current: i == index && index > 0,
              last: i == _tSteps.length - 1,
            ),
        ],
      ),
    );
  }
}

const _tSteps = [
  ('تم إنشاء الطلب', 'استلمنا طلبك بنجاح'),
  ('تم قبول المندوب', 'المندوب في الطريق لموقع الاستلام'),
  ('المندوب في موقع الاستلام', 'بانتظار استلام الشحنة'),
  ('تم استلام الشحنة', 'الشحنة مع المندوب الآن'),
  ('الشحنة في الطريق', 'التوصيل جارٍ إلى وجهتك'),
  ('تم التسليم', 'وصلت الشحنة لوجهتها'),
  ('اكتمل الطلب', 'شكرًا لاستخدام وصلني'),
];

class _TStep extends StatelessWidget {
  const _TStep({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.current,
    required this.last,
  });
  final String title;
  final String subtitle;
  final bool done;
  final bool current;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final color = done || current ? _tGreen : _tBorder;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: done
                    ? _tGreen
                    : current
                    ? _tGreen.withValues(alpha: 0.15)
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, color: _tBg, size: 16)
                  : current
                  ? Container(
                      margin: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: _tGreen,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            if (!last) Container(width: 1.5, height: 26, color: color),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 10 : 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: done || current ? Colors.white : _tMuted,
                    fontSize: 14,
                    fontWeight: done || current
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: _tMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TCancelBar extends StatelessWidget {
  const _TCancelBar({required this.canceling, required this.onCancel});
  final bool canceling;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: SizedBox(
      key: const ValueKey('cancel-order-button'),
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: canceling ? null : onCancel,
        style: OutlinedButton.styleFrom(
          foregroundColor: _tDanger,
          side: const BorderSide(color: _tDanger),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: canceling
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.close_rounded),
        label: Text(canceling ? 'جارٍ إلغاء الطلب…' : 'إلغاء الطلب'),
      ),
    ),
  );
}

int _tStepIndex(String status) => switch (status) {
  'ACCEPTED' => 1,
  'ARRIVED_AT_PICKUP' => 2,
  'PICKED_UP' => 3,
  'ON_THE_WAY' => 4,
  'DELIVERED' => 5,
  'COMPLETED' => 6,
  'CANCELLED' => -1,
  _ => 0,
};

String trackStatusAr(String status) => switch (status) {
  'PENDING' || 'SEARCHING_CAPTAIN' => 'جارٍ البحث عن مندوب',
  'ACCEPTED' => 'تم قبول الطلب',
  'ARRIVED_AT_PICKUP' => 'المندوب عند الاستلام',
  'PICKED_UP' => 'تم استلام الشحنة',
  'ON_THE_WAY' => 'الشحنة في الطريق',
  'DELIVERED' => 'تم التسليم',
  'COMPLETED' => 'اكتمل الطلب',
  'CANCELLED' => 'ملغي',
  _ => status,
};

String _tStatusDesc(String status) => switch (status) {
  'PENDING' || 'SEARCHING_CAPTAIN' => 'نبحث الآن عن أقرب مندوب متاح',
  'ACCEPTED' => 'المندوب في الطريق إلى موقع الاستلام',
  'ARRIVED_AT_PICKUP' => 'المندوب وصل وينتظر استلام الشحنة',
  'PICKED_UP' => 'الشحنة مع المندوب وفي الطريق إليك',
  'ON_THE_WAY' => 'التوصيل جارٍ الآن إلى وجهتك',
  'DELIVERED' => 'تم تسليم الشحنة، بانتظار تأكيدك',
  'COMPLETED' => 'اكتمل الطلب وتم إغلاقه بنجاح',
  'CANCELLED' => 'تم إلغاء هذا الطلب',
  _ => '',
};

IconData _tStatusIcon(String status) => switch (status) {
  'ACCEPTED' => Icons.person_pin_circle_outlined,
  'ARRIVED_AT_PICKUP' => Icons.location_on_outlined,
  'PICKED_UP' => Icons.inventory_2_outlined,
  'ON_THE_WAY' => Icons.local_shipping_outlined,
  'DELIVERED' || 'COMPLETED' => Icons.check_circle_outline_rounded,
  'CANCELLED' => Icons.cancel_outlined,
  _ => Icons.search_outlined,
};

/// Returns the assigned captain map, or null when no captain is assigned yet.
Map<String, dynamic>? _trackCaptain(Map<String, dynamic> order) {
  if (order['captainId'] == null) return null;
  final captain = order['captain'];
  if (captain is! Map<String, dynamic>) return null;
  if ('${captain['name'] ?? ''}'.isEmpty) return null;
  return captain;
}

LatLng? _tLatLng(Object? lat, Object? lon) {
  final la = asDoubleOrNull(lat);
  final lo = asDoubleOrNull(lon);
  if (la == null || lo == null) return null;
  return LatLng(la, lo);
}

double _tNum(Object? value) => asDouble(value);

String _tEgp(Object? value) => '${_tNum(value).toStringAsFixed(2)} ج.م';

String _tDate(Object? value) {
  final dt = DateTime.tryParse('${value ?? ''}');
  if (dt == null) return '—';
  final local = dt.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)} ${p(local.hour)}:${p(local.minute)}';
}

String _tTime(DateTime value) {
  final local = value.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(local.hour)}:${p(local.minute)}';
}

void _showTrackMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));


