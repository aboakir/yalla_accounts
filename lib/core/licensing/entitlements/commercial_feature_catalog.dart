import '../../security/authorization_policy.dart';

/// Capability keys, never plan names. Basic reading/export/backup stays
/// available for data retention; only commercial mutations are mapped here.
class CommercialFeatureCatalog {
  CommercialFeatureCatalog._();

  static String? forPermission(String permission) {
    if (const {
      PermissionKeys.invoiceCreate,
      PermissionKeys.invoiceApprove,
      PermissionKeys.invoicePost,
      PermissionKeys.invoiceReverse,
      PermissionKeys.insurancePolicyPost,
      PermissionKeys.receiptCreate,
      PermissionKeys.receiptReverse,
      PermissionKeys.paymentCreate,
      PermissionKeys.chequeManage,
      PermissionKeys.purchaseManage,
      PermissionKeys.repairCostManage,
      PermissionKeys.payrollManage,
      PermissionKeys.glManualPost,
      PermissionKeys.periodClose,
      PermissionKeys.periodReopen,
    }.contains(permission)) {
      return 'ACCOUNTING_CORE';
    }
    if (const {
      PermissionKeys.repairCreate,
      PermissionKeys.repairEdit,
      PermissionKeys.repairWorkflow,
      PermissionKeys.repairClose,
      PermissionKeys.repairReopen,
    }.contains(permission)) {
      return 'WORKSHOP_REPAIRS';
    }
    return null;
  }

  /// Independent database guard for legacy/direct write surfaces. The receipt
  /// is committed only by the verified activation/lifecycle path; callers must
  /// still pass the cryptographic service-level guard, not trust raw JSON.
  static String? forTable(String table) {
    if (const {
      'accounts',
      'gl_entries',
      'gl_lines',
      'journal_entries',
      'ledger_entries',
      'invoices',
      'payments',
      'purchase_invoices',
      'purchase_invoice_lines',
      'purchase_payments',
      'receipt_requests',
      'receipt_headers',
      'receipt_allocations',
      'customer_credit_allocations',
      'vouchers',
      'cheques',
      'cheque_events',
      'monthly_expenses',
      'employee_advances',
      'payroll_runs',
      'payroll_payments',
      'invoice_settlements',
      'insurance_policies',
      'insurance_policy_cheques',
      'insurance_policy_installments',
      'insurance_policy_promissories',
    }.contains(table)) {
      return 'ACCOUNTING_CORE';
    }
    if (const {
      'repairs',
      'repair_lines',
      'repairs_images',
      'repair_workflow',
      'repair_workflow_events',
    }.contains(table)) {
      return 'WORKSHOP_REPAIRS';
    }
    return null;
  }
}
