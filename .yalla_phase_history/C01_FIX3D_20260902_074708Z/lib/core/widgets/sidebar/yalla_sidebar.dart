// ًں“پ lib/core/widgets/sidebar/yalla_sidebar.dart
//
// YallaSidebar â€” ظ†ط³ط®ط© ظ…ط·ط§ط¨ظ‚ط© ظ„ظ„ظ‡ظٹظƒظ„ ط§ظ„ظ…ط·ظ„ظˆط¨ + ط¥طµظ„ط§ط­ طھظ†ظ‚ظ„ ظٹظ…ظ†ط¹ طھط±ط§ظƒظ… ط§ظ„ط´ط§ط´ط§طھ.
// + ط¥ط¶ط§ظپط© ظ‚ط³ظ… ط§ظ„ط³ظ†ط¯ط§طھ ط§ظ„ظ…ط§ظ„ظٹط© (ط³ظ†ط¯ ظ‚ط¨ط¶ + ط³ظ†ط¯ طµط±ظپ) ظپظ‚ط· ظƒظ…ط§ ط·ظ„ط¨طھ.
// ظ„ط§ طھط؛ظٹظٹط± ط¹ظ„ظ‰ ط£ظٹ ط´ظٹط، ط¢ط®ط±.
//
// â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”â€”

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

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
  /*Start Trial*/
  Future<bool> _canAddNewRepairFromSidebar() async {
    final repairs = await RepairDatabaseService.getRepairsCount();
    const maxFreeRepairs = 1000000;

    print("Repairs: $repairs");
    if (repairs >= maxFreeRepairs) {
      if (!mounted) return false;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title:
              const Text('ًں”’ ط§ظ†طھظ‡ط§ط، ط§ظ„ظ†ط³ط®ط© ط§ظ„طھط¬ط±ظٹط¨ظٹط©'),
          content: const Text(
            'ظ„ظ‚ط¯ ظˆطµظ„طھ ط¥ظ„ظ‰ ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ظ„ظ„ظ†ط³ط®ط© ط§ظ„طھط¬ط±ظٹط¨ظٹط© (10 ظ…ظ„ظپط§طھ ط¥طµظ„ط§ط­).\n\n'
            'ظ„طھطھظ…ظƒظ† ظ…ظ† ط¥ط¶ط§ظپط© ظ…ط±ظƒط¨ط§طھ ط¬ط¯ظٹط¯ط©طŒ ظٹط±ط¬ظ‰ طھظپط¹ظٹظ„ ط§ظ„ط§ط´طھط±ط§ظƒ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ظ„ط§ط­ظ‚ظ‹ط§'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, AppRoutes.technicalSupport);
              },
              child: const Text('طھظˆط§طµظ„ ظ„طھظپط¹ظٹظ„ ط§ظ„ط§ط´طھط±ط§ظƒ'),
            ),
          ],
        ),
      );

      return false;
    }

    return true;
  }

  /*End Trial*/

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
  static const rTechnicalSupport = AppRoutes.technicalSupport;

  static const rSubscription = '/subscription';

// ===== ط§ظ„ط³ظ†ط¯ط§طھ ط§ظ„ظ…ط§ظ„ظٹط© =====
  static const rReceiptVoucher = AppRoutes.receiptVoucher;
  static const rReceiptVouchersList = AppRoutes.receiptVouchersList;
  static const rPaymentVoucher = AppRoutes.paymentVoucher;
  static const rPaymentVouchersList = AppRoutes.paymentVouchersList;
// ===== ظˆظƒظٹظ„ ط§ظ„طھط£ظ…ظٹظ† =====
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

  Future<void> _navigate(String route) async {
    if (_isNavigating || route.isEmpty) return;

    if (route == rRepairsAdd) {
      final allowed = await _canAddNewRepairFromSidebar();
      if (!allowed) return;
    }

    if (!mounted) return;

    final current =
        ModalRoute.of(context)?.settings.name ?? widget.currentRoute;
    final scaffoldState = Scaffold.maybeOf(context);
    final drawerIsOpen = scaffoldState?.isDrawerOpen == true ||
        scaffoldState?.isEndDrawerOpen == true;

    // A sidebar destination tap on phone must finish closing the Drawer before
    // replacing the route. Navigating during the drawer closing animation can
    // leave the old drawer/shell painted over the new page on iOS.
    if (drawerIsOpen) {
      scaffoldState?.closeDrawer();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
    }

    if (current == route) return;

    _isNavigating = true;
    try {
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true)
          .pushReplacementNamed(route);
    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _navigateAddParty() async {
    if (_isCollapsed) {
      _navigate(rClientAdd);
      return;
    }
    final sel = await showDialog<String>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('ط¥ط¶ط§ظپط© ط¬ظ‡ط©'),
        content: const Text('ط§ط®طھط± ظ†ظˆط¹ ط§ظ„ط¬ظ‡ط©:'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('client'),
              child: const Text('ط¹ظ…ظٹظ„')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop('supplier'),
              child: const Text('ظ…ظˆط±ط¯')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('ط¥ظ„ط؛ط§ط،')),
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
        title: const Text('ط§ظ„ط°ظ…ظ…'),
        content: const Text('ط§ط®طھط± ظ†ظˆط¹ ط§ظ„ط°ظ…ظ…:'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('ar'),
              child: const Text('ط°ظ…ظ… ط§ظ„ط¹ظ…ظ„ط§ط،')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop('ap'),
              child: const Text('ط°ظ…ظ… ط§ظ„ظ…ظˆط±ط¯ظٹظ†')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('ط¥ظ„ط؛ط§ط،')),
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

    // 1) ط¥طµظ„ط§ط­ ط§ظ„ظ…ط±ظƒط¨ط§طھ
    final repairsItems = [
      (Icons.dashboard, 'ط´ط§ط´ط© ط§ظ„ط¥طµظ„ط§ط­ط§طھ', rRepairsDashboard),
      (Icons.add, 'ط¥ط¯ط®ط§ظ„ ظ…ط±ظƒط¨ط© ط¬ط¯ظٹط¯ط©', rRepairsAdd),
      (Icons.list, 'ظ‚ط§ط¦ظ…ط© ط§ظ„ظ…ط±ظƒط¨ط§طھ', rVehiclesList),
      (Icons.bar_chart, 'طھظ‚ط§ط±ظٹط± ط§ظ„ط¥طµظ„ط§ط­', rRepairReports),
    ].where((e) => _matches(e.$2)).toList();

    // 2) ط´ط¤ظˆظ† ط§ظ„ظ…ظˆط¸ظپظٹظ†
    final employeesItems = [
      (Icons.list_alt, 'ظ‚ط§ط¦ظ…ط© ط§ظ„ظ…ظˆط¸ظپظٹظ†', rEmpList),
      (Icons.person_add, 'ط¥ط¶ط§ظپط© ظ…ظˆط¸ظپ', rEmpAdd),
      (Icons.receipt_long, 'ط§ظ„ط±ظˆط§طھط¨', rEmpSalaries),
      (Icons.savings, 'ط§ظ„ط³ظ„ظپ ظˆط§ظ„ظ…ظƒط§ظپط¢طھ', rEmpAdvances),
      (Icons.access_time, 'ط§ظ„ط­ط¶ظˆط± ظˆط§ظ„ط§ظ†طµط±ط§ظپ', rEmpAttendance),
    ].where((e) => _matches(e.$2)).toList();

    // 3) ط§ظ„ظ…ط´طھط±ظٹط§طھ
    final purchasesItems = [
      (Icons.add, 'ط¥ط¯ط®ط§ظ„ ظ…ط´طھط±ظٹط§طھ', rPurchCreate),
      (
        Icons.list_alt,
        'ظ‚ط§ط¦ظ…ط© ط§ظ„ظ…ط´طھط±ظٹط§طھ',
        AppRoutes.purchasesList
      ),
    ];

    // 4) ط§ظ„ط´ظٹظƒط§طھ
    final chequesItems = [
      (Icons.dashboard, 'ط´ط§ط´ط© ط§ظ„ط´ظٹظƒط§طھ', rChequesDashboard),
      (Icons.add, 'ط¥ط¶ط§ظپط© ط´ظٹظƒ', rChequesAdd),
      (Icons.list, 'ظ‚ط§ط¦ظ…ط© ط§ظ„ط´ظٹظƒط§طھ', rChequesList),
      (Icons.call_received, 'ط´ظٹظƒط§طھ ظˆط§ط±ط¯ط©', rChequesIncoming),
    ].where((e) => _matches(e.$2)).toList();

    // 5) ط§ظ„ط¹ظ…ظ„ط§ط، ظˆط§ظ„ظ…ظˆط±ط¯ظˆظ†
    final clientsSuppliersItems = <Widget>[];
    if (_matches('ظ‚ط§ط¦ظ…ط© ط§ظ„ط¹ظ…ظ„ط§ط،')) {
      clientsSuppliersItems.add(_tile(
          icon: Icons.people,
          title: 'ظ‚ط§ط¦ظ…ط© ط§ظ„ط¹ظ…ظ„ط§ط،',
          route: rClients));
    }

    if (_matches('ط¥ط¶ط§ظپط© ط¹ظ…ظٹظ„/ظ…ظˆط±ط¯')) {
      clientsSuppliersItems.add(_actionTile(
        icon: Icons.person_add_alt_1,
        title: 'ط¥ط¶ط§ظپط© ط¹ظ…ظٹظ„/ظ…ظˆط±ط¯',
        onTap: _navigateAddParty,
      ));
    }
    if (_matches('ط§ظ„ط°ظ…ظ… ط§ظ„ظ…ط¯ظٹظ†ط© ظˆط§ظ„ط¯ط§ط¦ظ†ط©')) {
      clientsSuppliersItems.add(_actionTile(
        icon: Icons.account_balance_wallet,
        title: 'ط§ظ„ط°ظ…ظ… ط§ظ„ظ…ط¯ظٹظ†ط© ظˆط§ظ„ط¯ط§ط¦ظ†ط©',
        onTap: _navigateAgingBoth,
      ));
    }

    // 6) ط§ظ„ظ…ط§ظ„ظٹط©
    final financeItems = [
      (Icons.dashboard, 'ظ„ظˆط­ط© ظ…ط§ظ„ظٹط©', rFinanceDashboard),
      (Icons.list_alt, 'ظ‚ظٹظˆط¯ ط§ظ„ظٹظˆظ…ظٹط©', rJournalEntries),
      (Icons.menu_book, 'ط¯ظپطھط± ط§ظ„ط£ط³طھط§ط°', rFinanceAccountLedger),
      (Icons.stacked_bar_chart, 'ظ‚ط§ط¦ظ…ط© ط§ظ„ط¯ط®ظ„', rIncomeStatement),
      (
        Icons.account_balance_wallet,
        'ط§ظ„ظ…ظٹط²ط§ظ†ظٹط© ط§ظ„ط¹ظ…ظˆظ…ظٹط©',
        rReportsBalanceSheet
      ),
    ].where((e) => _matches(e.$2)).toList();

    // ===== NEW: ط³ظ†ط¯ط§طھ ظ…ط§ظ„ظٹط© =====
    final vouchersItems = [
      (Icons.arrow_downward, 'ط³ظ†ط¯ ظ‚ط¨ط¶', rReceiptVoucher),
      (
        Icons.list_alt,
        'ظ‚ط§ط¦ظ…ط© ط³ظ†ط¯ط§طھ ط§ظ„ظ‚ط¨ط¶',
        rReceiptVouchersList
      ),
      (Icons.arrow_upward, 'ط³ظ†ط¯ طµط±ظپ', rPaymentVoucher),
      (Icons.list, 'ظ‚ط§ط¦ظ…ط© ط³ظ†ط¯ط§طھ ط§ظ„طµط±ظپ', rPaymentVouchersList),
    ].where((e) => _matches(e.$2)).toList();
// ===== NEW: ظˆظƒظٹظ„ ط§ظ„طھط£ظ…ظٹظ† =====
    final insuranceAgentItems = [
      (Icons.home, 'ط§ظ„ط´ط§ط´ط© ط§ظ„ط±ط¦ظٹط³ظٹط©', rInsuranceHome),
      (
        Icons.add_circle_outline,
        ' ط¥ط¶ط§ظپط© طھط£ظ…ظٹظ† ط¬ط¯ظٹط¯',
        rInsuranceAddNew
      ),
      (Icons.calculate, 'ط­ط§ط³ط¨ط© ط§ظ„طھط£ظ…ظٹظ†', rInsuranceCalculator),
      (Icons.list_alt, 'ظ‚ط§ط¦ظ…ط© ط§ظ„طھط£ظ…ظٹظ†ط§طھ', rInsurancePoliciesList),
      (Icons.contacts, 'ط¬ظ‡ط§طھ ط§ظ„ط§طھطµط§ظ„', rInsuranceContacts),
      (Icons.folder_shared, 'ظ…ط­ط§ظپط¸ ط§ظ„ظ…ظ†طھط¬ظٹظ†', rInsuranceProducers),
      (Icons.account_balance_wallet, 'ط§ظ„ظ…ط§ظ„ظٹط©', rInsuranceFinance),
      (
        Icons.notifications_active,
        'ط§ظ„طھظ†ط¨ظٹظ‡ط§طھ ظˆط§ظ„ظ…طھط§ط¨ط¹ط©',
        rInsuranceAlerts
      ),
      (Icons.print, 'ط§ظ„طھظ‚ط§ط±ظٹط± ظˆط§ظ„ط·ط¨ط§ط¹ط©', rInsuranceReports),
    ].where((e) => _matches(e.$2)).toList();

    // 7) ط§ظ„طھظ‚ط§ط±ظٹط±
    final reportsItems = [
      (Icons.dashboard, 'ظ„ظˆط­ط© ط§ظ„طھظ‚ط§ط±ظٹط±', rReportsDashboard),
      (
        Icons.check_circle,
        'طھظ‚ط§ط±ظٹط± ط­ط¶ظˆط± ظˆط؛ظٹط§ط¨',
        rReportsAttendance
      ),
      (Icons.balance, 'طھظ‚ط§ط±ظٹط± ظ…ط§ظ„ظٹط©', rReportsTrialBalance),
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
// ط¥ط®ظپط§ط، ظ…ط±ط¨ط¹ ط§ظ„ط¨ط­ط« ط¨ط¯ظˆظ† ط­ط°ظپظ‡
              Visibility(
                visible: false,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: false,
                child: (!_isCollapsed)
                    ? Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SidebarSearch(
                          initialQuery: _searchQuery,
                          onChanged: (q) => setState(() => _searchQuery = q),
                          hintText: 'ط¨ط­ط«...',
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
                        title: 'ظ„ظˆط­ط© ط§ظ„طھط­ظƒظ…',
                        route: rDashboard),

                    // ط¥طµظ„ط§ط­ ط§ظ„ظ…ط±ظƒط¨ط§طھ
                    if (repairsItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.build,
                        title: 'ط¥طµظ„ط§ط­ ط§ظ„ظ…ط±ظƒط¨ط§طھ',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rRepairsRoot) ??
                                false,
                        children: repairsItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),
                    // ===== NEW: ظˆظƒظٹظ„ ط§ظ„طھط£ظ…ظٹظ† =====
                    if (insuranceAgentItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.verified_user,
                        title: 'ظˆظƒظٹظ„ ط§ظ„طھط£ظ…ظٹظ†',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rInsuranceRoot) ??
                                false,
                        children: insuranceAgentItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // ===== NEW: ط§ظ„ط³ظ†ط¯ط§طھ ط§ظ„ظ…ط§ظ„ظٹط© =====
                    if (vouchersItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.receipt_long,
                        title: 'ط§ظ„ط³ظ†ط¯ط§طھ ط§ظ„ظ…ط§ظ„ظٹط©',
                        isInitiallyExpanded:
                            widget.currentRoute?.contains('voucher') ?? false,
                        children: vouchersItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // ط´ط¤ظˆظ† ط§ظ„ظ…ظˆط¸ظپظٹظ†
                    if (employeesItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.people_alt,
                        title: 'ط´ط¤ظˆظ† ط§ظ„ظ…ظˆط¸ظپظٹظ†',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rEmpRoot) ?? false,
                        children: employeesItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // ظ…ط´طھط±ظٹط§طھ
                    if (purchasesItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.shopping_cart,
                        title: 'ط§ظ„ظ…ط´طھط±ظٹط§طھ',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rPurchRoot) ??
                                false,
                        children: purchasesItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // ط§ظ„ط¹ظ…ظ„ط§ط، ظˆط§ظ„ظ…ظˆط±ط¯ظˆظ†
                    if (clientsSuppliersItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.group,
                        title: 'ط§ظ„ط¹ظ…ظ„ط§ط، ظˆط§ظ„ظ…ظˆط±ط¯ظˆظ†',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith('/clients') ==
                                    true ||
                                widget.currentRoute?.startsWith('/suppliers') ==
                                    true,
                        children: clientsSuppliersItems,
                      ),

                    // ط§ظ„ظ…ط§ظ„ظٹط©
                    if (financeItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.account_balance,
                        title: 'ط§ظ„ظ…ط§ظ„ظٹط©',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rFinanceRoot) ??
                                false,
                        children: financeItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

                    // ط´ظٹظƒط§طھ
                    if (chequesItems.isNotEmpty || !hasSearch)
                      _group(
                        icon: Icons.receipt_long,
                        title: 'ط§ظ„ط´ظٹظƒط§طھ',
                        isInitiallyExpanded:
                            widget.currentRoute?.startsWith(rChequesRoot) ??
                                false,
                        children: chequesItems
                            .map((e) =>
                                _tile(icon: e.$1, title: e.$2, route: e.$3))
                            .toList(),
                      ),

// ===== ط¥طµط¯ط§ط± ظ„ط§ط­ظ‚ (ظ‚ط³ظ… ط؛ظٹط± ظپط¹ظ‘ط§ظ„) =====
                    _group(
                      icon: Icons.lock_clock,
                      title: 'ط¥طµط¯ط§ط± ظ„ط§ط­ظ‚',
                      isInitiallyExpanded: false,
                      children: [
                        ListTile(
                          dense: true,
                          title: Text(
                            'ط¥ط¯ط§ط±ط© ط§ظ„ط´ظٹظƒط§طھ',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading: const Icon(Icons.receipt_long,
                              color: Colors.grey),
                          onTap: null, // ط؛ظٹط± ظ…ظپط¹ظ‘ظ„
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'ط°ظ…ظ… ط§ظ„ط¹ظ…ظ„ط§ط، ظˆط§ظ„ظ…ظˆط±ط¯ظٹظ†',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading: const Icon(Icons.account_balance_wallet,
                              color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'ط§ظ„طھظ‚ط§ط±ظٹط± ط§ظ„ظ…ط§ظ„ظٹط© ط§ظ„ظ…طھظ‚ط¯ظ…ط©',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading:
                              const Icon(Icons.assessment, color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'ط¥ط¯ط§ط±ط© ط§ظ„ظپظˆط§طھظٹط± ط§ظ„ظ…طھظ‚ط¯ظ…ط©',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading: const Icon(Icons.request_page,
                              color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'طھظ‚ط§ط±ظٹط± ط§ظ„ط±ظˆط§طھط¨',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading:
                              const Icon(Icons.payments, color: Colors.grey),
                          onTap: null,
                        ),
                        ListTile(
                          dense: true,
                          title: Text(
                            'ط¥ط¯ط§ط±ط© ط§ظ„ظ…ط®ط²ظˆظ†',
                            style: TextStyle(color: Colors.grey),
                          ),
                          leading:
                              const Icon(Icons.inventory_2, color: Colors.grey),
                          onTap: null,
                        ),
                      ],
                    ),

                    // ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ
                    _group(
                      icon: Icons.settings,
                      title: 'ط§ظ„ط¥ط¹ط¯ط§ط¯ط§طھ',
                      isInitiallyExpanded:
                          widget.currentRoute?.startsWith(rSettingsRoot) ??
                              false,
                      children: [
                        _tile(
                            icon: Icons.store,
                            title: 'ط¥ط¹ط¯ط§ط¯ط§طھ ط§ظ„ظˆط±ط´ط©',
                            route: rSettingsWorkshop),
                        _tile(
                            icon: Icons.support_agent,
                            title: 'ط§ظ„ط¯ط¹ظ… ط§ظ„ظپظ†ظٹ',
                            route: rTechnicalSupport),
                        ListTile(
                          leading:
                              const Icon(Icons.logout, color: Colors.redAccent),
                          title: _isCollapsed
                              ? const SizedBox.shrink()
                              : const Text('طھط³ط¬ظٹظ„ ط®ط±ظˆط¬',
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
                      hasSearch
                          ? 'ظ„ط§ طھظˆط¬ط¯ ظ†طھط§ط¦ط¬ ظ…ط·ط§ط¨ظ‚ط©'
                          : 'ظ„ط§ طھظˆط¬ط¯ ط¹ظ†ط§طµط±',
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
