import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:flutter/foundation.dart';
import 'auth_session_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';

/// Runtime service-level authorization gate.
///
/// Unit/regression services can operate before the interactive app session is
/// activated. Production StartupScreen enables this gate as soon as a valid
/// authenticated session is restored. From that point, sensitive services
/// fail closed when the current user lacks the requested permission.
class AuthorizationGuard {
  AuthorizationGuard._();

  static bool _interactiveEnforcement = kReleaseMode;

  static bool get isInteractiveEnforcementEnabled => _interactiveEnforcement;

  static void enableInteractiveEnforcement() {
    _interactiveEnforcement = true;
  }

  static void disableInteractiveEnforcement() {
    if (!kReleaseMode) _interactiveEnforcement = false;
  }

  static Future<AppUser?> require(String permission) async {
    if (!_interactiveEnforcement &&
        !AuthSessionService.isRecoverySession &&
        permission != PermissionKeys.backupRestore) {
      return null;
    }
    final actor = await PermissionService().requireCurrent(permission);
    const readPermissions = {
      PermissionKeys.customerView,
      PermissionKeys.repairView,
      PermissionKeys.payrollView,
      PermissionKeys.glView,
      PermissionKeys.reportView,
      PermissionKeys.reportExport,
      PermissionKeys.userView,
      PermissionKeys.auditView,
      PermissionKeys.settingsView,
      PermissionKeys.backupCreate,
      PermissionKeys.backupExport,
    };
    if (!readPermissions.contains(permission)) {
      await LicenseRuntimeService().requireOperationalWrite(permission);
    }
    return actor;
  }
}
