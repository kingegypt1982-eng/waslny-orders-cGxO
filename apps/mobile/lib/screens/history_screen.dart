import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/json_utils.dart';
import 'tracking_screen.dart' show trackStatusAr;

const _hBg = Color(0xFF03151D);
const _hCard = Color(0xFF092630);
const _hGreen = Color(0xFF00D875);
const _hMuted = Color(0xFF9FB5BD);
const _hBorder = Color(0xFF24515B);

/// Active = anything before hand-over to the recipient.
const _hActiveStatuses = {
  'PENDING',
  'SEARCHING_CAPTAIN',
  'ACCEPTED',
  'ARRIVED_AT_PICKUP',
  'PICKED_UP',
  'ON_THE_WAY',
};
const _hDoneStatuses = {'DELIVERED', 'COMPLETED'};
const _hCancelledStatuses = {'CANCELLED'};

enum _HFilter { all, active, done, cancelled }

/// Customer order history: dark Arabic RTL with status filter chips.
/// Filtering is client-side over GET /orders (the API has no status filter).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _HFilter _filter = _HFilter.all;
  List<dynamic>? _orders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await ref.read(apiClientProvider).getList('/orders');
      if (mounted) {
        setState(() {
          _orders = orders;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(error));
    }
  }

  List<Map<String, dynamic>> get _visible {
    final orders = (_orders ?? []).map(
      (e) => Map<String, dynamic>.from(e as Map),
    );
    switch (_filter) {
      case _HFilter.active:
        return orders
            .where((o) => _hActiveStatuses.contains('${o['status']}'))
            .toList();
      case _HFilter.done:
        return orders
            .where((o) => _hDoneStatuses.contains('${o['status']}'))
            .toList();
      case _HFilter.cancelled:
        return orders
            .where((o) => _hCancelledStatuses.contains('${o['status']}'))
            .toList();
      case _HFilter.all:
        return orders.toList();
    }
  }

  String get _emptyText => switch (_filter) {
    _HFilter.active => 'لا توجد طلبات نشطة',
    _HFilter.done => 'لا توجد طلبات مكتملة',
    _HFilter.cancelled => 'لا توجد طلبات ملغاة',
    _HFilter.all => 'لا توجد طلبات بعد',
  };

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _hBg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Text(
                  'سجل الطلبات',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    _HChip(
                      label: 'الكل',
                      selected: _filter == _HFilter.all,
                      onTap: () => setState(() => _filter = _HFilter.all),
                    ),
                    _HChip(
                      label: 'نشطة',
                      selected: _filter == _HFilter.active,
                      onTap: () => setState(() => _filter = _HFilter.active),
                    ),
                    _HChip(
                      label: 'مكتملة',
                      selected: _filter == _HFilter.done,
                      onTap: () => setState(() => _filter = _HFilter.done),
                    ),
                    _HChip(
                      label: 'ملغاة',
                      selected: _filter == _HFilter.cancelled,
                      onTap: () => setState(() => _filter = _HFilter.cancelled),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(orders)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<dynamic>? orders) {
    if (orders == null) {
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, color: _hMuted, size: 44),
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
                    backgroundColor: _hGreen,
                    foregroundColor: _hBg,
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
      return const Center(child: CircularProgressIndicator(color: _hGreen));
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, color: _hMuted, size: 52),
            const SizedBox(height: 12),
            Text(
              _emptyText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _hGreen,
      backgroundColor: _hCard,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _HOrderCard(order: visible[index]),
      ),
    );
  }
}

class _HChip extends StatelessWidget {
  const _HChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: _hGreen,
      backgroundColor: _hCard,
      side: BorderSide(color: selected ? _hGreen : _hBorder),
      labelStyle: TextStyle(
        color: selected ? _hBg : Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );
}

class _HOrderCard extends StatelessWidget {
  const _HOrderCard({required this.order});
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) => Material(
    color: _hCard,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: () => context.push('/track/${order['id']}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order['reference'] ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    trackStatusAr('${order['status'] ?? ''}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _hGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${order['pickupLabel'] ?? '—'} ← ${order['deliveryLabel'] ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _hMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _hEgp(order['price']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _hDate(order['createdAt']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _hMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _hEgp(Object? value) {
  if (value == null) return '—';
  return '${asDouble(value).toStringAsFixed(2)} ج.م';
}

String _hDate(Object? value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return '';
  final local = date.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)}';
}
