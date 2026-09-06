import 'package:flutter/services.dart' show MissingPluginException;
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight local authenticated-user identity for audit attribution.
///
/// This deliberately reads only the locally stored session user id. It does
/// not query the database, so PostingEngine can use it safely from inside an
/// existing SQLite transaction. Headless/unit-test environments may not have
/// the SharedPreferences platform plugin registered; audit attribution must
/// never make an otherwise valid business operation fail in that case.
class CurrentUserContext {
  CurrentUserContext._();

  static const String _sessionUserKey = 'yalla_auth_session_user_v2';

  static Future<String?> userId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_sessionUserKey)?.trim();
      if (value == null || value.isEmpty) return null;
      return value;
    } on MissingPluginException {
      return null;
    }
  }
}
