class RoleKeys {
  static const String owner = 'owner';
  static const String manager = 'manager';
  static const String accountant = 'accountant';
  static const String cashier = 'cashier';
  static const String workshopManager = 'workshop_manager';
  static const String estimator = 'estimator';
  static const String storekeeper = 'storekeeper';
  static const String auditor = 'auditor';
  static const String readOnly = 'read_only';

  static const Set<String> assignable = {
    manager,
    accountant,
    cashier,
    workshopManager,
    estimator,
    storekeeper,
    auditor,
    readOnly,
  };

  static bool isKnown(String role) => all.contains(role);
  static bool isAssignable(String role) => assignable.contains(role);

  static const Set<String> all = {
    owner,
    manager,
    accountant,
    cashier,
    workshopManager,
    estimator,
    storekeeper,
    auditor,
    readOnly,
  };

  static String displayNameAr(String role) {
    switch (role) {
      case owner:
        return 'مالك المنشأة';
      case manager:
        return 'مدير';
      case accountant:
        return 'محاسب';
      case cashier:
        return 'أمين صندوق';
      case workshopManager:
        return 'مدير الورشة';
      case estimator:
        return 'مُقدّر';
      case storekeeper:
        return 'أمين مخزن';
      case auditor:
        return 'مدقق';
      case readOnly:
        return 'قراءة فقط';
      default:
        return role;
    }
  }
}

class PermissionKeys {
  static const String customerView = 'CUSTOMER_VIEW';
  static const String customerCreate = 'CUSTOMER_CREATE';
  static const String customerEdit = 'CUSTOMER_EDIT';

  static const String repairCreate = 'REPAIR_CREATE';
  static const String repairEdit = 'REPAIR_EDIT';

  static const String invoiceCreate = 'INVOICE_CREATE';
  static const String invoiceApprove = 'INVOICE_APPROVE';
  static const String invoicePost = 'INVOICE_POST';
  static const String invoiceReverse = 'INVOICE_REVERSE';

  static const String receiptCreate = 'RECEIPT_CREATE';
  static const String paymentCreate = 'PAYMENT_CREATE';

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

  static const String periodClose = 'PERIOD_CLOSE';
  static const String periodReopen = 'PERIOD_REOPEN';

  static const String settingsView = 'SETTINGS_VIEW';
  static const String settingsAccounting = 'SETTINGS_ACCOUNTING';
  static const String settingsTax = 'SETTINGS_TAX';

  static const String backupCreate = 'BACKUP_CREATE';
  static const String backupRestore = 'BACKUP_RESTORE';

  static const Set<String> all = {
    customerView,
    customerCreate,
    customerEdit,
    repairCreate,
    repairEdit,
    invoiceCreate,
    invoiceApprove,
    invoicePost,
    invoiceReverse,
    receiptCreate,
    paymentCreate,
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
    periodClose,
    periodReopen,
    settingsView,
    settingsAccounting,
    settingsTax,
    backupCreate,
    backupRestore,
  };
}

class AuthorizationPolicy {
  static const Map<String, Set<String>> rolePermissions = {
    RoleKeys.owner: PermissionKeys.all,
    RoleKeys.manager: {
      PermissionKeys.customerView,
      PermissionKeys.customerCreate,
      PermissionKeys.customerEdit,
      PermissionKeys.repairCreate,
      PermissionKeys.repairEdit,
      PermissionKeys.invoiceCreate,
      PermissionKeys.invoiceApprove,
      PermissionKeys.receiptCreate,
      PermissionKeys.paymentCreate,
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
      PermissionKeys.userView,
      PermissionKeys.settingsView,
      PermissionKeys.backupCreate,
    },
    RoleKeys.accountant: {
      PermissionKeys.customerView,
      PermissionKeys.invoiceCreate,
      PermissionKeys.invoiceApprove,
      PermissionKeys.invoicePost,
      PermissionKeys.invoiceReverse,
      PermissionKeys.receiptCreate,
      PermissionKeys.paymentCreate,
      PermissionKeys.glView,
      PermissionKeys.glManualPost,
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
      PermissionKeys.periodClose,
      PermissionKeys.settingsView,
      PermissionKeys.settingsAccounting,
      PermissionKeys.settingsTax,
      PermissionKeys.backupCreate,
    },
    RoleKeys.cashier: {
      PermissionKeys.customerView,
      PermissionKeys.customerCreate,
      PermissionKeys.invoiceCreate,
      PermissionKeys.receiptCreate,
      PermissionKeys.paymentCreate,
      PermissionKeys.reportView,
    },
    RoleKeys.workshopManager: {
      PermissionKeys.customerView,
      PermissionKeys.customerCreate,
      PermissionKeys.customerEdit,
      PermissionKeys.repairCreate,
      PermissionKeys.repairEdit,
      PermissionKeys.invoiceCreate,
      PermissionKeys.reportView,
    },
    RoleKeys.estimator: {
      PermissionKeys.customerView,
      PermissionKeys.customerCreate,
      PermissionKeys.customerEdit,
      PermissionKeys.repairCreate,
      PermissionKeys.repairEdit,
      PermissionKeys.reportView,
    },
    RoleKeys.storekeeper: {
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
    },
    RoleKeys.auditor: {
      PermissionKeys.customerView,
      PermissionKeys.glView,
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
      PermissionKeys.settingsView,
    },
    RoleKeys.readOnly: {
      PermissionKeys.customerView,
      PermissionKeys.glView,
      PermissionKeys.reportView,
      PermissionKeys.settingsView,
    },
  };

  static Set<String> forRole(String role) =>
      Set<String>.unmodifiable(rolePermissions[role] ?? const <String>{});
}
