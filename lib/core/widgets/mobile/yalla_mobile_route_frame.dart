import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

class YallaMobileRouteScope extends InheritedWidget {
  const YallaMobileRouteScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  final VoidCallback openDrawer;

  static YallaMobileRouteScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<YallaMobileRouteScope>();

  @override
  bool updateShouldNotify(YallaMobileRouteScope oldWidget) =>
      openDrawer != oldWidget.openDrawer;
}

/// Global authenticated phone shell.
///
/// On phone this is the single application-level drawer owner for routes that
/// do not intentionally own a complete phone shell. Feature screens can obtain
/// the drawer callback through [YallaMobileRouteScope] without creating a
/// nested Scaffold drawer.
class YallaMobileRouteFrame extends StatefulWidget {
  const YallaMobileRouteFrame({
    super.key,
    required this.routeName,
    required this.child,
  });

  final String routeName;
  final Widget child;

  @override
  State<YallaMobileRouteFrame> createState() => _YallaMobileRouteFrameState();
}

class _YallaMobileRouteFrameState extends State<YallaMobileRouteFrame> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _featureOwnedPhoneRoutes = <String>{
    AppRoutes.dashboard,
    AppRoutes.homeDashboard,
    AppRoutes.repairs,
    AppRoutes.repairsList,
    AppRoutes.repairsDashboard,
    AppRoutes.repairDetail,
    AppRoutes.repairReports,
    AppRoutes.repairAnalytics,
    AppRoutes.vehiclesArrears,
    AppRoutes.debts,
    AppRoutes.employeeDashboard,
    AppRoutes.employeeList,
    AppRoutes.employeeAdd,
    AppRoutes.employeeEdit,
    AppRoutes.employeeAttendance,
    AppRoutes.employeeAdvances,
    AppRoutes.employeePayroll,
    AppRoutes.financeDashboard,
    AppRoutes.collectionDashboard,
    AppRoutes.journalEntries,
    AppRoutes.incomeStatement,
    AppRoutes.expenses,
    AppRoutes.cashAccount,
    AppRoutes.bankAccount,
    AppRoutes.financeGL,
    AppRoutes.financeGeneralJournal,
    AppRoutes.financeAccountLedger,
    AppRoutes.receiptVoucher,
    AppRoutes.paymentVoucher,
    AppRoutes.purchasesDashboard,
    AppRoutes.purchasesList,
    AppRoutes.purchasesByMonth,
    AppRoutes.purchasesSuppliersAging,
    AppRoutes.purchasesSupplierLedger,
    AppRoutes.purchasesGLAudit,
    AppRoutes.chequesDashboard,
    AppRoutes.chequesAdd,
    AppRoutes.chequesEdit,
    AppRoutes.chequesList,
    AppRoutes.chequesIncoming,
    AppRoutes.chequesOutgoing,
    AppRoutes.chequesCollection,
    AppRoutes.chequesCollected,
    AppRoutes.chequesReturned,
    AppRoutes.chequesCancelled,
    AppRoutes.chequesPostdated,
    AppRoutes.chequesReport,
    AppRoutes.chequeBooks,
    AppRoutes.clientArrears,
    AppRoutes.rawMaterials,
    AppRoutes.rawMaterialAdd,
    AppRoutes.rawMaterialEdit,
    AppRoutes.suppliers,
    AppRoutes.suppliersPayablesList,
    AppRoutes.supplierCheques,
    AppRoutes.reportsDashboard,
    AppRoutes.reportsTrialBalance,
    AppRoutes.reportsGeneralLedger,
    AppRoutes.reportsBalanceSheet,
    AppRoutes.reportsAttendance,
    AppRoutes.reportsAdvances,
    AppRoutes.reportsPayroll,
    AppRoutes.insuranceAgentCalculator,
  };

  bool get _screenAlreadyOwnsPhoneNav =>
      _featureOwnedPhoneRoutes.contains(widget.routeName);

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) return widget.child;
    if (_screenAlreadyOwnsPhoneNav) return widget.child;

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: 300,
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: YallaSidebar(currentRoute: widget.routeName),
        ),
      ),
      body: YallaMobileRouteScope(
        openDrawer: _openDrawer,
        child: widget.child,
      ),
      bottomNavigationBar: YallaMobileBottomNav(
        currentRoute: widget.routeName,
        onMore: _openDrawer,
      ),
    );
  }
}
