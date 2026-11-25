import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/texts.dart';
import 'notifications_screen.dart';

class WaslnyHomeScreen extends StatefulWidget {
  const WaslnyHomeScreen({
    super.key,
    required this.onNavigate,
    required this.loadOrders,
  });

  final ValueChanged<int> onNavigate;
  final Future<List<dynamic>> Function() loadOrders;

  @override
  State<WaslnyHomeScreen> createState() => _WaslnyHomeScreenState();
}

class _WaslnyHomeScreenState extends State<WaslnyHomeScreen> {
  static const Color bg = Color(0xFF03151D);
  static const Color card = Color(0xFF092630);
  static const Color cardLight = Color(0xFF103640);
  static const Color green = Color(0xFF00D875);
  static const Color muted = Color(0xFF9FB5BD);
  static const Color border = Color(0xFF24515B);

  int selectedTab = 0;
  bool _loadingOrders = false;

  final List<Map<String, dynamic>> parcelTypes = [
    {
      'title': 'مشتريات',
      'titleEn': 'Purchases',
      'category': 'PURCHASES',
      'icon': Icons.shopping_bag_rounded,
      'color': Color(0xFF269BFF),
    },
    {
      'title': 'طعام ومشروبات',
      'titleEn': 'Food and drinks',
      'category': 'FOOD',
      'icon': Icons.lunch_dining_rounded,
      'color': Color(0xFFFFA72B),
    },
    {
      'title': 'طرود وطلبات',
      'titleEn': 'Packages and orders',
      'category': 'PACKAGE',
      'icon': Icons.inventory_2_rounded,
      'color': Color(0xFFFFB45A),
    },
    {
      'title': 'مستندات وأوراق',
      'titleEn': 'Documents and papers',
      'category': 'PAPERS',
      'icon': Icons.description_rounded,
      'color': Color(0xFF8ECFFF),
    },
    {
      'title': 'أدوية',
      'titleEn': 'Medicines',
      'category': 'MEDICINES',
      'icon': Icons.medical_services_rounded,
      'color': Color(0xFF55E2BC),
    },
    {
      'title': 'إلكترونيات',
      'titleEn': 'Electronics',
      'category': 'ELECTRONICS',
      'icon': Icons.devices_rounded,
      'color': Color(0xFF7FA8FF),
    },
    {
      'title': 'هدايا',
      'titleEn': 'Gifts',
      'category': 'GOODS',
      'icon': Icons.card_giftcard_rounded,
      'color': Color(0xFFFF697C),
    },
  ];

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: cardLight,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void startOrder() {
    context.push('/new-order');
  }

  Future<void> _openActiveOrder() async {
    if (_loadingOrders) return;
    setState(() => _loadingOrders = true);
    try {
      final orders = await widget.loadOrders();
      const terminalStatuses = {'DELIVERED', 'COMPLETED', 'CANCELLED'};
      final activeOrders = orders.where((item) {
        if (item is! Map) return false;
        return !terminalStatuses.contains(item['status']?.toString());
      }).toList();
      if (!mounted) return;
      if (activeOrders.length == 1) {
        final order = activeOrders.single as Map;
        final orderId = order['id']?.toString();
        if (orderId == null || orderId.isEmpty) {
          showMessage(
            tr(
              ar: 'تعذر تحميل الطلبات الآن',
              en: 'Could not load orders right now',
            ),
          );
        } else {
          context.push('/track/$orderId');
        }
      } else if (activeOrders.length > 1) {
        widget.onNavigate(1);
      } else {
        showMessage(
          tr(ar: 'لا توجد طلبات جارية الآن', en: 'There are no active orders'),
        );
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          tr(
            ar: 'تعذر تحميل الطلبات الآن',
            en: 'Could not load orders right now',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: deviceIsArabic() ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    buildHeader(),
                    const SizedBox(height: 20),
                    buildHeroBanner(),
                    const SizedBox(height: 18),
                    const SizedBox(height: 23),
                    buildSectionTitle(
                      tr(ar: 'اختر نوع الطرد', en: 'Choose a delivery type'),
                    ),
                    const SizedBox(height: 13),
                    buildParcelGrid(),
                    const SizedBox(height: 20),
                    buildSafetyBanner(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildHeader() {
    return Row(
      children: [
        Container(
          height: 49,
          width: 49,
          decoration: BoxDecoration(
            color: cardLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: const Icon(Icons.location_on_rounded, color: green, size: 32),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Waslny',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                tr(ar: 'طلبات', en: 'Orders'),
                style: TextStyle(
                  fontSize: 16,
                  color: green,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const NotificationBell(iconColor: Colors.white),
        Container(
          height: 43,
          width: 43,
          decoration: BoxDecoration(
            color: cardLight,
            shape: BoxShape.circle,
            border: Border.all(color: border),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () => widget.onNavigate(2),
            icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget buildHeroBanner() {
    return Container(
      height: 260,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: border),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF124A4B), Color(0xFF06252E), Color(0xFF03151D)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 10,
            right: 10,
            top: 5,
            bottom: 5,
            child: Image.asset(
              'assets/images/waslny_home_banner.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              opacity: const AlwaysStoppedAnimation(0.75),
            ),
          ),
          Positioned(
            left: 14,
            top: 17,
            child: Icon(
              Icons.location_on_rounded,
              size: 45,
              color: green.withValues(alpha: 0.65),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 23, 19, 19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(ar: 'كل احتياجاتك', en: 'Everything you need'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(ar: 'في مكان واحد', en: 'in one place'),
                  style: TextStyle(
                    color: green,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    ar: 'اطلب مندوب الآن واستلم طلبك\nمن مكانك إلى وجهتك.',
                    en: 'Request a captain and get your order delivered\nfrom pickup to destination.',
                  ),
                  style: TextStyle(
                    color: Color(0xFFD0E0E0),
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: startOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: bg,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_forward_rounded, size: 20),
                        SizedBox(width: 9),
                        Text(
                          tr(ar: 'اطلب مندوب', en: 'Request a captain'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Icon(Icons.widgets_outlined, color: green, size: 22),
      ],
    );
  }

  Widget buildParcelGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 390
            ? 2
            : constraints.maxWidth < 650
            ? 3
            : 4;
        final itemWidth = (constraints.maxWidth - 9 * (columns - 1)) / columns;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 9,
          runSpacing: 10,
          children: [
            for (final item in parcelTypes)
              SizedBox(
                width: itemWidth,
                height: 128,
                child: Material(
                  color: card,
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    onTap: () {
                      final category = item['category'] as String;
                      context.push(
                        '/new-order?category=${Uri.encodeComponent(category)}',
                        extra: {'category': category},
                      );
                    },
                    borderRadius: BorderRadius.circular(17),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 45,
                            width: 45,
                            decoration: BoxDecoration(
                              color: (item['color'] as Color).withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              item['icon'] as IconData,
                              color: item['color'] as Color,
                              size: 29,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item[deviceIsArabic() ? 'title' : 'titleEn']
                                as String,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget buildSafetyBanner() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openActiveOrder,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0B3035), Color(0xFF08242D)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: green,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(ar: 'أمان في التوصيل', en: 'Safe delivery'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      tr(
                        ar: 'تابع طلبك من الاستلام حتى التسليم',
                        en: 'Track your order from pickup to delivery',
                      ),
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (_loadingOrders)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    color: green,
                    strokeWidth: 2,
                  ),
                )
              else
                const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 17,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
