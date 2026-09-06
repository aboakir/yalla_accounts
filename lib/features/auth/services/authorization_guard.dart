import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';

/// Runtime service-level authorization gate.
///
/// Unit/regression services can operate before the interactive app session is
/// activated. Production StartupScreen enables this gate as soon as a valid
/// authenticated session is restored. From that point, sensitive services
/// fail closed when the current user lacks the requested permission.
class AuthorizationGuard {
  AuthorizationGuard._();

  static bool _interactiveEnforcement = false;

  static bool get isInteractiveEnforcementEnabled => _interactiveEnforcement;

  static void enableInteractiveEnforcement() {
    _interactiveEnforcement = true;
  }

  static void disableInteractiveEnforcement() {
    _interactiveEnforcement = false;
  }

  static Future<AppUser?> require(String permission) async {
    if (!_interactiveEnforcement) return null;
    return PermissionService().requireCurrent(permission);
  }
}
