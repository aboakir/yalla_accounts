// 📁 lib/core/widgets/sidebar/yalla_sidebar.dart
//
// YallaSidebar — نسخة مطابقة للهيكل المطلوب + إصلاح تنقل يمنع تراكم الشاشات.
// + إضافة قسم السندات المالية (سند قبض + سند صرف) فقط كما طلبت.
// لا تغيير على أي شيء آخر.
//
// ——————————————————————————————————————————————

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/release/release_scope_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

import 'sidebar_header.dart';
import 'sidebar_search.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class YallaSidebar extends ConsumerStatefulWidget {
  final String? currentRoute;
  const YallaSidebar({super.key, this.currentRoute});

  @override
  ConsumerState<YallaSidebar> createState() => _YallaSidebarState();
}

class _YallaSidebarState extends ConsumerState<YallaSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _widthAnim;
  bool _isCollapsed = false;
  String _searchQuery = '';
  final String _version = '';
  bool _isNavigating = false; // Debounce

  // ===== Routes =====
  static const rDashboard = '/dashboard';

  // Repairs
  static const rRepairsRoot = '/repairs';
  static const rRepairsDashboard = '/repairs/dashboard';
  static const rRepairsAdd = '/repairs/add';
  static const rVehiclesList = AppRoutes.vehiclesList;
  static const rRepairReports = '/repairs/reports';

  // Employees
  static const rEmpRoot = '/employees';
  static const rEmpList = '/employees/list';
  static const rEmpAdd = '/employees/add';
  static const rEmpAdvances = '/employees/list';
  static const rEmpAttendance = '/employees/attendance';
  static const rEmpSalaries = '/employees/salaries';

  // Purchases
  static const rPurchRoot = '/purchases';
  static const rPurchList = AppRoutes.purchasesList;
  static const rPurchCreate = '/purchases/create';

  // Cheques
  static const rChequesRoot = '/cheques';
  static const rChequesDashboard = '/cheques/dashboard';
  static const rChequesAdd = '/cheques/add';
  static const rChequesList = '/cheques/list';
  static const rChequesIncoming = '/cheques/incoming';
  static const rChequesOutgoing = '/cheques/outgoing';
  static const rChequesCollection = '/cheques/collection';
  static const rChequesCollected = '/cheques/collected';
  static const rChequesReturned = '/cheques/returned';
  static const rChequesCancelled = '/cheques/cancelled';
  static const rChequesPostdated = '/cheques/postdated';

  // Clients & Suppliers
  static const rClients = '/clients';
  static const rClientAdd = '/clients/add';
  static const rClientAR = '/clients/accounts-receivable';
  static const rSuppliers = '/suppliers';
  static const rSupplierAdd = '/suppliers/add';

  // Finance
  static const rFinanceRoot = '/finance';
  static const rFinanceDashboard = '/finance/dashboard';
  static const rCollectionDashboard = AppRoutes.collectionDashboard;
  static const rJournalEntries = '/finance/journal/entries';
  static const rFinanceAccountLedger = '/finance/account-ledger';
  static const rIncomeStatement = '/finance/income-statement';
  static const rReportsBalanceSheet = '/reports/balance-sheet';

  // Reports
  static const rReportsRoot = '/reports';
  static const rReportsDashboard = '/reports';
  static const rReportsAttendance = '/reports/attendance';
  static const rReportsTrialBalance = '/reports/trial-balance';

  // Settings
  static const rSettingsRoot = '/settings';
  static const rSettingsWorkshop = '/settings/workshop';
  static const rSettingsUser = '/settings/user';
  static const rSettingsUI = '/settings/ui';
  static const rSettingsSupport = '/settings/support';
  static const rSettingsSecurityData = '/settings/security-data';
  static const rTechnicalSupport = AppRoutes.technicalSupport;

  static const rSubscription = '/subscription';

// ===== السندات المالية =====
  static const rReceiptVoucher = AppRoutes.receiptVoucher;
  static const rReceiptVouchersList = AppRoutes.receiptVouchersList;
  static const rPaymentVoucher = AppRoutes.paymentVoucher;
  static const rPaymentVouchersList = AppRoutes.paymentVouchersList;
// ===== وكيل التأمين =====
  static const rInsuranceRoot = AppRoutes.insuranceAgentRoot;
  static const rInsuranceHome = AppRoutes.insuranceAgentHome;
  static const rInsuranceAddNew = AppRoutes.insuranceAgentAddNew;
  static const rInsuranceProducers = AppRoutes.insuranceAgentProducers;
  static const rInsuranceCalculator = AppRoutes.insuranceAgentCalculator;
  static const rInsuranceFinance = AppRoutes.insuranceAgentFinance;
  static const rInsuranceAlerts = AppRoutes.insuranceAgentAlerts;
  static const rInsuranceReports = AppRoutes.insuranceAgentReports;
  static const rInsurancePoliciesList = AppRoutes.insurancePoliciesList;
  static const rInsuranceContacts = AppRoutes.insuranceAgentContacts;

  // Logout
  static const rLogout = '/logout';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _widthAnim = Tween<double>(begin: 300, end: 80).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _restoreCollapse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _restoreCollapse() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    // Collapse is a desktop-only affordance. A saved collapsed desktop state
    // must never turn the phone/tablet drawer into an icon-only strip.
    final saved = context.isDesktopWidth
        ? (prefs.getBool('sidebar_collapsed') ?? false)
        : false;

    setState(() {
      _isCollapsed = saved;
      if (_isCollapsed) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    });
  }

  Future<void> _persistCollapse(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sidebar_collapsed', v);
  }

  void _toggleCollapse() {
    if (!context.isDesktopWidth) return;

    setState(() {
      _isCollapsed = !_isCollapsed;
      if (_isCollapsed) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
      _persistCollapse(_isCollapsed);
    });
  }

  void _navigate(String route) async {
    print("NAVIGATING TO: $route");

    if (_isNavigating || route.isEmpty) return;

    if (!mounted) return;

    final compactNavigation = !context.isDesktopWidth;
    final drawerNavigator = Navigator.of(context);
    final targetNavigator =
        Navigator.of(context, rootNavigator: compactNavigation);
    final scaffoldState = Scaffold.maybeOf(context);
    final drawerIsOpen = scaffoldState?.isDrawerOpen == true ||
        scaffoldState?.isEndDrawerOpen == true;
    final current =
        ModalRoute.of(context)?.settings.name ?? widget.currentRoute;

    if (current == route) {
      if (drawerIsOpen && drawerNavigator.canPop()) {
        drawerNavigator.pop();
      }
      return;
    }

    _isNavigating = true;

    if (drawerIsOpen && drawerNavigator.canPop()) {
      drawerNavigator.pop();
    }

    print(">>> SIDEBAR NAVIGATE TO: $route");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!targetNavigator.mounted) {
        _isNavigating = false;
        return;
      }

      final Future<dynamic> navigation = compactNavigation
          ? targetNavigator.pushNamedAndRemoveUntil(
              route,
              (Route<dynamic> r) => r.isFirst,
            )
          : targetNavigator.pushReplacementNamed(route);

      navigation
          .catchError((Object _) => null)
          .whenComplete(() => _isNavigating = false);
    });
  }

  Future<void> _navigateAddParty() async {
    if (_isCollapsed) {
      _navigate(rClientAdd);
      return;
    }
    final sel = await showDialog<String>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('إضافة جهة'),
        content: const Text('اختر نوع الجهة:'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('client'),
              child: const Text('عميل')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop('supplier'),
              child: const Text('مورد')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('إلغاء')),
        ],
      ),
    );
    if (sel == 'client') _navigate(rClientAdd);
    if (sel == 'supplier') _navigate(rSupplierAdd);
  }

  Future<void> _navigateAgingBoth() async {
    if (_isCollapsed) {
      _navigate(rClientAR);
      return;
    }

    final sel = await showDialog<String>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('الذمم'),
        content: const Text('اختر نوع الذمم:'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('ar'),
              child: const Text('ذمم العملاء')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop('ap'),
              child: const Text('ذمم الموردين')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('إلغاء')),
        ],
      ),
    );

    if (sel == 'ar') _navigate(rClientAR);
    if (sel == 'ap') _navigate(AppRoutes.suppliersPayablesList);
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String route,
  }) {
    final bool active = (widget.currentRoute == route) ||
        (ModalRoute.of(context)?.settings.name == route);

    final line = Container(
      width: 3,
      height: 26,
      decoration: BoxDecoration(
        color: active ? Colors.green : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    final row = AdaptiveRow(
      children: [
        line,
        const SizedBox(width: 8),
        Icon(icon, color: active ? Colors.green : null),
        const SizedBox(width: 8),
        if (!_isCollapsed)
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: active ? Colors.green : null),
            ),
          ),
      ],
    );

    final tile = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: row,
      onTap: () => _navigate(route),
    );

    return _isCollapsed ? Tooltip(message: title, child: tile) : tile;
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final row = AdaptiveRow(
      children: [
        Container(width: 3, height: 26, color: Colors.transparent),
        const SizedBox(width: 8),
        Icon(icon),
        const SizedBox(width: 8),
        if (!_isCollapsed)
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
      ],
    );
    final tile = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: row,
      onTap: onTap,
    );
    return _isCollapsed ? Tooltip(message: title, child: tile) : tile;
  }

  bool _matches(String title) {
    if (_searchQuery.trim().isEmpty) return true;
    return title.contains(_searchQuery) ||
        title.toLowerCase().contains(_searchQuery.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final hasSearch = _searchQuery.trim().isNotEmpty;

    // 1) إصلاح المركبات
    final repairsItems = [
      (Icons.dashboard, 'شاشة الإصلاحات', rRepairsDashboard),
      (Icons.add, 'إدخال مركبة جديدة', rRepairsAdd),
      (Icons.list, 'قائمة المركبات', rVehiclesList),
      (Icons.bar_chart, 'تقارير الإصلاح', rRepairReports),
    ].where((e) => _matches(e.$2)).toList();

    // 2) شؤون الموظفين
    final employeesItems = [
      (Icons.list_alt, 'قائمة الموظفين', rEmpList),
      (Icons.person_add, 'إضافة موظف', rEmpAdd),
      (Icons.receipt_long, 'الرواتب', rEmpSalaries),
      if (ReleaseScopeConfig.employeeAdvancesEnabled)
        (Icons.savings, 'السلف والمكافآت', rEmpAdvances),
      (Icons.access_time, 'الحضور والانصراف', rEmpAttendance),
    ].where((e) => _matches(e.$2)).toList();

    // 3) المشتريات
    final purchasesItems = [
      (Icons.add, 'إدخال مشتريات', rPurchCreate),
      (Icons.list_alt, 'قائمة المشتريات', AppRoutes.purchasesList),
    ];

    // 4) الشيكات
    final chequesItems = [
      (Icons.dashboard, 'شاشة الشيكات', rChequesDashboard),
      (Icons.add, 'إضافة شيك', rChequesAdd),
      (Icons.list, 'قائمة الشيكات', rChequesList),
      (Icons.call_received, 'شيكات واردة', rChequesIncoming),
    ].where((e) => _matches(e.$2)).toList();

    // 5) العملاء والموردون
    final clientsSuppliersItems = <Widget>[];
    if (_matches('قائمة العملاء')) {
      clientsSuppliersItems.add(
          _tile(icon: Icons.people, title: 'قائمة العملاء', route: rClients));
    }

    if (_matches('إضافة عميل/مورد')) {
      clientsSuppliersItems.add(_actionTile(
        icon: Icons.person_add_alt_1,
        title: 'إضافة عميل/مورد',
        onTap: _navigateAddParty,
      ));
    }
    if (_matches('الذمم المدينة والدائنة')) {
      clientsSuppliersItems.add(_actionTile(
        icon: Icons.account_balance_wallet,
        title: 'الذمم المدينة والدائنة',
        onTap: _navigateAgingBoth,
      ));
    }

    // 6) المالية
    final financeItems = [
      (Icons.list_alt, 'قيود اليومية', rJournalEntries),
      (Icons.menu_book, 'دفتر الأستاذ', rFinanceAccountLedger),
      if (ReleaseScopeConfig.extendedFinanceEnabled) ...[
        (Icons.dashboard, 'لوحة مالية', rFinanceDashboard),
        (
          Icons.collections_bookmark_outlined,
          'التحصيل والذمم',
          rCollectionDashboard
        ),
        (Icons.stacked_bar_chart, 'قائمة الدخل', rIncomeStatement),
        (
          Icons.account_balance_wallet,
          'الميزانية العمومية',
          rReportsBalanceSheet
        ),
      ],
    ].where((e) => _matches(e.$2)).toList();

    // ===== NEW: سندات مالية =====
    final vouchersItems = [
      (Icons.arrow_downward, 'سند قبض', rReceiptVoucher),
      (Icons.list_alt, 'قائمة سندات القبض', rReceiptVouchersList),
      (Icons.arrow_upward, 'سند صرف', rPaymentVoucher),
      (Icons.list, 'قائمة سندات الصرف', rPaymentVouchersList),
    ].where((e) => _matches(e.$2)).toList();
// ===== NEW: وكيل التأمين =====
    final insuranceAgentItems = [
      (Icons.home, 'الشاشة الرئيسية', rInsuranceHome),
      (Icons.add_circle_outline, ' إضافة تأمين جديد', rInsuranceAddNew),
      (Icons.calculate, 'حاسبة التأمين', rInsuranceCalculator),
      (Icons.list_alt, 'قائمة التأمينات', rInsurancePoliciesList),
      (Icons.contacts, 'جهات الاتصال', rInsuranceContacts),
      (Icons.folder_shared, 'محافظ المنتجين', rInsuranceProducers),
      (Icons.account_balance_wallet, 'المالية', rInsuranceFinance),
      (Icons.notifications_active, 'التنبيهات والمتابعة', rInsuranceAlerts),
      (Icons.print, 'التقارير والطباعة', rInsuranceReports),
    ].where((e) => _matches(e.$2)).toList();

    // 7) التقارير
    final reportsItems = [
      (Icons.dashboard, 'لوحة التقارير', rReportsDashboard),
      (Icons.check_circle, 'تقارير حضور وغياب', rReportsAttendance),
      (Icons.balance, 'تقارير مالية', rReportsTrialBalance),
    ].where((e) => _matches(e.$2)).toList();

    return AnimatedBuilder(
      animation: _widthAnim,
      builder: (_, __) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SizedBox(
          width: _widthAnim.value,
          child: Column(
            children: [
              SidebarHeader(
                isCollapsed: _isCollapsed,
                onToggle: _toggleCollapse,
                showToggle: context.isDesktopWidth,
              ),
// إخفاء مربع البحث بدون حذفه
              Visibility(
                visible: false,
                maintainState: false,
                maintainAnimation: false,
                maintainSize: false,
                child: (!_isCollapsed)
                    ? Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SidebarSearch(
                          initialQuery: _searchQuery,
                          onChanged: (q) => setState(() => _searchQuery = q),
                          hintText: 'بحث...',
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _tile(
                        icon: Icons.dashboard,
                        title: 'لوحة التحكم',
                        route: rDashboard),

                    // إصلاح المركبات
                    if (repairsItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.build,
                        title: 'إصلاح المركبات',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rRepairsRoot) ??
                                false,
                        children: repairsItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),
                    // ===== NEW: وكيل التأمين =====
                    if (insuranceAgentItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.verified_user,
                        title: 'وكيل التأمين',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rInsuranceRoot) ??
                                false,
                        children: insuranceAgentItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // ===== NEW: السندات المالية =====
                    if (vouchersItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.receipt_long,
                        title: 'السندات المالية',
                        isInitiallyExpanded:
                            widget.currentRoute?.contains('voucher') ?? false,
                        children: vouchersItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // شؤون الموظفين
                    if (employeesItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.people_alt,
                        title: 'شؤون الموظفين',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rEmpRoot) ?? false,
                        children: employeesItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // مشتريات
                    if (purchasesItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.shopping_cart,
                        title: 'المشتريات',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rPurchRoot) ??
                                false,
                        children: purchasesItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // العملاء والموردون
                    if (clientsSuppliersItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.group,
                        title: 'العملاء والموردون',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith('/clients') ==
                                    true ||
                                widget.currentRoute?.startsWith('/suppliers') ==
                                    true,
                        children: clientsSuppliersItems,
                      ),

                    // المالية
                    if (financeItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.account_balance,
                        title: 'المالية',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rFinanceRoot) ??
                                false,
                        children: financeItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // شيكات
                    if (ReleaseScopeConfig.chequesEnabled &&
                        (chequesItems.isNotEmpty || !hasSearch))
                      _group(
                        icon: Icons.receipt_long,
                        title: 'الشيكات',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rChequesRoot) ??
                                false,
                        children: chequesItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

// ===== إصدار لاحق (قسم غير فعّال) =====
                    _group(
                      icon: Icons.lock_clock,
                      title: 'إصدار لاحق',
                      isInitiallyExpanded: false,
                      children: [
                        if (ReleaseScopeConfig.chequesEnabled)
                          ListTile(
                            dense: true,
                            title: Text(
                              'إدارة الشيكات',
                              style: TextStyle(color: Colors.grey),
                            ),
                            leading: const Icon(Icons.receipt_long,
                                color: Colors.grey),
                            onTap: null, // غير مفعّل
                          ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'ذمم العملاء والموردين',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading: const Icon(Icons.account_balance_wallet,
                              color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'التقارير المالية المتقدمة',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading:
                              const Icon(Icons.assessment, color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'إدارة الفواتير المتقدمة',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading: const Icon(Icons.request_page,
                              color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'تقارير الرواتب',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading:
                              const Icon(Icons.payments, color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'إدارة المخزون',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading:
                              const Icon(Icons.inventory_2, color: Colors.grey),
                          onTap: null,
                        ),
                      ],
                    ),

                    // الإعدادات
                    _group(
                      icon: Icons.settings,
                      title: 'الإعدادات',
                      isInitiallyExpanded:
                          widget.currentRoute?.startsWith(rSettingsRoot) ??
                              false,
                      children: [
                        _tile(
                            icon: Icons.store,
                            title: 'إعدادات الورشة',
                            route: rSettingsWorkshop),
                        _tile(
                            icon: Icons.shield_outlined,
                            title: 'حماية البيانات',
                            route: rSettingsSecurityData),
                        _tile(
                            icon: Icons.support_agent,
                            title: 'الدعم الفني',
                            route: rTechnicalSupport),
                        ListTile(
                          leading:
                              const Icon(Icons.logout, color: Colors.redAccent),
                          title: _isCollapsed
                              ? const SizedBox.shrink()
                              : const Text('تسجيل خروج',
                                  style: TextStyle(color: Colors.redAccent)),
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          onTap: () {
                            final scaffoldState = Scaffold.maybeOf(context);
                            if (scaffoldState?.isDrawerOpen == true) {
                              Navigator.of(context).pop();
                            }
                            _navigate(rLogout);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group({
    required IconData icon,
    required String title,
    required List<Widget> children,
    bool isInitiallyExpanded = false,
  }) {
    final hasSearch = _searchQuery.trim().isNotEmpty;

    if (hasSearch && children.isEmpty) return const SizedBox.shrink();

    if (_isCollapsed) {
      return Tooltip(
        message: title,
        child: ListTile(
          leading: Icon(icon),
          title: const SizedBox.shrink(),
          dense: true,
          onTap: _toggleCollapse,
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title),
        initiallyExpanded: isInitiallyExpanded,
        children: children.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      hasSearch ? 'لا توجد نتائج مطابقة' : 'لا توجد عناصر',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              ]
            : children,
      ),
    );
  }
}
