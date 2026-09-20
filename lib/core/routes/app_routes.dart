import 'package:yalla_accounts/features/parties/screens/parties_screen.dart';
// 📁 lib/core/routes/app_routes.dart
//
// Routes — v29a+
// - يمرّر RouteSettings لكل MaterialPageRoute للحفاظ على اسم المسار.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/config/owner_local_access.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_route_frame.dart';
import 'package:yalla_accounts/features/activation/screens/activation_screen.dart';
import 'package:yalla_accounts/features/auth/screens/login_screen.dart';
import 'package:yalla_accounts/features/auth/screens/forgot_access_screen.dart';
import 'package:yalla_accounts/features/auth/screens/logout_screen.dart';
import 'package:yalla_accounts/features/onboarding/screens/workshop_onboarding_screen.dart';
import 'package:yalla_accounts/features/auth/widgets/authenticated_route_gate.dart';

// ===== Core / Home =====
import 'package:yalla_accounts/core/widgets/under_construction_screen.dart';
import 'package:yalla_accounts/features/home/screens/dashboard_screen.dart';

// ===== agent =====
import 'package:yalla_accounts/features/insurance_agent/home/screens/insurance_agent_home_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/add_policy_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/policies_list_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/screens/insurance_contacts_list_screen.dart';

import 'package:yalla_accounts/features/insurance_agent/producers/screens/producers_portfolios_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/calculator/screens/insurance_calculator_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/alerts/screens/insurance_alerts_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/screens/insurance_finance_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/screens/insurance_reports_screen.dart';

// ===== Employees =====
import 'package:yalla_accounts/features/employees/screens/employee_dashboard_screen.dart';
import 'package:yalla_accounts/features/employees/screens/employees_list_screen.dart';
import 'package:yalla_accounts/features/employees/screens/add_employee_screen.dart';
import 'package:yalla_accounts/features/employees/screens/edit_employee_screen.dart';
import 'package:yalla_accounts/features/employees/screens/attendance_screen.dart';
import 'package:yalla_accounts/features/employees/screens/salary_screen.dart';
import 'package:yalla_accounts/features/employees/screens/employee_advances_screen.dart';
import 'package:yalla_accounts/features/employees/screens/payroll_screen.dart';

// ===== Finance =====
import 'package:yalla_accounts/features/finance/screens/finance_dashboard_screen.dart';
import 'package:yalla_accounts/features/finance/screens/journal_entries_screen.dart';
import 'package:yalla_accounts/features/finance/screens/income_statement_screen.dart';
import 'package:yalla_accounts/features/finance/screens/expenses_screen.dart';
import 'package:yalla_accounts/features/finance/screens/cash_account_screen.dart';
import 'package:yalla_accounts/features/finance/screens/bank_account_screen.dart';
import 'package:yalla_accounts/features/finance/screens/accounts_receivable_screen.dart';
import 'package:yalla_accounts/features/finance/screens/collection_dashboard_screen.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_browser_screen.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';
import 'package:yalla_accounts/features/finance/screens/account_ledger_screen.dart';
import 'package:yalla_accounts/features/finance/invoices/screens/invoice_view_screen.dart';
import 'package:yalla_accounts/features/finance/screens/general_journal_screen.dart';
import 'package:yalla_accounts/features/finance/payments/screens/payment_list_screen.dart';

// ===== Purchases =====
import 'package:yalla_accounts/features/finance/purchases/screens/purchases_dashboard_screen.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/purchases_by_month_screen.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/purchases_list_screen.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_create_screen.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/suppliers_aging_screen.dart'
    as sa;
import 'package:yalla_accounts/features/finance/purchases/screens/supplier_ledger_screen.dart'
    as sl;

// Aliases
import 'package:yalla_accounts/features/finance/purchases/screens/purchases_gl_audit_screen.dart'
    as pga;
import 'package:yalla_accounts/features/finance/purchases/screens/unposted_purchases_screen.dart'
    as up;

import 'package:yalla_accounts/features/finance/purchases/screens/supplier_payments_screen.dart';

// ===== Cheques =====
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_dashboard_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_add_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_list_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_incoming_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_outgoing_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_collection_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_collected_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_returned_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_cancelled_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_postdated_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_report_screen.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_books_screen.dart';
import 'package:yalla_accounts/features/suppliers/screens/supplier_cheques_screen.dart';

// ===== Repairs =====
import 'package:yalla_accounts/features/repairs/screens/repairs_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repairs_overview_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_reports_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_analytics_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/vehicles_arrears_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repairs_and_ar_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/vehicles_list_screen.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

// ===== Clients =====
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/screens/clients_screen.dart';
import 'package:yalla_accounts/features/clients/screens/client_edit_screen.dart';
import 'package:yalla_accounts/features/account_statements/customers/screens/customer_account_statement_screen.dart';

// ===== Insurance =====
import 'package:yalla_accounts/features/insurance/screens/insurance_invoice_list_screen.dart';
import 'package:yalla_accounts/features/reports/screens/reports_dashboard_screen.dart';

// ===== Reports =====
import 'package:yalla_accounts/features/reports/screens/trial_balance_screen.dart';
import 'package:yalla_accounts/features/finance/reports/screens/ar_aging_screen.dart';
import 'package:yalla_accounts/features/finance/reports/screens/balance_sheet_screen.dart';

// === Employees Reports ===
import 'package:yalla_accounts/features/employees/screens/advances_report_screen.dart';
import 'package:yalla_accounts/features/employees/screens/payroll_report_screen.dart';
import 'package:yalla_accounts/features/employees/screens/attendance_report_screen.dart';

// ===== Search =====
import 'package:yalla_accounts/features/search/screens/global_search_screen.dart';

// ===== Subscription =====
import 'package:yalla_accounts/features/subscription/screens/subscription_screen.dart';
import 'package:yalla_accounts/features/subscription/screens/current_subscription_screen.dart';
import 'package:yalla_accounts/features/subscription/screens/pending_subscriptions_screen.dart';

// ===== Settings =====
import 'package:yalla_accounts/features/settings/screens/workshop_settings_screen.dart';
import 'package:yalla_accounts/features/settings/screens/security_data_screen.dart';
import 'package:yalla_accounts/features/settings/screens/sync_conflicts_screen.dart';
import 'package:yalla_accounts/features/support/screens/technical_support_screen.dart';

// ===== Models =====
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

// ===== Suppliers =====
import 'package:yalla_accounts/features/suppliers/screens/suppliers_list_screen.dart';
import 'package:yalla_accounts/features/suppliers/screens/supplier_form_screen.dart';
import 'package:yalla_accounts/features/suppliers/screens/suppliers_payables_screen.dart';
import 'package:yalla_accounts/features/suppliers/screens/suppliers_debts_screen.dart';
import 'package:yalla_accounts/features/suppliers/screens/suppliers_payables_list_screen.dart';

// ===== Raw Materials =====
import 'package:yalla_accounts/features/raw_materials/models/raw_material.dart'
    as rm;
import 'package:yalla_accounts/features/raw_materials/screens/raw_material_list_screen.dart';
import 'package:yalla_accounts/features/raw_materials/screens/raw_material_edit_screen.dart';

// ===== Dev / Debug =====
import 'package:yalla_accounts/dev/dev_smoke_test.dart';

//// ===== السندات المالية  =====
import 'package:yalla_accounts/features/vouchers/screens/receipt_voucher_screen.dart';
import 'package:yalla_accounts/features/vouchers/screens/payment_voucher_screen.dart';
import 'package:yalla_accounts/features/vouchers/screens/payment_vouchers_list_screen.dart';
import 'package:yalla_accounts/features/vouchers/screens/receipt_vouchers_list_screen.dart';
import 'package:yalla_accounts/core/licensing/trial_expired_screen.dart';
import 'package:yalla_accounts/features/startup/startup_screen.dart';

class AppRoutes {
  AppRoutes._();
  // ===== Session check =====
//  static Future<bool> _isLoggedIn() async {
  // final prefs = await SharedPreferences.getInstance();
  // return prefs.getBool('loggedIn') == true;
  // }

  static final navigatorKey = GlobalKey<NavigatorState>();

  // ===== General =====
  static const splash = '/';
  static const login = '/login';
  static const logout = '/logout';
  static const register = '/register';
  static const dashboard = '/dashboard';
  static const homeDashboard = '/home/dashboard';
  static const forgotAccess = '/forgot-access';

// ===== Startup / Activation =====
  static const startup = '/startup';
  static const activation = '/activation';
  static const trialExpired = '/trial-expired';

  // ===== Roles =====
  static const admin = '/admin';
  static const managerDashboard = '/manager-dashboard';

  // ===== Repairs =====
  static const repairs = '/repairs';
  static const repairsList = '/repairs/list';
  static const repairsAdd = '/repairs/add';
  static const repairsDashboard = '/repairs/dashboard';
  static const repairDetail = '/repairs/detail';
  static const repairReports = '/repairs/reports';
  static const repairAnalytics = '/repairs/analytics';
  static const vehiclesList = '/repairs/vehicles';
  static const vehiclesArrears = '/repairs/vehicles/arrears';
  static const debts = '/repairs/debts';

  // ===== Employees =====
  static const employeeDashboard = '/employees';
  static const employeeList = '/employees/list';
  static const employeeAdd = '/employees/add';
  static const employeeEdit = '/employees/edit';
  static const employeeSalaries = '/employees/salaries';
  static const employeeAttendance = '/employees/attendance';
  static const employeeAdvances = '/employees/advances';
  static const employeePayroll = '/employees/payroll';

  // ===== Finance =====
  static const financeDashboard = '/finance/dashboard';
  static const collectionDashboard = '/finance/collections';
  static const payments = '/finance/payments';
// ===== Vouchers =====
  static const receiptVoucher = '/finance/receipt-voucher';
  static const paymentVoucher = '/finance/payment-voucher';
  static const paymentVouchersList = '/finance/payment-vouchers';
  static const receiptVouchersList = '/finance/receipt-vouchers';
  static const journalEntries = '/finance/journal/entries';
  static const incomeStatement = '/finance/income-statement';
  static const expenses = '/finance/expenses';
  static const cashAccount = '/finance/cash';
  static const bankAccount = '/finance/bank';
  static const financeGL = '/finance/gl';
  static const financeGLEntry = '/finance/gl/entry';
  static const financeAccountLedger = '/finance/account-ledger';
  static const invoiceView = '/finance/invoices/view';
  static const financeGeneralJournal = '/finance/general-journal';

  // ===== Purchases =====
  static const purchasesDashboard = '/purchases';
  static const purchaseTools = '/purchases/tools';
  static const purchasePaint = '/purchases/paint';
  static const purchaseInsurance = '/purchases/insurance';
  static const purchaseOther = '/purchases/other';
  static const purchasePayments = '/purchases/payments';
  static const purchasesList = '/purchases/list';
  static const purchaseCreate = '/purchases/create';
  static const purchasesByMonth = '/purchases/by-month';

  // ===== Cheques =====
  static const chequesDashboard = '/cheques/dashboard';
  static const chequesAdd = '/cheques/add';
  static const chequesEdit = '/cheques/edit';
  static const chequesList = '/cheques/list';
  static const chequesIncoming = '/cheques/incoming';
  static const chequesOutgoing = '/cheques/outgoing';
  static const chequesCollection = '/cheques/collection';
  static const chequesCollected = '/cheques/collected';
  static const chequesReturned = '/cheques/returned';
  static const chequesCancelled = '/cheques/cancelled';
  static const chequesPostdated = '/cheques/postdated';
  static const chequesReport = '/cheques/report';
  static const chequeBooks = '/cheques/books';

  // ===== Purchases extra =====
  static const purchasesSuppliersAging = '/purchases/suppliers-aging';
  static const purchasesSupplierLedger = '/purchases/supplier-ledger';
  static const purchasesGLAudit = '/purchases/gl-audit';
  static const purchasesUnposted = '/purchases/unposted';

  // ===== Clients =====
  static const clients = '/clients';
  static const clientsList = '/clients/list';
  static const clientAdd = '/clients/add';
  static const clientEdit = '/clients/edit';
  static const clientStatement = '/clients/statement';
  static const clientArrears = '/clients/accounts-receivable';
  static const parties = '/parties';
  static const partyAdd = '/parties/add';

// ===== Suppliers =====
  static const suppliers = '/suppliers'; // SupplierListScreen
  static const suppliersPayablesList = '/suppliers/payables-list';

  static const supplierAdd = '/suppliers/add'; // SupplierFormScreen
  static const supplierPayables =
      '/suppliers/payables'; // SupplierPayablesScreen
  static const suppliersDebts = '/suppliers/debts'; // SuppliersDebtsScreen
  static const supplierCheques = '/suppliers/cheques';

  // ===== Inventory =====
  static const rawMaterials = '/raw_materials';
  static const rawMaterialAdd = '/raw_materials/add';
  static const rawMaterialEdit = '/raw_materials/edit';
  static const inventory = '/inventory';

  // ===== Insurance =====
  static const insuranceInvoices = '/insurance/invoices';
// ===== Insurance Agent (وكيل التأمين) =====
  static const insuranceAgentRoot = '/insurance-agent';
  static const insuranceAgentHome = '/insurance-agent/home';
  static const insurancePoliciesList = '/insurance-agent/policies';

  static const insuranceAgentAddNew = '/insurance-agent/add';
  static const insuranceAgentProducers = '/insurance-agent/producers';
  static const insuranceAgentCalculator = '/insurance-agent/calculator';
  static const insuranceAgentFinance = '/insurance-agent/finance';
  static const insuranceAgentAlerts = '/insurance-agent/alerts';
  static const insuranceAgentReports = '/insurance-agent/reports';
  static const insuranceAgentContacts = '/insurance-agent/contacts';

  // ===== Reports =====
  static const reportsDashboard = '/reports';
  static const reportsTrialBalance = '/reports/trial-balance';
  static const reportsARAging = '/reports/ar-aging';
  static const reportsGeneralLedger = '/reports/general-ledger';
  static const reportsBalanceSheet = '/reports/balance-sheet';

  // === Employees Reports ===
  static const reportsAttendance = '/reports/attendance';
  static const reportsAdvances = '/reports/advances';
  static const reportsPayroll = '/reports/payroll';

  // ===== Search =====
  static const globalSearch = '/search';

  // ===== Settings / Subscription =====
  static const settings = '/settings';
  static const settingsWorkshop = '/settings/workshop';
  static const settingsUser = '/settings/user';
  static const settingsUI = '/settings/ui';
  static const settingsSupport = '/settings/support';
  static const settingsSecurityData = '/settings/security-data';
  static const settingsSyncConflicts = '/settings/sync-conflicts';
  static const subscription = '/subscription';
  static const subscriptionScreen = subscription;
  static const currentSubscription = '/current-subscription';
  static const adminSubscriptions = '/admin-subscriptions';
  static const technicalSupport = '/support/technical';

  // ===== Dev / Debug =====
  static const devSmoke = '/dev/smoke';

  /// Single source of truth for named navigation.
  /// Any new pushNamed target must be added here and handled by onGenerateRoute.
  static const Set<String> registeredRoutes = {
    splash,
    login,
    logout,
    register,
    dashboard,
    homeDashboard,
    forgotAccess,
    startup,
    activation,
    trialExpired,
    admin,
    managerDashboard,
    repairs,
    repairsList,
    repairsAdd,
    repairsDashboard,
    repairDetail,
    repairReports,
    repairAnalytics,
    vehiclesList,
    vehiclesArrears,
    debts,
    employeeDashboard,
    employeeList,
    employeeAdd,
    employeeEdit,
    employeeSalaries,
    employeeAttendance,
    employeeAdvances,
    employeePayroll,
    financeDashboard,
    collectionDashboard,
    payments,
    receiptVoucher,
    paymentVoucher,
    paymentVouchersList,
    receiptVouchersList,
    journalEntries,
    incomeStatement,
    expenses,
    cashAccount,
    bankAccount,
    financeGL,
    financeGLEntry,
    financeAccountLedger,
    invoiceView,
    financeGeneralJournal,
    purchasesDashboard,
    purchaseTools,
    purchasePaint,
    purchaseInsurance,
    purchaseOther,
    purchasePayments,
    purchasesList,
    purchaseCreate,
    purchasesByMonth,
    chequesDashboard,
    chequesAdd,
    chequesEdit,
    chequesList,
    chequesIncoming,
    chequesOutgoing,
    chequesCollection,
    chequesCollected,
    chequesReturned,
    chequesCancelled,
    chequesPostdated,
    chequesReport,
    chequeBooks,
    purchasesSuppliersAging,
    purchasesSupplierLedger,
    purchasesGLAudit,
    purchasesUnposted,
    clients,
    clientsList,
    clientAdd,
    clientEdit,
    clientStatement,
    clientArrears,
    parties,
    partyAdd,
    suppliers,
    suppliersPayablesList,
    supplierAdd,
    supplierPayables,
    suppliersDebts,
    supplierCheques,
    rawMaterials,
    rawMaterialAdd,
    rawMaterialEdit,
    inventory,
    insuranceInvoices,
    insuranceAgentRoot,
    insuranceAgentHome,
    insurancePoliciesList,
    insuranceAgentAddNew,
    insuranceAgentProducers,
    insuranceAgentCalculator,
    insuranceAgentFinance,
    insuranceAgentAlerts,
    insuranceAgentReports,
    insuranceAgentContacts,
    reportsDashboard,
    reportsTrialBalance,
    reportsARAging,
    reportsGeneralLedger,
    reportsBalanceSheet,
    reportsAttendance,
    reportsAdvances,
    reportsPayroll,
    globalSearch,
    settings,
    settingsWorkshop,
    settingsUser,
    settingsUI,
    settingsSupport,
    settingsSecurityData,
    settingsSyncConflicts,
    subscription,
    currentSubscription,
    adminSubscriptions,
    technicalSupport,
    devSmoke,
  };

  static bool isRegisteredRoute(String route) =>
      registeredRoutes.contains(route);

  static Future<T?> pushNamedSafe<T extends Object?>(
    BuildContext context,
    String route, {
    Object? arguments,
    bool rootNavigator = false,
  }) {
    if (!isRegisteredRoute(route)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('هذا الرابط غير متاح حاليًا.')),
      );
      return Future<T?>.value();
    }
    return Navigator.of(context, rootNavigator: rootNavigator)
        .pushNamed<T>(route, arguments: arguments);
  }

  // ===== P1.002 Auth guards =====
  static const Set<String> _publicRoutes = {
    splash,
    startup,
    login,
    logout,
    register,
    forgotAccess,
    activation,
    trialExpired,
  };

  static const Set<String> _ownerRoutes = {
    admin,
    settings,
    settingsWorkshop,
    settingsUser,
    settingsUI,
    settingsSecurityData,
    settingsSyncConflicts,
    subscription,
    currentSubscription,
    adminSubscriptions,
    devSmoke,
  };

  // ===== Helpers =====
  static MaterialPageRoute<T> _page<T>(
    RouteSettings settings,
    Widget child,
  ) {
    final routeName = settings.name ?? '';
    final isPublic = _publicRoutes.contains(routeName);
    final ownerOnly = _ownerRoutes.contains(routeName);

    return MaterialPageRoute<T>(
      builder: (_) => isPublic
          ? child
          : AuthenticatedRouteGate(
              ownerOnly: ownerOnly,
              child: YallaMobileRouteFrame(
                routeName: routeName,
                child: child,
              ),
            ),
      settings: settings,
    );
  }

  static MaterialPageRoute _under(RouteSettings settings, String title) =>
      _page(settings, UnderConstructionScreen(title: title));

  static MaterialPageRoute _fallback(
    RouteSettings requested,
    String fallbackRoute,
    Widget child,
    String message,
  ) {
    return _page(
      RouteSettings(name: fallbackRoute),
      _RouteFallbackNotice(message: message, child: child),
    );
  }

  // ===== Router =====
  // Keep the calculator available while the other agent sections are paused.
  static bool isInsuranceAgentFrozenRoute(String route) =>
      (route == insuranceAgentRoot ||
          route.startsWith('$insuranceAgentRoot/')) &&
      route != insuranceAgentCalculator;

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '';

    if (OwnerLocalAccess.enabled &&
        (name == login ||
            name == register ||
            name == logout ||
            name == forgotAccess ||
            name == activation ||
            name == trialExpired)) {
      return _page(
        const RouteSettings(name: startup),
        const StartupScreen(),
      );
    }

    if (isInsuranceAgentFrozenRoute(name)) {
      return _page(
          settings,
          Scaffold(
            appBar: AppBar(title: const Text('وكيل التأمين')),
            body: const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'هذا القسم غير مفعّل حاليًا. حاسبة التأمين متاحة من القائمة.',
                  textAlign: TextAlign.center),
            )),
          ));
    }

    if (name == login) {
      return _page(settings, const LoginScreen());
    }
    if (name == forgotAccess) {
      return _page(settings, const ForgotAccessScreen());
    }
    if (name == register) {
      return _page(settings, const WorkshopOnboardingScreen());
    }
    if (name == logout) {
      return _page(settings, const LogoutScreen());
    }
    if (name == dashboard || name == homeDashboard) {
      return _page(settings, const DashboardScreen());
    }
    if (name == splash || name == startup) {
      return _page(settings, const StartupScreen());
    }
    if (name == activation) {
      return _page(settings, const ActivationScreen());
    }
    if (name == trialExpired) {
      return _page(settings, const TrialExpiredScreen());
    }

    // Roles
    if (name == admin) {
      return _under(settings, 'لوحة الإدارة');
    }
    if (name == managerDashboard) {
      return _under(settings, 'لوحة المدير');
    }

    // Repairs
    if (name == vehiclesList) {
      return _page(settings, const VehiclesListScreen());
    }

    if (name == repairs) {
      return _page(settings, const RepairsOverviewScreen());
    }
    if (name == repairsList) {
      return _page(settings, const RepairsScreen(showAll: true));
    }
    if (name == repairsAdd) {
      return _page(settings, const AddRepairScreen());
    }
    if (name == repairsDashboard) {
      return _page(settings, const RepairsScreen());
    }
    if (name == repairDetail) {
      final args = settings.arguments;
      if (args is! Repair) {
        return _fallback(
          settings,
          repairsList,
          const RepairsScreen(showAll: true),
          'تعذر فتح ملف الإصلاح لأن بياناته غير مكتملة. أعدناك إلى قائمة الإصلاحات.',
        );
      }
      return _page(settings, RepairDetailsScreen(repair: args));
    }
    if (name == repairReports) {
      return _page(settings, const RepairReportsScreen());
    }
    if (name == repairAnalytics) {
      return _page(settings, const RepairAnalyticsScreen());
    }

    if (name == vehiclesArrears) {
      return _page(settings, const VehiclesArrearsScreen());
    }
    if (name == debts) {
      return _page(settings, const RepairsAndARScreen());
    }

    // Employees
    if (name == employeeDashboard) {
      return _page(settings, const EmployeeDashboardScreen());
    }
    if (name == employeeList) {
      return _page(settings, const EmployeesListScreen());
    }
    if (name == employeeAdd) {
      return _page(settings, const AddEmployeeScreen());
    }
    if (name == employeeEdit) {
      final args = settings.arguments;
      if (args is! Employee) {
        return _fallback(
          settings,
          employeeList,
          const EmployeesListScreen(),
          'تعذر فتح تعديل الموظف لأن بيانات الموظف غير متاحة.',
        );
      }
      return _page(settings, EditEmployeeScreen(employee: args));
    }
    if (name == employeeSalaries) {
      return _page(settings, const SalaryScreen());
    }
    if (name == employeeAttendance) {
      return _page(settings, const AttendanceScreen());
    }
    if (name == employeeAdvances) {
      final args = settings.arguments;
      if (args is! Employee) {
        return _fallback(
          settings,
          employeeList,
          const EmployeesListScreen(),
          'تعذر فتح سلف الموظف لأن بيانات الموظف غير متاحة.',
        );
      }
      return _page(settings, EmployeeAdvancesScreen(employee: args));
    }
    if (name == employeePayroll) {
      final args = settings.arguments;
      if (args is! Employee) {
        return _fallback(
          settings,
          employeeList,
          const EmployeesListScreen(),
          'تعذر فتح رواتب الموظف لأن بيانات الموظف غير متاحة.',
        );
      }
      return _page(settings, PayrollScreen(employee: args));
    }

    // Finance
    if (name == financeDashboard) {
      return _page(settings, const FinanceDashboardScreen());
    }
    if (name == payments) {
      final args = settings.arguments;
      String? repairId;
      String? paymentId;
      var allowReverse = false;
      if (args is Map) {
        repairId = (args['repairId'] ?? args['relatedRepairId'])?.toString();
        paymentId = args['paymentId']?.toString();
        allowReverse = args['allowReverse'] == true;
      }
      return _page(
        settings,
        PaymentListScreen(
          initialRepairId: repairId,
          initialPaymentId: paymentId,
          allowReverse: allowReverse,
        ),
      );
    }

    if (name == journalEntries) {
      final args = settings.arguments;
      String? repairId;
      if (args is Map) {
        repairId = (args['relatedRepairId'] ?? args['repairId'])?.toString();
      }
      return _page(
        settings,
        JournalEntriesScreen(initialRepairId: repairId),
      );
    }
    if (name == incomeStatement) {
      return _page(settings, const IncomeStatementScreen());
    }
    if (name == expenses) {
      return _page(settings, const ExpensesScreen());
    }
    if (name == cashAccount) {
      return _page(settings, const CashAccountScreen());
    }
    if (name == bankAccount) {
      return _page(settings, const BankAccountScreen());
    }
    if (name == financeGL) {
      return _page(settings, const GLBrowserScreen());
    }
    if (name == financeGLEntry) {
      final args = settings.arguments;
      int? entryId;
      if (args is int) entryId = args;
      if (entryId == null && args is String) entryId = int.tryParse(args);
      if (entryId == null && args is Map && args['entryId'] != null) {
        final v = args['entryId'];
        entryId = v is int ? v : int.tryParse('$v');
      }
      if (entryId == null) {
        return _fallback(
          settings,
          financeGL,
          const GLBrowserScreen(),
          'تعذر فتح القيد لأن رقم القيد غير متاح. أعدناك إلى الأستاذ العام.',
        );
      }
      return _page(settings, GLEntryScreen(entryId: entryId));
    }
    if (name == financeGeneralJournal) {
      return _page(settings, const GeneralJournalScreen());
    }
    if (name == financeAccountLedger) {
      return _page(settings, const AccountLedgerScreen());
    }
    if (name == invoiceView) {
      final args = settings.arguments;
      if (args is String) {
        return _page(settings, InvoiceViewScreen(invoiceId: args));
      }
      if (args is Map && args['invoiceId'] is String) {
        return _page(settings, InvoiceViewScreen(invoiceId: args['invoiceId']));
      }
      return _fallback(
        settings,
        financeDashboard,
        const FinanceDashboardScreen(),
        'تعذر فتح الفاتورة لأن رقمها غير متاح. أعدناك إلى اللوحة المالية.',
      );
    }
// Finance - Vouchers
    if (name == receiptVoucher) {
      final args = settings.arguments;
      if (args is Map) {
        final clientRaw = args['clientId'];
        final clientId = clientRaw is int
            ? clientRaw
            : int.tryParse(clientRaw?.toString() ?? '');

        return _page(
          settings,
          ReceiptVoucherScreen(
            initialRepairId:
                (args['repairId'] ?? args['relatedRepairId'])?.toString(),
            initialClientId: clientId,
            initialClientType: args['clientType']?.toString(),
          ),
        );
      }

      return _page(settings, const ReceiptVoucherScreen());
    }
    if (name == paymentVoucher) {
      return _page(settings, const PaymentVoucherScreen());
    }
// LIST — Payment Vouchers
    if (name == paymentVouchersList) {
      return _page(settings, const PaymentVoucherListScreen());
    }
// LIST — Receipt Vouchers
    if (name == receiptVouchersList) {
      return _page(settings, const ReceiptVoucherListScreen());
    }

    // Purchases
    if (name == purchasesDashboard) {
      return _page(settings, const PurchasesDashboardScreen());
    }
    if (name == purchaseTools) {
      return _page(
        settings,
        const PurchaseCreateScreen(initialPurchaseType: 'TOOLS'),
      );
    }
    if (name == purchasePaint) {
      return _page(
        settings,
        const PurchaseCreateScreen(initialPurchaseType: 'PAINT'),
      );
    }
    if (name == purchaseInsurance) {
      return _page(
        settings,
        const PurchaseCreateScreen(
          initialPurchaseType: 'OTHER',
          initialNote: 'تأمين',
        ),
      );
    }
    if (name == purchaseOther) {
      return _page(
        settings,
        const PurchaseCreateScreen(initialPurchaseType: 'OTHER'),
      );
    }
    if (name == purchasePayments) {
      return _page(settings, const SupplierPaymentsScreen());
    }
    if (name == purchasesList) {
      return _page(settings, const PurchasesListScreen());
    }
    if (name == purchaseCreate) {
      return _page(settings, const PurchaseCreateScreen());
    }
    if (name == purchasesByMonth) {
      return _page(settings, const PurchasesByMonthScreen());
    }

    // Cheques
    if (name == chequesDashboard) {
      return _page(settings, const ChequesDashboardScreen());
    }
    if (name == chequesAdd) {
      return _page(settings, const ChequeAddScreen());
    }
    if (name == chequesEdit) {
      final args = settings.arguments;
      if (args is! Cheque) {
        return _fallback(
          settings,
          chequesList,
          const ChequesListScreen(),
          'تعذر فتح تعديل الشيك لأن بيانات الشيك غير متاحة.',
        );
      }
      return _page(settings, ChequeAddScreen(editCheque: args));
    }
    if (name == chequesList) {
      return _page(settings, const ChequesListScreen());
    }
    if (name == chequesIncoming) {
      return _page(settings, const ChequesIncomingScreen());
    }
    if (name == chequesOutgoing) {
      return _page(settings, const ChequesOutgoingScreen());
    }
    if (name == chequesCollection) {
      return _page(settings, const ChequesCollectionScreen());
    }
    if (name == chequesCollected) {
      return _page(settings, const ChequesCollectedScreen());
    }
    if (name == chequesReturned) {
      return _page(settings, const ChequesReturnedScreen());
    }
    if (name == chequesCancelled) {
      return _page(settings, const ChequesCancelledScreen());
    }
    if (name == chequesPostdated) {
      return _page(settings, const ChequesPostdatedScreen());
    }
    if (name == chequesReport) {
      return _page(settings, const ChequesReportScreen());
    }
    if (name == chequeBooks) {
      return _page(settings, const ChequeBooksScreen());
    }

    // Purchases → Suppliers GL reports
    if (name == purchasesSuppliersAging) {
      return _page(settings, const sa.SuppliersAgingScreen());
    }
    if (name == purchasesSupplierLedger) {
      final args = settings.arguments;
      if (args is Map &&
          args['supplierId'] is String &&
          args['supplierName'] is String) {
        return _page(
          settings,
          sl.SupplierLedgerScreen(
            supplierId: args['supplierId'],
            supplierName: args['supplierName'],
          ),
        );
      }
      return _fallback(
        settings,
        suppliers,
        const SupplierListScreen(),
        'تعذر فتح دفتر المورد لأن بيانات المورد غير مكتملة.',
      );
    }

    // Purchases → GL audits
    if (name == purchasesGLAudit) {
      return _page(settings, const pga.PurchasesGLAuditScreen());
    }
    if (name == purchasesUnposted) {
      return _page(settings, const up.UnpostedPurchasesScreen());
    }

    // Clients
    if (name == parties) {
      return _page(settings, const PartiesScreen());
    }
    if (name == partyAdd) {
      return _page(settings, const PartyFormScreen());
    }
    if (name == clients || name == clientsList) {
      return _page(settings, const ClientsScreen());
    }
    if (name == clientAdd) {
      return _page(settings, const ClientEditScreen());
    }
    if (name == clientEdit) {
      final args = settings.arguments;
      if (args is! Client) {
        return _fallback(
          settings,
          clients,
          const ClientsScreen(),
          'تعذر فتح تعديل العميل لأن بيانات العميل غير متاحة.',
        );
      }
      return _page(settings, ClientEditScreen(client: args));
    }
    if (name == clientStatement) {
      final args = settings.arguments;
      final rawId = args is Map ? args['clientId'] : null;
      final clientId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      final clientName =
          args is Map ? args['clientName']?.toString().trim() : null;
      if (clientId == null) {
        return _fallback(
          settings,
          clients,
          const ClientsScreen(),
          'تعذر فتح كشف حساب العميل لأن رقم العميل غير متاح.',
        );
      }
      return _page(
        settings,
        CustomerAccountStatementScreen(
          clientId: clientId,
          clientName:
              (clientName?.isNotEmpty ?? false) ? clientName! : 'العميل',
        ),
      );
    }
    if (name == clientArrears) {
      return _page(settings, const AccountsReceivableScreen());
    }
    if (name == collectionDashboard) {
      return _page(settings, const CollectionDashboardScreen());
    }

    // Insurance
    if (name == insuranceInvoices) {
      return _page(settings, const InsuranceInvoiceListScreen());
    }
// Insurance Agent (وكيل التأمين)
    if (name == insuranceAgentRoot || name == insuranceAgentHome) {
      return _page(settings, const InsuranceAgentHomeScreen());
    }
    if (name == insurancePoliciesList) {
      return _page(settings, const PoliciesListScreen());
    }

    if (name == insuranceAgentAddNew) {
      return _page(settings, const AddPolicyScreen());
    }
    if (name == insuranceAgentProducers) {
      return _page(settings, const ProducersPortfoliosScreen());
    }
    if (name == insuranceAgentCalculator) {
      return _page(settings, const InsuranceCalculatorScreen());
    }
    if (name == insuranceAgentFinance) {
      return _page(settings, const InsuranceFinanceScreen());
    }
    if (name == insuranceAgentAlerts) {
      return _page(settings, const InsuranceAlertsScreen());
    }
    if (name == insuranceAgentReports) {
      return _page(settings, const InsuranceReportsScreen());
    }
    if (name == insuranceAgentContacts) {
      return _page(settings, const InsuranceContactsListScreen());
    }

    // Inventory
    if (name == rawMaterials) {
      return _page(settings, const RawMaterialListScreen());
    }
    if (name == rawMaterialAdd) {
      return _page(settings,
          const RawMaterialEditScreen(material: null, rawMaterial: null));
    }
    if (name == rawMaterialEdit) {
      final args = settings.arguments;
      if (args is rm.RawMaterial) {
        return _page(
            settings, RawMaterialEditScreen(material: args, rawMaterial: null));
      }
      return _fallback(
        settings,
        rawMaterials,
        const RawMaterialListScreen(),
        'تعذر فتح تعديل المادة لأن بياناتها غير متاحة.',
      );
    }
    if (name == inventory) {
      return _under(settings, 'شاشة الجرد والمخزون');
    }

// ===== Suppliers =====
    if (name == suppliersPayablesList) {
      return _page(settings, const SupplierPayablesListScreen());
    }

    if (name == suppliers) {
      return _page(settings, const SupplierListScreen());
    }

    if (name == supplierAdd) {
      return _page(settings, const SupplierFormScreen());
    }

    /// Supplier Payables — requires supplierId + supplierName
    if (name == supplierPayables) {
      final args = settings.arguments;

      if (args is! Map || args['supplierId'] == null) {
        return _fallback(
          settings,
          suppliers,
          const SupplierListScreen(),
          'تعذر فتح حساب المورد لأن بيانات المورد غير مكتملة.',
        );
      }

      final supplierId = args['supplierId'].toString();
      final supplierName = args['supplierName']?.toString().trim();
      return _page(
        settings,
        SupplierPayablesScreen(
          supplierId: supplierId,
          supplierName:
              (supplierName?.isNotEmpty ?? false) ? supplierName! : 'المورد',
        ),
      );
    }

    /// Suppliers Debts
    if (name == suppliersDebts) {
      return _page(settings, const SuppliersDebtsScreen());
    }

    // Reports
    if (name == reportsDashboard) {
      return _page(settings, const ReportsDashboardScreen());
    }
    if (name == reportsTrialBalance) {
      return _page(settings, const TrialBalanceScreen());
    }
    if (name == reportsARAging) {
      return _page(settings, const ARAgingScreen());
    }
    if (name == reportsGeneralLedger) {
      return _page(settings, const GLBrowserScreen());
    }
    if (name == reportsBalanceSheet) {
      return _page(settings, const BalanceSheetScreen());
    }
// Supplier Cheques
    if (name == supplierCheques) {
      final args = settings.arguments;

      if (args is! Map || args['supplierPid'] == null) {
        return _fallback(
          settings,
          suppliers,
          const SupplierListScreen(),
          'تعذر فتح شيكات المورد لأن بيانات المورد غير مكتملة.',
        );
      }

      final supplierPid = args['supplierPid'].toString();
      final supplierName = args['supplierName']?.toString().trim();
      return _page(
        settings,
        SupplierChequesScreen(
          supplierPid: supplierPid,
          supplierName:
              (supplierName?.isNotEmpty ?? false) ? supplierName! : 'المورد',
        ),
      );
    }

    // Employees Reports
    if (name == reportsAttendance) {
      return _page(settings, const AttendanceReportScreen());
    }
    if (name == reportsAdvances) {
      return _page(settings, const AdvancesReportScreen());
    }
    if (name == reportsPayroll) {
      return _page(settings, const PayrollReportScreen());
    }

    // Search
    if (name == globalSearch) {
      return _page(settings, const GlobalSearchScreen());
    }

    // Settings
    if (name == AppRoutes.settings || name == settingsWorkshop) {
      return _page(settings, const WorkshopSettingsScreen());
    }
    if (name == settingsUser) {
      return _under(settings, 'إعدادات المستخدم');
    }
    if (name == settingsUI) {
      return _under(settings, 'إعدادات الواجهة');
    }
    if (name == settingsSecurityData) {
      return _page(settings, const SecurityDataScreen());
    }
    if (name == settingsSyncConflicts) {
      return _page(settings, const SyncConflictsScreen());
    }
    if (name == settingsSupport || name == technicalSupport) {
      return _page(settings, const TechnicalSupportScreen());
    }

    // Subscription
    if (name == subscription) {
      return _page(settings, const SubscriptionScreen());
    }
    if (name == currentSubscription) {
      return _page(settings, const CurrentSubscriptionScreen());
    }
    if (name == adminSubscriptions) {
      return _page(settings, const PendingSubscriptionsScreen());
    }

    // Dev / Debug
    if (name == devSmoke) {
      return _page(settings, const DevSmokeTestScreen());
    }

    // Unknown routes must never leak a placeholder to commercial users.
    return _fallback(
      settings,
      dashboard,
      const DashboardScreen(),
      'الرابط المطلوب غير متاح. أعدناك إلى لوحة التحكم.',
    );
  }

  // ===== Open helpers =====
  static Future<void> openGlEntry(BuildContext context, int entryId) async {
    await Navigator.of(context).pushNamed(financeGLEntry, arguments: entryId);
  }

  static Future<void> openInvoice(
      BuildContext context, String invoiceId) async {
    await Navigator.of(context).pushNamed(invoiceView, arguments: invoiceId);
  }

  static Future<void> openRepairById(
    BuildContext context,
    String repairId,
  ) async {
    try {
      final repair = await RepairDatabaseService.getRepairById(repairId);
      if (!context.mounted) return;
      if (repair == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ملف الإصلاح غير متاح. أعدناك إلى قائمة الإصلاحات.'),
          ),
        );
        await Navigator.of(context).pushNamed(repairsList);
        return;
      }
      await Navigator.of(context).pushNamed(repairDetail, arguments: repair);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح ملف الإصلاح. حاول مجددًا.')),
      );
    }
  }

  static Future<void> openEmployeePayroll(
      BuildContext context, Employee employee) async {
    await Navigator.of(context).pushNamed(employeePayroll, arguments: employee);
  }

  static Future<void> openEmployeeAdvances(
      BuildContext context, Employee employee) async {
    await Navigator.of(context)
        .pushNamed(employeeAdvances, arguments: employee);
  }

  // ===== Raw materials helpers =====
  static Future<void> openRawMaterialAdd(BuildContext context) async {
    await Navigator.of(context).pushNamed(rawMaterialAdd);
  }

  static Future<void> openRawMaterialEdit(
      BuildContext context, rm.RawMaterial material) async {
    await Navigator.of(context).pushNamed(rawMaterialEdit, arguments: material);
  }

  static Future<void> openSupplierLedger(BuildContext context,
      {required String supplierId, required String supplierName}) async {
    await Navigator.of(context).pushNamed(
      purchasesSupplierLedger,
      arguments: {'supplierId': supplierId, 'supplierName': supplierName},
    );
  }

  static Future<void> openSuppliersAging(BuildContext context) async {
    await Navigator.of(context).pushNamed(purchasesSuppliersAging);
  }

  static Future<void> openPurchasesGLAudit(BuildContext context) async {
    await Navigator.of(context).pushNamed(purchasesGLAudit);
  }

  static Future<void> openPurchasesDashboard(BuildContext context) async {
    await Navigator.of(context).pushNamed(purchasesDashboard);
  }

  static Future<void> openDevSmoke(BuildContext context) async {
    await Navigator.of(context).pushNamed(devSmoke);
  }
}

class _RouteFallbackNotice extends StatefulWidget {
  const _RouteFallbackNotice({
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  @override
  State<_RouteFallbackNotice> createState() => _RouteFallbackNoticeState();
}

class _RouteFallbackNoticeState extends State<_RouteFallbackNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(widget.message)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
