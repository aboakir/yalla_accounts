import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight local authenticated-user identity for audit attribution.
///
/// This deliberately reads only the locally stored session user id. It does
/// not query the database, so PostingEngine can use it safely from inside an
/// existing SQLite transaction.
class CurrentUserContext {
  CurrentUserContext._();

  static const String _sessionUserKey = 'yalla_auth_session_user_v2';

  static Future<String?> userId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_sessionUserKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
