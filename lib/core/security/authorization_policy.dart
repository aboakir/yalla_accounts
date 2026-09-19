class RoleKeys {
  // Canonical roles for new users; legacy roles keep their existing grants.
  static const String owner = 'owner';
  static const String admin = 'admin';
  static const String staff = 'staff';
  static const String viewer = 'viewer';
  static const Set<String> canonical = {
    owner,
    admin,
    accountant,
    staff,
    viewer
  };
  static const String manager = 'manager';
  static const String accountant = 'accountant';
  static const String employee = 'employee';
  static const String technician = 'technician';

  // Historical SEC.008 roles remain recognized so existing installations and
  // old signed/test data are never orphaned. New UI assignment exposes only
  // the canonical roles above (Owner is created by protected bootstrap).
  static const String cashier = 'cashier';
  static const String workshopManager = 'workshop_manager';
  static const String estimator = 'estimator';
  static const String storekeeper = 'storekeeper';
  static const String auditor = 'auditor';
  static const String readOnly = 'read_only';

  static const Set<String> assignable = {
    admin,
    accountant,
    staff,
    viewer,
  };

  static const Set<String> legacyAssignable = {
    manager,
    employee,
    technician,
    cashier,
    workshopManager,
    estimator,
    storekeeper,
    auditor,
    readOnly,
  };

  static String normalize(String role) => role.trim().toLowerCase();

  static bool isKnown(String role) => all.contains(normalize(role));
  static bool isAssignable(String role) => assignable.contains(normalize(role));

  static const Set<String> all = {
    ...canonical,
    manager,
    employee,
    technician,
    cashier,
    workshopManager,
    estimator,
    storekeeper,
    auditor,
    readOnly,
  };

  static String displayNameAr(String role) {
    switch (normalize(role)) {
      case admin:
        return 'مدير';
      case staff:
        return 'موظف';
      case viewer:
        return 'مشاهد — قراءة فقط';
      case owner:
        return 'المالك';
      case manager:
        return 'المدير';
      case accountant:
        return 'المحاسب';
      case employee:
        return 'موظف';
      case technician:
        return 'فني';
      case cashier:
        return 'أمين صندوق (قديم)';
      case workshopManager:
        return 'مدير الورشة (قديم)';
      case estimator:
        return 'مُقدّر (قديم)';
      case storekeeper:
        return 'أمين مخزن (قديم)';
      case auditor:
        return 'مدقق (قديم)';
      case readOnly:
        return 'قراءة فقط (قديم)';
      default:
        return role;
    }
  }
}

class PermissionKeys {
  static const String customerView = 'CUSTOMER_VIEW';
  static const String customerCreate = 'CUSTOMER_CREATE';
  static const String customerEdit = 'CUSTOMER_EDIT';

  static const String repairView = 'REPAIR_VIEW';
  static const String repairCreate = 'REPAIR_CREATE';
  static const String repairEdit = 'REPAIR_EDIT';
  static const String repairWorkflow = 'REPAIR_WORKFLOW';
  static const String repairClose = 'REPAIR_CLOSE';
  static const String repairReopen = 'REPAIR_REOPEN';

  static const String invoiceCreate = 'INVOICE_CREATE';
  static const String invoiceApprove = 'INVOICE_APPROVE';
  static const String invoicePost = 'INVOICE_POST';
  static const String invoiceReverse = 'INVOICE_REVERSE';

  static const String receiptCreate = 'RECEIPT_CREATE';
  static const String receiptReverse = 'RECEIPT_REVERSE';
  static const String paymentCreate = 'PAYMENT_CREATE';

  static const String chequeManage = 'CHEQUE_MANAGE';
  static const String chequeCreate = 'CHEQUE_CREATE';
  static const String chequeEdit = 'CHEQUE_EDIT';
  static const String chequeDeposit = 'CHEQUE_DEPOSIT';
  static const String chequeCollect = 'CHEQUE_COLLECT';
  static const String chequeReturn = 'CHEQUE_RETURN';
  static const String chequeCancel = 'CHEQUE_CANCEL';
  static const String chequeEndorse = 'CHEQUE_ENDORSE';
  static const String chequeDueDateEdit = 'CHEQUE_DUE_DATE_EDIT';
  static const String chequeBookManage = 'CHEQUE_BOOK_MANAGE';
  static const String chequePrint = 'CHEQUE_PRINT';
  static const String chequeReportView = 'CHEQUE_REPORT_VIEW';
  static const String chequeReverse = 'CHEQUE_REVERSE';
  static const String purchaseManage = 'PURCHASE_MANAGE';
  static const String repairCostManage = 'REPAIR_COST_MANAGE';
  static const String payrollView = 'PAYROLL_VIEW';
  static const String payrollManage = 'PAYROLL_MANAGE';

  static const String glView = 'GL_VIEW';
  static const String glManualPost = 'GL_MANUAL_POST';

  static const String reportView = 'REPORT_VIEW';
  static const String reportExport = 'REPORT_EXPORT';

  static const String userView = 'USER_VIEW';
  static const String userCreate = 'USER_CREATE';
  static const String userEdit = 'USER_EDIT';
  static const String userDisable = 'USER_DISABLE';
  static const String userUnlock = 'USER_UNLOCK';
  static const String roleManage = 'ROLE_MANAGE';

  static const String auditView = 'AUDIT_VIEW';

  static const String periodClose = 'PERIOD_CLOSE';
  static const String periodReopen = 'PERIOD_REOPEN';

  static const String settingsView = 'SETTINGS_VIEW';
  static const String settingsAccounting = 'SETTINGS_ACCOUNTING';
  static const String settingsTax = 'SETTINGS_TAX';

  static const String backupCreate = 'BACKUP_CREATE';
  static const String backupExport = 'BACKUP_EXPORT';
  static const String backupRestore = 'BACKUP_RESTORE';
  static const String windowsImport = 'WINDOWS_IMPORT';

  static const Set<String> all = {
    customerView,
    customerCreate,
    customerEdit,
    repairView,
    repairCreate,
    repairEdit,
    repairWorkflow,
    repairClose,
    repairReopen,
    invoiceCreate,
    invoiceApprove,
    invoicePost,
    invoiceReverse,
    receiptCreate,
    receiptReverse,
    paymentCreate,
    chequeManage,
    chequeCreate,
    chequeEdit,
    chequeDeposit,
    chequeCollect,
    chequeReturn,
    chequeCancel,
    chequeEndorse,
    chequeDueDateEdit,
    chequeBookManage,
    chequePrint,
    chequeReportView,
    chequeReverse,
    purchaseManage,
    repairCostManage,
    payrollView,
    payrollManage,
    glView,
    glManualPost,
    reportView,
    reportExport,
    userView,
    userCreate,
    userEdit,
    userDisable,
    userUnlock,
    roleManage,
    auditView,
    periodClose,
    periodReopen,
    settingsView,
    settingsAccounting,
    settingsTax,
    backupCreate,
    backupExport,
    backupRestore,
    windowsImport,
  };
}

class AuthorizationPolicy {
  static const Set<String> _readOnlyPermissions = {
    PermissionKeys.customerView,
    PermissionKeys.repairView,
    PermissionKeys.glView,
    PermissionKeys.reportView,
    PermissionKeys.settingsView,
  };

  static const Set<String> _employeePermissions = {
    PermissionKeys.customerView,
    PermissionKeys.customerCreate,
    PermissionKeys.customerEdit,
    PermissionKeys.repairView,
    PermissionKeys.repairCreate,
    PermissionKeys.repairEdit,
    PermissionKeys.repairWorkflow,
  };

  static const Set<String> _managerPermissions = {
    PermissionKeys.customerView,
    PermissionKeys.customerCreate,
    PermissionKeys.customerEdit,
    PermissionKeys.repairView,
    PermissionKeys.repairCreate,
    PermissionKeys.repairEdit,
    PermissionKeys.repairWorkflow,
    PermissionKeys.repairClose,
    PermissionKeys.repairReopen,
    PermissionKeys.invoiceCreate,
    PermissionKeys.invoiceApprove,
    PermissionKeys.receiptCreate,
    PermissionKeys.paymentCreate,
    PermissionKeys.chequeManage,
    PermissionKeys.chequeCreate,
    PermissionKeys.chequeEdit,
    PermissionKeys.chequeDeposit,
    PermissionKeys.chequeCollect,
    PermissionKeys.chequeReturn,
    PermissionKeys.chequeCancel,
    PermissionKeys.chequeEndorse,
    PermissionKeys.chequeDueDateEdit,
    PermissionKeys.chequeBookManage,
    PermissionKeys.chequePrint,
    PermissionKeys.chequeReportView,
    PermissionKeys.chequeReverse,
    PermissionKeys.purchaseManage,
    PermissionKeys.repairCostManage,
    PermissionKeys.payrollView,
    PermissionKeys.reportView,
    PermissionKeys.reportExport,
    PermissionKeys.userView,
    PermissionKeys.auditView,
    PermissionKeys.settingsView,
    PermissionKeys.backupCreate,
    PermissionKeys.backupExport,
  };

  static const Map<String, Set<String>> rolePermissions = {
    RoleKeys.owner: PermissionKeys.all,

    RoleKeys.manager: _managerPermissions,
    RoleKeys.admin: _managerPermissions,

    RoleKeys.accountant: {
      PermissionKeys.customerView,
      PermissionKeys.repairView,
      PermissionKeys.invoiceCreate,
      PermissionKeys.invoiceApprove,
      PermissionKeys.invoicePost,
      PermissionKeys.invoiceReverse,
      PermissionKeys.receiptCreate,
      PermissionKeys.receiptReverse,
      PermissionKeys.paymentCreate,
      PermissionKeys.chequeManage,
      PermissionKeys.chequeCreate,
      PermissionKeys.chequeEdit,
      PermissionKeys.chequeDeposit,
      PermissionKeys.chequeCollect,
      PermissionKeys.chequeReturn,
      PermissionKeys.chequeCancel,
      PermissionKeys.chequeEndorse,
      PermissionKeys.chequeDueDateEdit,
      PermissionKeys.chequeBookManage,
      PermissionKeys.chequePrint,
      PermissionKeys.chequeReportView,
      PermissionKeys.chequeReverse,
      PermissionKeys.purchaseManage,
      PermissionKeys.repairCostManage,
      PermissionKeys.payrollView,
      PermissionKeys.payrollManage,
      PermissionKeys.glView,
      PermissionKeys.glManualPost,
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
      PermissionKeys.auditView,
      PermissionKeys.periodClose,
      PermissionKeys.settingsView,
      PermissionKeys.settingsAccounting,
      PermissionKeys.settingsTax,
      PermissionKeys.backupCreate,
      PermissionKeys.backupExport,
    },

    RoleKeys.employee: _employeePermissions,
    RoleKeys.staff: _employeePermissions,

    RoleKeys.technician: {
      PermissionKeys.repairView,
      PermissionKeys.repairWorkflow,
    },

    // Historical compatibility roles. They are hidden from the P16 role picker
    // but remain functional until existing users are reassigned.
    RoleKeys.cashier: {
      PermissionKeys.customerView,
      PermissionKeys.customerCreate,
      PermissionKeys.repairView,
      PermissionKeys.invoiceCreate,
      PermissionKeys.receiptCreate,
      PermissionKeys.paymentCreate,
      PermissionKeys.chequeCreate,
      PermissionKeys.chequeDeposit,
      PermissionKeys.chequeCollect,
      PermissionKeys.chequeReturn,
      PermissionKeys.chequePrint,
      PermissionKeys.chequeReportView,
      PermissionKeys.reportView,
    },
    RoleKeys.workshopManager: {
      PermissionKeys.customerView,
      PermissionKeys.customerCreate,
      PermissionKeys.customerEdit,
      PermissionKeys.repairView,
      PermissionKeys.repairCreate,
      PermissionKeys.repairEdit,
      PermissionKeys.repairWorkflow,
      PermissionKeys.invoiceCreate,
      PermissionKeys.reportView,
    },
    RoleKeys.estimator: {
      PermissionKeys.customerView,
      PermissionKeys.customerCreate,
      PermissionKeys.customerEdit,
      PermissionKeys.repairView,
      PermissionKeys.repairCreate,
      PermissionKeys.repairEdit,
      PermissionKeys.reportView,
    },
    RoleKeys.storekeeper: {
      PermissionKeys.purchaseManage,
      PermissionKeys.repairCostManage,
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
    },
    RoleKeys.auditor: {
      PermissionKeys.customerView,
      PermissionKeys.repairView,
      PermissionKeys.glView,
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
      PermissionKeys.auditView,
      PermissionKeys.settingsView,
    },
    RoleKeys.readOnly: _readOnlyPermissions,
    RoleKeys.viewer: _readOnlyPermissions,
  };

  static Set<String> forRole(String role) => Set<String>.unmodifiable(
      rolePermissions[RoleKeys.normalize(role)] ?? const <String>{});
}
