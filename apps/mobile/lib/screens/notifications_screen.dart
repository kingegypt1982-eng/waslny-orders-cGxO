import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';

const _nBg = Color(0xFF03151D);
const _nCard = Color(0xFF092630);
const _nGreen = Color(0xFF00D875);
const _nMuted = Color(0xFF9FB5BD);
const _nBorder = Color(0xFF24515B);
const _nBadge = Color(0xFFFF4B64);

/// Notifications inbox: GET /notifications with pull-to-refresh.
/// Tapping a notification marks it read (PATCH) then opens its order.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<dynamic>? _items;
  String? _error;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiClientProvider).getList('/notifications');
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await ref.read(apiClientProvider).post('/notifications/read-all');
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  /// Maps API notification metadata to the screen that makes sense for the
  /// current role. `extra.route` is respected when a future producer sends it.
  String? _routeFor(Map<String, dynamic> item) {
    final metadata = item['metadata'];
    final meta = metadata is Map ? Map<String, dynamic>.from(metadata) : <String, dynamic>{};
    final role = ref.read(sessionProvider)?['role']?.toString().toUpperCase();
    final isCaptain = role == 'CAPTAIN';
    final screen = meta['screen']?.toString().toUpperCase();
    final explicitRoute = meta['route']?.toString();
    if (explicitRoute != null && explicitRoute.isNotEmpty) return explicitRoute;

    if (screen == 'CAPTAIN_REVIEW' ||
        screen == 'DOCUMENT_APPROVED' ||
        screen == 'DOCUMENT_REJECTED') {
      return isCaptain ? '/captain-documents' : null;
    }
    if (screen == 'NEW_ORDER' || screen == 'AVAILABLE_ORDERS') {
      return isCaptain ? '/captain/availability' : null;
    }

    final orderId = meta['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) return null;
    return isCaptain ? '/captain/trip/$orderId' : '/track/$orderId';
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id != null && id.isNotEmpty) {
      try {
        await ref.read(apiClientProvider).patch('/notifications/$id/read');
      } catch (_) {
        // Best effort: still open the target even if marking fails.
      }
      if (mounted) setState(() {});
      await _load();
    }
    final route = _routeFor(item);
    if (route != null && mounted) context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _nBg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'الإشعارات',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (items != null && items.isNotEmpty)
                      TextButton(
                        onPressed: _markingAll ? null : _markAllRead,
                        child: Text(
                          _markingAll ? 'جارٍ التعليم…' : 'تعليم الكل كمقروء',
                          style: const TextStyle(
                            color: _nGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(items)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<dynamic>? items) {
    if (items == null) {
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, color: _nMuted, size: 44),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _nGreen,
                    foregroundColor: _nBg,
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
      return const Center(child: CircularProgressIndicator(color: _nGreen));
    }
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, color: _nMuted, size: 52),
            SizedBox(height: 12),
            Text(
              'لا توجد إشعارات',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'ستظهر هنا تحديثات طلباتك',
              style: TextStyle(color: _nMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _nGreen,
      backgroundColor: _nCard,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = Map<String, dynamic>.from(items[index] as Map);
          return _NotificationTile(item: item, onTap: () => _open(item));
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item['readAt'] == null;
    final metadata = item['metadata'];
    final hasLink = metadata is Map &&
        (metadata['orderId']?.toString().isNotEmpty == true ||
            metadata['screen']?.toString().isNotEmpty == true ||
            metadata['route']?.toString().isNotEmpty == true);
    return Material(
      color: unread ? const Color(0xFF0D3038) : _nCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: unread ? _nGreen : _nBorder,
              width: unread ? 1.2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _nGreen.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: _nGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['title'] ?? ''}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: _nGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item['body'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _nMuted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _agoArabic(item['createdAt']),
                          style: const TextStyle(color: _nMuted, fontSize: 11),
                        ),
                        if (hasLink) ...[
                          const Spacer(),
                          const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: _nMuted,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bell with an unread-count badge. Polls every 30s while mounted.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key, required this.iconColor, this.size = 27});
  final Color iconColor;
  final double size;
  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  int? _count;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      final data = await ref
          .read(apiClientProvider)
          .getMap('/notifications/unread-count');
      final count = data['count'];
      final value = count is num
          ? count.toInt()
          : int.tryParse('${count ?? ''}');
      if (mounted) setState(() => _count = value);
    } catch (_) {
      // Best effort: keep the previous badge instead of hiding errors.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: () => context.push('/notifications'),
          icon: Icon(
            Icons.notifications_none_rounded,
            color: widget.iconColor,
            size: widget.size,
          ),
        ),
        if (count > 0)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _nBadge,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '+99' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _agoArabic(Object? value) {
  final date = DateTime.tryParse('${value ?? ''}');
  if (date == null) return '';
  final diff = DateTime.now().difference(date.toLocal());
  if (diff.inSeconds < 60) return 'الآن';
  final minutes = diff.inMinutes;
  if (minutes == 1) return 'قبل دقيقة';
  if (minutes == 2) return 'قبل دقيقتين';
  if (minutes <= 10) return 'قبل $minutes دقائق';
  if (minutes < 60) return 'قبل $minutes دقيقة';
  final hours = diff.inHours;
  if (hours == 1) return 'قبل ساعة';
  if (hours == 2) return 'قبل ساعتين';
  if (hours <= 10) return 'قبل $hours ساعات';
  if (hours < 24) return 'قبل $hours ساعة';
  final days = diff.inDays;
  if (days == 1) return 'قبل يوم';
  if (days == 2) return 'قبل يومين';
  if (days <= 10) return 'قبل $days أيام';
  return 'قبل $days يومًا';
}
