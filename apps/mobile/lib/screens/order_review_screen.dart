import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/json_utils.dart';
import '../core/texts.dart';

const _reviewGreen = Color(0xFF19785F);
const _reviewInk = Color(0xFF23362C);
const _reviewMuted = Color(0xFF829087);

class OrderReviewScreen extends ConsumerStatefulWidget {
  const OrderReviewScreen({
    super.key,
    required this.orderData,
    required this.quote,
  });

  final Map<String, dynamic> orderData;
  final Map<String, dynamic> quote;

  @override
  ConsumerState<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends ConsumerState<OrderReviewScreen> {
  static const _sensitiveCategories = {
    'MEDICINES',
    'PURCHASES',
    'FOOD',
    'ELECTRONICS',
  };

  bool _busy = false;
  bool _ackChecked = false;
  Map<String, dynamic>? _policy;
  String? _policyError;

  bool get _needsAck =>
      _sensitiveCategories.contains(widget.orderData['category']?.toString());

  @override
  void initState() {
    super.initState();
    if (_needsAck) _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    try {
      final policy = await ref
          .read(apiClientProvider)
          .getMap('/policies/SENSITIVE_CATEGORY');
      if (mounted) {
        setState(() {
          _policy = policy;
          _policyError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _policyError = ApiClient.errorMessage(error));
      }
    }
  }

  Future<void> _confirmOrder() async {
    if (_busy) return;
    if (_needsAck && !_ackChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب الموافقة على إقرار الشحنة أولاً')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (_needsAck) {
        final version = _policy?['version']?.toString() ?? '';
        if (version.isEmpty) throw StateError('policy not loaded');
        await ref
            .read(apiClientProvider)
            .post(
              '/acknowledgements',
              data: {
                'type': 'SENSITIVE_CATEGORY',
                'policyVersion': version,
                'category': widget.orderData['category'],
              },
            );
      }
      final order = await ref
          .read(apiClientProvider)
          .post('/orders', data: widget.orderData);
      final orderId = order['id']?.toString();
      if (orderId == null || orderId.isEmpty) {
        throw StateError('Order response did not include an id');
      }
      if (mounted) context.go('/track/$orderId');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) return 'انتهت الجلسة، سجّل الدخول مرة أخرى';
      if (statusCode == 400) {
        final response = error.response?.data;
        final message = response is Map ? response['message'] : null;
        if (message is List && message.isNotEmpty) {
          return message.first.toString();
        }
        if (message is String && message.trim().isNotEmpty) return message;
        return 'بيانات الطلب غير صالحة. راجعها وحاول مرة أخرى.';
      }
      if (error.response == null &&
          (error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout)) {
        return 'تعذر الاتصال بالخادم. تحقق من اتصالك وحاول مرة أخرى.';
      }
    }
    return 'تعذر إنشاء الطلب. حاول مرة أخرى.';
  }

  String _categoryLabel(Object? category) => switch (category) {
    'PURCHASES' => 'مشتريات',
    'FOOD' => 'طعام ومشروبات',
    'PACKAGE' => 'طرود وطلبات',
    'PAPERS' => 'مستندات وأوراق',
    'MEDICINES' => 'أدوية',
    'ELECTRONICS' => 'إلكترونيات',
    'GOODS' => 'هدايا',
    'SPARE_PARTS' => 'قطع غيار',
    _ => 'شحنة',
  };

  /// One money format for every screen: localised currency first, two decimals.
  /// A non-EGP API currency is still honoured, using the same shape.
  String _money(Object? value, Object? currency) {
    final amount = asDoubleOrNull(value);
    if (amount == null) return '—';
    final code = currency?.toString().trim().toUpperCase();
    if (code == null || code.isEmpty || code == 'EGP') {
      return moneyLabel(amount);
    }
    return '$code ${amount.toStringAsFixed(2)}';
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go('/new-order');

  @override
  Widget build(BuildContext context) {
    final price = _money(widget.quote['price'], widget.quote['currency']);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مراجعة السعر'),
          leading: IconButton(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _ReviewSection(
                children: [
                  _ReviewRow(
                    label: 'نقطة الاستلام',
                    value: widget.orderData['pickupLabel']?.toString() ?? '—',
                    icon: Icons.trip_origin,
                  ),
                  const Divider(height: 24),
                  _ReviewRow(
                    label: 'نقطة التسليم',
                    value: widget.orderData['deliveryLabel']?.toString() ?? '—',
                    icon: Icons.location_on_outlined,
                  ),
                  const Divider(height: 24),
                  _ReviewRow(
                    label: 'نوع الشحنة',
                    value: _categoryLabel(widget.orderData['category']),
                    icon: Icons.inventory_2_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ReviewSection(
                children: [
                  _ReviewRow(
                    label: 'المسافة',
                    value:
                        '${asDoubleOrNull(widget.quote['distanceKm'])?.toStringAsFixed(1) ?? '—'} كم',
                    icon: Icons.route_outlined,
                  ),
                  const Divider(height: 24),
                  _ReviewRow(
                    label: 'رسوم التوصيل',
                    value: price,
                    icon: Icons.local_shipping_outlined,
                  ),
                  const Divider(height: 24),
                  _ReviewRow(
                    label: 'الإجمالي',
                    value: price,
                    icon: Icons.receipt_long_outlined,
                    emphasize: true,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_needsAck) ...[
                _ReviewSection(
                  children: [
                    if (_policyError != null) ...[
                      const Text(
                        'تعذر تحميل نص الإقرار',
                        style: TextStyle(
                          color: _reviewInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _policyError!,
                        style: const TextStyle(
                          color: _reviewMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _policyError = null);
                          _loadPolicy();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('إعادة تحميل الإقرار'),
                      ),
                    ] else if (_policy == null) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ] else ...[
                      Text(
                        _policy!['title']?.toString() ?? 'إقرار الشحنة',
                        style: const TextStyle(
                          color: _reviewInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _policy!['text']?.toString() ?? '',
                        style: const TextStyle(
                          color: _reviewMuted,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: CheckboxListTile(
                          value: _ackChecked,
                          onChanged: (value) =>
                              setState(() => _ackChecked = value ?? false),
                          title: const Text(
                            'أقر بما ورد أعلاه وأوافق عليه',
                            style: TextStyle(
                              color: _reviewInk,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: _reviewGreen,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _confirmOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _reviewGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _reviewGreen.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'تأكيد وطلب مندوب',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : _back,
                child: const Text('تعديل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE6EBE6)),
    ),
    child: Column(children: children),
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _reviewGreen, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _reviewMuted,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          style: TextStyle(
            color: _reviewInk,
            fontWeight: FontWeight.w800,
            fontSize: emphasize ? 17 : 14,
          ),
        ),
      ),
    ],
  );
}
