import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';

class YallaMobileMoreScreen extends StatelessWidget {
  const YallaMobileMoreScreen({super.key, this.currentRoute});

  final String? currentRoute;

  static Future<void> open(
    BuildContext context, {
    String? currentRoute,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/mobile-more'),
        builder: (_) => YallaMobileMoreScreen(currentRoute: currentRoute),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'المزيد',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: YallaMobileMoreMenu(currentRoute: currentRoute),
      ),
      bottomNavigationBar: YallaMobileBottomNav(
        currentRoute: '/mobile-more',
        onMore: () {},
      ),
    );
  }
}

class YallaMobileMoreMenu extends StatelessWidget {
  const YallaMobileMoreMenu({super.key, this.currentRoute});

  final String? currentRoute;

  Future<void> _go(BuildContext context, String route) async {
    if (route.isEmpty || route == currentRoute) {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold?.isDrawerOpen == true) scaffold?.closeDrawer();
      if (scaffold?.isEndDrawerOpen == true) scaffold?.closeEndDrawer();
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    final scaffold = Scaffold.maybeOf(context);
    final drawerOpen =
        scaffold?.isDrawerOpen == true || scaffold?.isEndDrawerOpen == true;

    if (scaffold?.isDrawerOpen == true) scaffold?.closeDrawer();
    if (scaffold?.isEndDrawerOpen == true) scaffold?.closeEndDrawer();

    if (drawerOpen) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    if (!navigator.mounted) return;

    try {
      await navigator.pushNamed(route);
    } catch (error, stackTrace) {
      debugPrint('YALLA_MOBILE_NAV_FAILED $route: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('تعذر فتح الشاشة المطلوبة.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <_MobileGroup>[
      _MobileGroup(
        title: 'إصلاح المركبات',
        icon: Icons.car_repair_rounded,
        routes: const [
          _MobileRoute(
              'شاشة الإصلاحات', Icons.dashboard_rounded, '/repairs/dashboard'),
          _MobileRoute('إدخال مركبة جديدة', Icons.add_circle_outline_rounded,
              '/repairs/add'),
          _MobileRoute('قائمة المركبات', Icons.directions_car_rounded,
              '/repairs/vehicles'),
          _MobileRoute(
              'تقارير الإصلاح', Icons.bar_chart_rounded, '/repairs/reports'),
        ],
      ),
      _MobileGroup(
        title: 'وكيل التأمين',
        icon: Icons.verified_user_rounded,
        routes: const [
          _MobileRoute('الرئيسية', Icons.home_rounded, '/insurance-agent/home'),
          _MobileRoute('إضافة تأمين جديد', Icons.add_circle_outline_rounded,
              '/insurance-agent/add'),
          _MobileRoute('حاسبة التأمين', Icons.calculate_rounded,
              '/insurance-agent/calculator'),
          _MobileRoute('قائمة التأمينات', Icons.list_alt_rounded,
              '/insurance-agent/policies'),
          _MobileRoute('جهات الاتصال', Icons.contacts_rounded,
              '/insurance-agent/contacts'),
          _MobileRoute('محافظ المنتجين', Icons.folder_shared_rounded,
              '/insurance-agent/producers'),
          _MobileRoute('المالية', Icons.account_balance_wallet_rounded,
              '/insurance-agent/finance'),
          _MobileRoute('التنبيهات والمتابعة',
              Icons.notifications_active_rounded, '/insurance-agent/alerts'),
          _MobileRoute('التقارير والطباعة', Icons.print_rounded,
              '/insurance-agent/reports'),
        ],
      ),
      _MobileGroup(
        title: 'السندات المالية',
        icon: Icons.receipt_long_rounded,
        routes: const [
          _MobileRoute(
              'سند قبض', Icons.south_west_rounded, '/finance/receipt-voucher'),
          _MobileRoute('قائمة سندات القبض', Icons.list_alt_rounded,
              '/finance/receipt-vouchers'),
          _MobileRoute(
              'سند صرف', Icons.north_east_rounded, '/finance/payment-voucher'),
          _MobileRoute('قائمة سندات الصرف', Icons.list_rounded,
              '/finance/payment-vouchers'),
        ],
      ),
      _MobileGroup(
        title: 'شؤون الموظفين',
        icon: Icons.people_alt_rounded,
        routes: const [
          _MobileRoute(
              'قائمة الموظفين', Icons.list_alt_rounded, '/employees/list'),
          _MobileRoute(
              'إضافة موظف', Icons.person_add_alt_1_rounded, '/employees/add'),
          _MobileRoute(
              'الرواتب', Icons.payments_rounded, '/employees/salaries'),
          _MobileRoute('الحضور والانصراف', Icons.access_time_rounded,
              '/employees/attendance'),
        ],
      ),
      _MobileGroup(
        title: 'المشتريات',
        icon: Icons.shopping_cart_rounded,
        routes: const [
          _MobileRoute('إدخال مشتريات', Icons.add_shopping_cart_rounded,
              '/purchases/create'),
          _MobileRoute(
              'قائمة المشتريات', Icons.list_alt_rounded, '/purchases/list'),
        ],
      ),
      _MobileGroup(
        title: 'العملاء والموردون',
        icon: Icons.groups_rounded,
        routes: const [
          _MobileRoute('قائمة العملاء', Icons.people_rounded, '/clients'),
          _MobileRoute(
              'إضافة عميل', Icons.person_add_alt_1_rounded, '/clients/add'),
          _MobileRoute('ذمم العملاء', Icons.account_balance_wallet_outlined,
              '/clients/accounts-receivable'),
          _MobileRoute(
              'قائمة الموردين', Icons.local_shipping_rounded, '/suppliers'),
          _MobileRoute(
              'إضافة مورد', Icons.person_add_alt_rounded, '/suppliers/add'),
          _MobileRoute('ذمم الموردين', Icons.account_balance_wallet_rounded,
              '/suppliers/payables-list'),
        ],
      ),
      _MobileGroup(
        title: 'المالية',
        icon: Icons.account_balance_rounded,
        routes: const [
          _MobileRoute(
              'اللوحة المالية', Icons.dashboard_rounded, '/finance/dashboard'),
          _MobileRoute('قيود اليومية', Icons.list_alt_rounded,
              '/finance/journal/entries'),
          _MobileRoute('دفتر الأستاذ', Icons.menu_book_rounded,
              '/finance/account-ledger'),
          _MobileRoute('قائمة الدخل', Icons.stacked_bar_chart_rounded,
              '/finance/income-statement'),
          _MobileRoute('الميزانية العمومية', Icons.balance_rounded,
              '/reports/balance-sheet'),
        ],
      ),
      _MobileGroup(
        title: 'الشيكات',
        icon: Icons.request_quote_rounded,
        routes: const [
          _MobileRoute(
              'شاشة الشيكات', Icons.dashboard_rounded, '/cheques/dashboard'),
          _MobileRoute('إضافة شيك', Icons.add_rounded, '/cheques/add'),
          _MobileRoute('قائمة الشيكات', Icons.list_rounded, '/cheques/list'),
          _MobileRoute(
              'شيكات واردة', Icons.call_received_rounded, '/cheques/incoming'),
          _MobileRoute(
              'شيكات صادرة', Icons.call_made_rounded, '/cheques/outgoing'),
          _MobileRoute(
              'للتحصيل', Icons.schedule_rounded, '/cheques/collection'),
          _MobileRoute('محصلة', Icons.task_alt_rounded, '/cheques/collected'),
          _MobileRoute(
              'مرتجعة', Icons.assignment_return_rounded, '/cheques/returned'),
          _MobileRoute('ملغاة', Icons.cancel_outlined, '/cheques/cancelled'),
          _MobileRoute('آجلة', Icons.event_rounded, '/cheques/postdated'),
        ],
      ),
      _MobileGroup(
        title: 'التقارير',
        icon: Icons.assessment_rounded,
        routes: const [
          _MobileRoute('لوحة التقارير', Icons.dashboard_rounded, '/reports'),
          _MobileRoute('تقارير الحضور والغياب', Icons.fact_check_rounded,
              '/reports/attendance'),
          _MobileRoute('ميزان المراجعة', Icons.balance_rounded,
              '/reports/trial-balance'),
        ],
      ),
      _MobileGroup(
        title: 'الإعدادات',
        icon: Icons.settings_rounded,
        routes: const [
          _MobileRoute(
              'إعدادات الورشة', Icons.store_rounded, '/settings/workshop'),
          _MobileRoute(
              'الدعم الفني', Icons.support_agent_rounded, '/support/technical'),
          _MobileRoute('تسجيل الخروج', Icons.logout_rounded, '/logout'),
        ],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _MobileNavCard(
          title: 'لوحة التحكم',
          icon: Icons.dashboard_rounded,
          active: currentRoute == AppRoutes.dashboard ||
              currentRoute == AppRoutes.homeDashboard,
          onTap: () => _go(context, AppRoutes.dashboard),
        ),
        const SizedBox(height: 12),
        ...groups.map(
          (group) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MobileGroupCard(
              group: group,
              currentRoute: currentRoute,
              onRoute: (route) => _go(context, route),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileGroupCard extends StatelessWidget {
  const _MobileGroupCard({
    required this.group,
    required this.currentRoute,
    required this.onRoute,
  });

  final _MobileGroup group;
  final String? currentRoute;
  final ValueChanged<String> onRoute;

  @override
  Widget build(BuildContext context) {
    final groupActive = group.routes.any((item) => currentRoute == item.route);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: groupActive ? AppColors.primary : AppColors.lightGrey,
          ),
        ),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          initiallyExpanded: groupActive,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(group.icon, color: AppColors.primary),
          ),
          title: Text(
            group.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          children: group.routes
              .map(
                (item) => ListTile(
                  minTileHeight: 54,
                  leading: Icon(
                    item.icon,
                    color: currentRoute == item.route
                        ? AppColors.primary
                        : AppColors.secondary,
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: currentRoute == item.route
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color:
                          currentRoute == item.route ? AppColors.primary : null,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => onRoute(item.route),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _MobileNavCard extends StatelessWidget {
  const _MobileNavCard({
    required this.title,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.lightGreen : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.lightGrey,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileGroup {
  const _MobileGroup({
    required this.title,
    required this.icon,
    required this.routes,
  });

  final String title;
  final IconData icon;
  final List<_MobileRoute> routes;
}

class _MobileRoute {
  const _MobileRoute(this.title, this.icon, this.route);

  final String title;
  final IconData icon;
  final String route;
}
