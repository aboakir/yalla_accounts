// 📁 lib/core/widgets/sidebar/yalla_sidebar.dart
//
// YallaSidebar — نسخة مطابقة للهيكل المطلوب + إصلاح تنقل يمنع تراكم الشاشات.
// + إضافة قسم السندات المالية (سند قبض + سند صرف) فقط كما طلبت.
// لا تغيير على أي شيء آخر.
//
// ——————————————————————————————————————————————

import 'package:flutter/material.dart';
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
  bool _isNavigating = false; // Debounce

  // ===== Routes =====
  static const rDashboard = '/dashboard';

  // Repairs
  static const rRepairsRoot = '/repairs';
  static const rRepairsOverview = AppRoutes.repairs;
  static const rRepairsDashboard = '/repairs/dashboard';
  static const rRepairsAdd = '/repairs/add';
  static const rVehiclesList = AppRoutes.vehiclesList;
  static const rRepairReports = '/repairs/reports';
  static const rRepairAnalytics = AppRoutes.repairAnalytics;
  static const rVehiclesArrears = AppRoutes.vehiclesArrears;
  static const rRepairsDebts = AppRoutes.debts;

  // Employees
  static const rEmpRoot = '/employees';
  static const rEmpList = '/employees/list';
  static const rEmpAdd = '/employees/add';
  static const rEmpAttendance = '/employees/attendance';
  static const rEmpSalaries = '/employees/salaries';
  static const rEmpDashboard = AppRoutes.employeeDashboard;
  static const rReportsPayroll = AppRoutes.reportsPayroll;
  static const rReportsAdvances = AppRoutes.reportsAdvances;

  // Purchases
  static const rPurchRoot = '/purchases';
  static const rPurchList = AppRoutes.purchasesList;
  static const rPurchCreate = '/purchases/create';
  static const rPurchDashboard = AppRoutes.purchasesDashboard;
  static const rPurchPayments = AppRoutes.purchasePayments;
  static const rPurchByMonth = AppRoutes.purchasesByMonth;
  static const rPurchAging = AppRoutes.purchasesSuppliersAging;
  static const rPurchUnposted = AppRoutes.purchasesUnposted;
  static const rPurchAudit = AppRoutes.purchasesGLAudit;
  static const rPurchTools = AppRoutes.purchaseTools;
  static const rPurchPaint = AppRoutes.purchasePaint;
  static const rPurchInsurance = AppRoutes.purchaseInsurance;
  static const rPurchOther = AppRoutes.purchaseOther;

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
  static const rExpenses = AppRoutes.expenses;
  static const rCashAccount = AppRoutes.cashAccount;
  static const rBankAccount = AppRoutes.bankAccount;
  static const rFinanceGL = AppRoutes.financeGL;
  static const rFinanceGeneralJournal = AppRoutes.financeGeneralJournal;
  static const rReportsBalanceSheet = AppRoutes.reportsBalanceSheet;

  // Reports
  static const rReportsRoot = '/reports';
  static const rReportsDashboard = '/reports';
  static const rReportsAttendance = '/reports/attendance';
  static const rReportsTrialBalance = '/reports/trial-balance';
  static const rReportsARAging = AppRoutes.reportsARAging;
  static const rReportsGeneralLedger = AppRoutes.reportsGeneralLedger;

  // Settings
  static const rSettingsRoot = '/settings';
  static const rSettingsWorkshop = '/settings/workshop';
  static const rSettingsSecurityData = '/settings/security-data';
  static const rTechnicalSupport = AppRoutes.technicalSupport;

  static const rSubscription = '/subscription';
  static const rGlobalSearch = AppRoutes.globalSearch;
  static const rRawMaterials = AppRoutes.rawMaterials;
  static const rRawMaterialAdd = AppRoutes.rawMaterialAdd;

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
    if (_isNavigating || route.isEmpty) return;

    if (!mounted) return;
    if (!AppRoutes.isRegisteredRoute(route)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('هذا الرابط غير متاح حاليًا.')),
      );
      return;
    }

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
    _navigate('/parties/add');
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
    final enabled = !AppRoutes.isInsuranceAgentFrozenRoute(route);
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
        Icon(icon,
            color: enabled ? (active ? Colors.green : null) : Colors.grey),
        const SizedBox(width: 8),
        if (!_isCollapsed)
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color:
                      enabled ? (active ? Colors.green : null) : Colors.grey),
            ),
          ),
      ],
    );

    final tile = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: row,
      enabled: enabled,
      subtitle: !enabled && !_isCollapsed
          ? const Text('غير مفعّل حاليًا', style: TextStyle(fontSize: 11))
          : null,
      onTap: enabled ? () => _navigate(route) : null,
    );

    return _isCollapsed
        ? Tooltip(
            message: enabled ? title : '$title — غير مفعّل حاليًا', child: tile)
        : tile;
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
      (
        Icons.dashboard_customize_outlined,
        'نظرة عامة للإصلاحات',
        rRepairsOverview
      ),
      (Icons.dashboard, 'شاشة الإصلاحات', rRepairsDashboard),
      (
        Icons.folder_copy_outlined,
        'قائمة ملفات الإصلاح',
        AppRoutes.repairsList
      ),
      (Icons.add, 'إدخال مركبة جديدة', rRepairsAdd),
      (Icons.list, 'قائمة المركبات', rVehiclesList),
      (Icons.account_balance_wallet_outlined, 'ذمم المركبات', rVehiclesArrears),
      (Icons.receipt_long_outlined, 'الإصلاحات والذمم', rRepairsDebts),
      (Icons.analytics_outlined, 'تحليلات الإصلاح', rRepairAnalytics),
      (Icons.bar_chart, 'تقارير الإصلاح', rRepairReports),
    ].where((e) => _matches(e.$2)).toList();

    // 2) شؤون الموظفين
    final employeesItems = [
      (Icons.dashboard_outlined, 'لوحة الموظفين', rEmpDashboard),
      (Icons.list_alt, 'قائمة الموظفين', rEmpList),
      (Icons.person_add, 'إضافة موظف', rEmpAdd),
      (Icons.receipt_long, 'الرواتب', rEmpSalaries),
      (Icons.access_time, 'الحضور والانصراف', rEmpAttendance),
    ].where((e) => _matches(e.$2)).toList();

    // 3) المشتريات والمصروفات
    final purchasesItems = [
      (Icons.dashboard_outlined, 'لوحة المشتريات', rPurchDashboard),
      (Icons.add_shopping_cart, 'إدخال مشتريات', rPurchCreate),
      (Icons.format_paint_outlined, 'مشتريات مواد الدهان', rPurchPaint),
      (Icons.handyman_outlined, 'مشتريات العِدّة والأدوات', rPurchTools),
      (Icons.verified_user_outlined, 'مشتريات التأمين', rPurchInsurance),
      (Icons.more_horiz, 'مشتريات أخرى', rPurchOther),
      (Icons.list_alt, 'قائمة المشتريات', rPurchList),
      (Icons.calendar_month_outlined, 'المشتريات حسب الشهر', rPurchByMonth),
      (Icons.payments_outlined, 'مدفوعات الموردين', rPurchPayments),
      (Icons.timeline_outlined, 'أعمار ذمم الموردين', rPurchAging),
      (Icons.pending_actions_outlined, 'مشتريات غير مرحلة', rPurchUnposted),
      (Icons.fact_check_outlined, 'تدقيق قيود المشتريات', rPurchAudit),
    ].where((e) => _matches(e.$2)).toList();

    // 4) الشيكات
    final chequesItems = [
      (Icons.dashboard, 'لوحة الشيكات', rChequesDashboard),
      (Icons.add, 'إضافة شيك', rChequesAdd),
      (Icons.list, 'قائمة الشيكات', rChequesList),
      (Icons.call_received, 'شيكات واردة', rChequesIncoming),
      (Icons.call_made, 'شيكات صادرة', rChequesOutgoing),
      (
        Icons.account_balance_outlined,
        'إيداع وتحصيل الشيكات',
        rChequesCollection
      ),
      (Icons.verified_outlined, 'شيكات محصلة', rChequesCollected),
      (Icons.schedule_outlined, 'شيكات آجلة', rChequesPostdated),
      (Icons.undo, 'شيكات راجعة', rChequesReturned),
      (Icons.cancel_outlined, 'شيكات ملغاة', rChequesCancelled),
      (Icons.assessment_outlined, 'تقرير الشيكات', AppRoutes.chequesReport),
    ].where((e) => _matches(e.$2)).toList();

    // 5) العملاء والموردون
    final clientsSuppliersItems = <Widget>[];
    if (_matches('الجهات وكشف الحساب الشامل')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.contact_page,
          title: 'الجهات وكشف الحساب الشامل',
          route: '/parties'));
    }
    if (_matches('إضافة جهة')) {
      clientsSuppliersItems.add(_actionTile(
        icon: Icons.person_add_alt_1,
        title: 'إضافة جهة',
        onTap: _navigateAddParty,
      ));
    }
    if (_matches('قائمة العملاء')) {
      clientsSuppliersItems.add(
          _tile(icon: Icons.people, title: 'قائمة العملاء', route: rClients));
    }
    if (_matches('إضافة عميل')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.person_add_outlined,
          title: 'إضافة عميل',
          route: rClientAdd));
    }
    if (_matches('ذمم العملاء')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.request_page, title: 'ذمم العملاء', route: rClientAR));
    }
    if (_matches('قائمة الموردين')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.local_shipping_outlined,
          title: 'قائمة الموردين',
          route: rSuppliers));
    }
    if (_matches('إضافة مورد')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.person_add_alt_outlined,
          title: 'إضافة مورد',
          route: rSupplierAdd));
    }
    if (_matches('ذمم الموردين')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'ذمم الموردين',
          route: AppRoutes.suppliersPayablesList));
    }
    if (_matches('ديون الموردين')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.receipt_long_outlined,
          title: 'ديون الموردين',
          route: AppRoutes.suppliersDebts));
    }
    if (_matches('الذمم المدينة والدائنة')) {
      clientsSuppliersItems.add(_actionTile(
        icon: Icons.compare_arrows,
        title: 'الذمم المدينة والدائنة',
        onTap: _navigateAgingBoth,
      ));
    }

    // 6) المالية والمحاسبة
    final financeItems = [
      (Icons.dashboard, 'اللوحة المالية', rFinanceDashboard),
      (Icons.account_balance_wallet_outlined, 'الصندوق', rCashAccount),
      (Icons.account_balance_outlined, 'البنك', rBankAccount),
      (
        Icons.collections_bookmark_outlined,
        'التحصيل والذمم',
        rCollectionDashboard
      ),
      (Icons.payments_outlined, 'حركات الدفع والتحصيل', AppRoutes.payments),
      (Icons.stacked_bar_chart, 'قائمة الدخل', rIncomeStatement),
      (
        Icons.account_balance_wallet,
        'الميزانية العمومية',
        rReportsBalanceSheet
      ),
      (Icons.list_alt, 'قيود اليومية', rJournalEntries),
      (Icons.menu_book, 'دفتر الأستاذ', rFinanceAccountLedger),
      (Icons.receipt_long_outlined, 'اليومية العامة', rFinanceGeneralJournal),
      (Icons.manage_search_outlined, 'متصفح القيود المحاسبية', rFinanceGL),
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
      (
        Icons.receipt_long_outlined,
        'فواتير التأمين',
        AppRoutes.insuranceInvoices
      ),
      (Icons.add_circle_outline, 'إضافة تأمين جديد', rInsuranceAddNew),
      (Icons.calculate, 'حاسبة التأمين', rInsuranceCalculator),
      (Icons.list_alt, 'قائمة التأمينات', rInsurancePoliciesList),
      (Icons.contacts, 'جهات الاتصال', rInsuranceContacts),
      (Icons.folder_shared, 'محافظ المنتجين', rInsuranceProducers),
      (Icons.account_balance_wallet, 'المالية', rInsuranceFinance),
      (Icons.notifications_active, 'التنبيهات والمتابعة', rInsuranceAlerts),
      (Icons.print, 'التقارير والطباعة', rInsuranceReports),
    ].where((e) => _matches(e.$2)).toList();

    // 7) المخزون والمواد
    final inventoryItems = [
      (Icons.inventory_2_outlined, 'المواد الخام', rRawMaterials),
      (Icons.add_box_outlined, 'إضافة مادة خام', rRawMaterialAdd),
    ].where((e) => _matches(e.$2)).toList();

    // 8) التقارير
    final reportsItems = [
      (Icons.dashboard, 'لوحة التقارير', rReportsDashboard),
      (Icons.balance, 'ميزان المراجعة', rReportsTrialBalance),
      (Icons.schedule_outlined, 'تقادم ذمم العملاء', rReportsARAging),
      (Icons.menu_book_outlined, 'الأستاذ العام', rReportsGeneralLedger),
      (
        Icons.account_balance_wallet_outlined,
        'الميزانية العمومية',
        rReportsBalanceSheet
      ),
      (Icons.check_circle, 'تقرير الحضور والغياب', rReportsAttendance),
      (Icons.payments_outlined, 'تقرير الرواتب', rReportsPayroll),
      (Icons.savings_outlined, 'تقرير السلف والمكافآت', rReportsAdvances),
    ].where((e) => _matches(e.$2)).toList();

    return AnimatedBuilder(
      animation: _widthAnim,
      builder: (_, __) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: SizedBox(
            width: context.isDesktopWidth ? _widthAnim.value : 300,
            child: Column(
              children: [
                SidebarHeader(
                  isCollapsed: _isCollapsed,
                  onToggle: _toggleCollapse,
                  showToggle: context.isDesktopWidth,
                ),
// البحث داخل عناصر القائمة
                Visibility(
                  visible: true,
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
                      _tile(
                          icon: Icons.search,
                          title: 'البحث الشامل',
                          route: rGlobalSearch),

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
                              widget.currentRoute?.startsWith(rEmpRoot) ??
                                  false,
                          children: employeesItems
                              .map((e) =>
                                  _tile(icon: e.$1, title: e.$2, route: e.$3))
                              .toList(),
                        ),

                      // المشتريات والمصروفات
                      if (purchasesItems.isNotEmpty || !hasSearch)
                        _group(
                          icon: Icons.shopping_cart,
                          title: 'المشتريات',
                          isInitiallyExpanded:
                              (widget.currentRoute?.startsWith(rPurchRoot) ??
                                  false),
                          children: purchasesItems
                              .map((e) =>
                                  _tile(icon: e.$1, title: e.$2, route: e.$3))
                              .toList(),
                        ),

                      // العملاء والموردون
                      _tile(
                          icon: Icons.receipt_long_outlined,
                          title: 'المصروفات',
                          route: rExpenses),

                      if (clientsSuppliersItems.isNotEmpty || !hasSearch)
                        _group(
                          icon: Icons.group,
                          title: 'العملاء والموردون',
                          isInitiallyExpanded: widget.currentRoute
                                      ?.startsWith('/clients') ==
                                  true ||
                              widget.currentRoute?.startsWith('/suppliers') ==
                                  true ||
                              widget.currentRoute?.startsWith('/parties') ==
                                  true,
                          children: clientsSuppliersItems,
                        ),

                      // المالية والمحاسبة
                      if (financeItems.isNotEmpty || !hasSearch)
                        _group(
                          icon: Icons.account_balance,
                          title: 'المالية والمحاسبة',
                          isInitiallyExpanded:
                              widget.currentRoute?.startsWith(rFinanceRoot) ??
                                  false,
                          children: financeItems
                              .map((e) =>
                                  _tile(icon: e.$1, title: e.$2, route: e.$3))
                              .toList(),
                        ),

                      // الشيكات
                      if (chequesItems.isNotEmpty || !hasSearch)
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

                      // المخزون والمواد
                      if (inventoryItems.isNotEmpty || !hasSearch)
                        _group(
                          icon: Icons.inventory_2_outlined,
                          title: 'المخزون والمواد',
                          isInitiallyExpanded: widget.currentRoute
                                  ?.startsWith('/raw_materials') ??
                              false,
                          children: inventoryItems
                              .map((e) =>
                                  _tile(icon: e.$1, title: e.$2, route: e.$3))
                              .toList(),
                        ),

                      // التقارير
                      if (reportsItems.isNotEmpty || !hasSearch)
                        _group(
                          icon: Icons.assessment_outlined,
                          title: 'التقارير',
                          isInitiallyExpanded:
                              widget.currentRoute?.startsWith(rReportsRoot) ??
                                  false,
                          children: reportsItems
                              .map((e) =>
                                  _tile(icon: e.$1, title: e.$2, route: e.$3))
                              .toList(),
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
                              icon: Icons.verified_outlined,
                              title: 'حالة الاشتراك',
                              route: '/current-subscription'),
                          _tile(
                              icon: Icons.workspace_premium_outlined,
                              title: 'الاشتراك والخطط',
                              route: rSubscription),
                          _tile(
                              icon: Icons.support_agent,
                              title: 'الدعم الفني',
                              route: rTechnicalSupport),
                          ListTile(
                            leading: const Icon(Icons.logout,
                                color: Colors.redAccent),
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
