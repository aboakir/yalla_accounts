import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';

/// Uses the same verified, process-local session as authentication.
/// Never restores a session here: financial callers may already hold a SQLite
/// transaction. Restoration belongs to login/startup, before financial writes.
class CurrentUserContext {
  CurrentUserContext._();

  static String? Function()? _activeUserReader;

  /// The application binds its current-user state here. Read lazily so account
  /// switches and logout are reflected immediately, without caching an id.
  static void bindActiveUserReader(String? Function() reader) {
    _activeUserReader = reader;
  }

  static Future<String?> userId() async {
    if (AuthSessionService.isRecoverySession) return null;
    final reader = _activeUserReader;
    // A bound but signed-out UI must not fall back to an older session.
    final id =
        reader != null ? reader() : AuthSessionService.authenticatedUserId;
    if (id != AuthSessionService.authenticatedUserId) return null;
    return id == null || id.trim().isEmpty ? null : id.trim();
  }
}
