import '../../security/authorization_policy.dart';

/// Central client projection of backend capability codes.
/// Plan names are never used as authorization keys.
class CommercialFeatureCatalog {
  CommercialFeatureCatalog._();

  static const all = <String>{
    'GARAGE_REPAIRS',
    'CUSTOMERS',
    'VEHICLES',
    'SALES',
    'EXPENSES',
    'RECEIPTS',
    'PAYMENTS',
    'CUSTOMER_RECEIVABLES',
    'SUPPLIER_PAYABLES',
    'PURCHASES',
    'CHEQUES_BASIC',
    'CHEQUES_ADVANCED',
    'INVENTORY_BASIC',
    'INVENTORY_ADVANCED',
    'EMPLOYEES',
    'PAYROLL',
    'ACCOUNTING_GL',
    'BASIC_REPORTS',
    'ADVANCED_REPORTS',
    'ADVANCED_PERMISSIONS',
    'CLOUD_SYNC',
    'PDF_EXPORT',
    'AUDIT_LOG',
    'MODULE_INSURANCE',
    'MODULE_AUTO_PARTS',
  };

  static String? forPermission(String permission) {
    if (const {
      PermissionKeys.invoiceCreate,
      PermissionKeys.invoiceApprove,
      PermissionKeys.invoicePost,
      PermissionKeys.invoiceReverse,
    }.contains(permission)) {
      return 'SALES';
    }
    if (permission == PermissionKeys.insurancePolicyPost) {
      return 'MODULE_INSURANCE';
    }
    if (const {
      PermissionKeys.receiptCreate,
      PermissionKeys.receiptReverse,
    }.contains(permission)) {
      return 'RECEIPTS';
    }
    if (permission == PermissionKeys.paymentCreate) {
      return 'PAYMENTS';
    }
    if (permission == PermissionKeys.chequeManage) {
      return 'CHEQUES_BASIC';
    }
    if (permission == PermissionKeys.purchaseManage) {
      return 'PURCHASES';
    }
    if (permission == PermissionKeys.repairCostManage) {
      return 'GARAGE_REPAIRS';
    }
    if (permission == PermissionKeys.payrollManage) {
      return 'PAYROLL';
    }
    if (const {
      PermissionKeys.glManualPost,
      PermissionKeys.periodClose,
      PermissionKeys.periodReopen,
    }.contains(permission)) {
      return 'ACCOUNTING_GL';
    }
    if (const {
      PermissionKeys.repairCreate,
      PermissionKeys.repairEdit,
      PermissionKeys.repairWorkflow,
      PermissionKeys.repairClose,
      PermissionKeys.repairReopen,
    }.contains(permission)) {
      return 'GARAGE_REPAIRS';
    }
    return null;
  }

  static String? limitForPermission(String permission) {
    if (permission == PermissionKeys.repairCreate) {
      return 'MAX_REPAIRS_MONTH';
    }
    if (permission == PermissionKeys.invoiceCreate) {
      return 'MAX_INVOICES_MONTH';
    }
    return null;
  }

  static String? forTable(String table) {
    if (const {
      'accounts',
      'gl_entries',
      'gl_lines',
      'journal_entries',
      'ledger_entries',
    }.contains(table)) {
      return 'ACCOUNTING_GL';
    }
    if (table == 'invoices' || table == 'invoice_settlements') {
      return 'SALES';
    }
    if (table == 'payments') return 'PAYMENTS';
    if (const {
      'purchase_invoices',
      'purchase_invoice_lines',
      'purchase_payments',
    }.contains(table)) {
      return 'PURCHASES';
    }
    if (const {
      'receipt_requests',
      'receipt_headers',
      'receipt_allocations',
      'customer_credit_allocations',
    }.contains(table)) {
      return 'RECEIPTS';
    }
    if (table == 'vouchers') return 'PAYMENTS';
    if (table == 'cheques') return 'CHEQUES_BASIC';
    if (table == 'cheque_events') return 'CHEQUES_ADVANCED';
    if (table == 'monthly_expenses') return 'EXPENSES';
    if (table == 'employee_advances') return 'EMPLOYEES';
    if (const {'payroll_runs', 'payroll_payments'}.contains(table)) {
      return 'PAYROLL';
    }
    if (const {
      'insurance_policies',
      'insurance_policy_cheques',
      'insurance_policy_installments',
      'insurance_policy_promissories',
    }.contains(table)) {
      return 'MODULE_INSURANCE';
    }
    if (const {
      'repairs',
      'repair_lines',
      'repairs_images',
      'repair_workflow',
      'repair_workflow_events',
    }.contains(table)) {
      return 'GARAGE_REPAIRS';
    }
    if (const {
      'inventory_items',
      'inventory_warehouses',
    }.contains(table)) {
      return 'INVENTORY_BASIC';
    }
    if (const {
      'inventory_movements',
      'inventory_item_alternatives',
      'inventory_item_compatibilities',
    }.contains(table)) {
      return 'INVENTORY_ADVANCED';
    }
    return null;
  }

  static String? forRoute(String routeName) {
    if (routeName.startsWith('/insurance-agent')) return 'MODULE_INSURANCE';
    if (routeName == '/employees/payroll' ||
        routeName == '/reports/payroll' ||
        routeName == '/employees/salaries') {
      return 'PAYROLL';
    }
    if (routeName.startsWith('/employees')) return 'EMPLOYEES';

    if (const {
      '/finance/gl',
      '/finance/gl/entry',
      '/finance/journal/entries',
      '/finance/general-journal',
      '/finance/account-ledger',
      '/finance/accounting-periods',
      '/reports/trial-balance',
      '/reports/general-ledger',
      '/reports/balance-sheet',
    }.contains(routeName)) {
      return 'ACCOUNTING_GL';
    }
    if (routeName == '/finance/income-statement') return 'ADVANCED_REPORTS';
    if (routeName == '/reports') return 'BASIC_REPORTS';
    if (routeName.startsWith('/reports/')) return 'ADVANCED_REPORTS';

    if (const {
      '/cheques/collection',
      '/cheques/collected',
      '/cheques/returned',
      '/cheques/cancelled',
      '/cheques/postdated',
      '/cheques/report',
      '/cheques/books',
    }.contains(routeName)) {
      return 'CHEQUES_ADVANCED';
    }
    if (routeName.startsWith('/cheques') || routeName == '/suppliers/cheques') {
      return 'CHEQUES_BASIC';
    }

    if (routeName.startsWith('/purchases')) return 'PURCHASES';
    if (routeName.startsWith('/suppliers')) return 'SUPPLIER_PAYABLES';
    if (routeName == '/inventory' || routeName.startsWith('/raw_materials')) {
      return 'INVENTORY_BASIC';
    }
    if (routeName.startsWith('/repairs')) return 'GARAGE_REPAIRS';
    if (routeName.startsWith('/clients') || routeName.startsWith('/parties')) {
      return 'CUSTOMERS';
    }
    if (routeName == '/finance/expenses') return 'EXPENSES';
    if (routeName.contains('receipt-voucher')) return 'RECEIPTS';
    if (routeName.contains('payment-voucher') ||
        routeName == '/finance/payments') {
      return 'PAYMENTS';
    }
    return null;
  }
}
