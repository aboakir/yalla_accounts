import 'device_unlock_service.dart';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';

typedef AuthDatabaseProvider = Future<Database> Function();

final authSessionServiceProvider = Provider<AuthSessionService>(
  (ref) => AuthSessionService(),
);

class LoginPreferences {
  const LoginPreferences({
    required this.rememberUsername,
    required this.keepSignedIn,
    this.rememberedUsername,
  });

  final bool rememberUsername;
  final bool keepSignedIn;
  final String? rememberedUsername;
}

class AuthSessionService {
  AuthSessionService({
    AuthDatabaseProvider? databaseProvider,
    FlutterSecureStorage? secureStorage,
  })  : _databaseProvider = databaseProvider ?? (() => DBService.database),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final AuthDatabaseProvider _databaseProvider;
  final FlutterSecureStorage _secureStorage;

  static const String _secureTokenKey = 'yalla_auth_session_token_v3';
  static const String _secureUserIdKey = 'yalla_auth_session_user_v3';
  static const String _rememberUsernameKey = 'yalla_auth_remember_username_v1';
  static const String _rememberedUsernameKey = 'yalla_auth_username_v1';
  static const String _keepSignedInKey = 'yalla_auth_keep_signed_in_v1';
  static const Duration _sessionLifetime = Duration(days: 30);

  // Process-local session material supports an authenticated session without
  // persisting it across application restarts.
  static String? _ephemeralToken;
  static String? _ephemeralUserId;
  static AppUser? _previewUser;
  static bool _recoveryOnly = false;
  static bool get isRecoverySession => _recoveryOnly;

  /// Simulates loss of volatile process memory; never grants or renews access.
  @visibleForTesting
  static void resetProcessMemoryForTesting() {
    _ephemeralToken = null;
    _ephemeralUserId = null;
    _previewUser = null;
    _previewUsesLocalUser = false;
    _recoveryOnly = false;
  }

  Future<void> createRecoverySession(AppUser user) async {
    if (!user.isOwner) throw StateError('Owner authentication required.');
    await createSession(user);
    _recoveryOnly = true;
  }

  static bool _previewUsesLocalUser = false;

  /// Explicit temporary-login session, never persisted as a production token.
  /// Existing local users are re-read on authorization; synthetic preview users
  /// exist only until logout/process exit. No workshop employee rows are used.
  Future<AppUser> startPreviewSession(AppUser user,
      {required bool localUser}) async {
    if (!kDebugMode) throw StateError('Temporary login is disabled.');
    await _clearSessionMaterial();
    if (user.status != 'active') {
      throw StateError('Cannot create a session for a disabled user.');
    }
    _previewUser = user;
    _previewUsesLocalUser = localUser;
    return (await restoreSession()) ??
        (throw StateError('User is unavailable.'));
  }

  static bool get hasPreviewSession => _previewUser != null;

  /// Identity established by createSession/restoreSession and cleared on logout.
  /// No database access: safe to read from inside financial transactions.
  static String? get authenticatedUserId =>
      _previewUser?.id ?? (_ephemeralToken == null ? null : _ephemeralUserId);

  Future<LoginPreferences> loadLoginPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearLegacyFlags(prefs);

    final rememberUsername = prefs.getBool(_rememberUsernameKey) ?? false;
    final keepSignedIn = prefs.getBool(_keepSignedInKey) ?? false;
    final rememberedUsername =
        rememberUsername ? prefs.getString(_rememberedUsernameKey) : null;

    return LoginPreferences(
      rememberUsername: rememberUsername,
      keepSignedIn: keepSignedIn,
      rememberedUsername: rememberedUsername,
    );
  }

  Future<void> saveLoginPreferences({
    required String username,
    required bool rememberUsername,
    required bool keepSignedIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final previouslyKeptSignedIn = prefs.getBool(_keepSignedInKey) ?? false;

    await prefs.setBool(_rememberUsernameKey, rememberUsername);
    await prefs.setBool(_keepSignedInKey, keepSignedIn);

    if (rememberUsername && username.trim().isNotEmpty) {
      await prefs.setString(_rememberedUsernameKey, username.trim());
    } else {
      await prefs.remove(_rememberedUsernameKey);
    }

    // Secure storage is a platform-channel concern. Only touch it when the
    // preference actually transitions away from a persisted login. This keeps
    // ordinary process-local sessions independent from Windows secure storage
    // and lets pure service/database tests exercise authentication safely.
    if (!keepSignedIn && previouslyKeptSignedIn) {
      await _clearPersistentSession();
    }
  }

  Future<String> createSession(
    AppUser user, {
    bool keepSignedIn = false,
  }) async {
    _recoveryOnly = false;
    _previewUser = null;
    if (user.status != 'active') {
      throw StateError('Cannot create a session for a disabled user.');
    }

    final db = await _databaseProvider();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(_sessionLifetime);
    final rawToken = _newToken();
    final tokenHash = _tokenHash(rawToken);

    await db.transaction((txn) async {
      await txn.update(
        'auth_sessions',
        {'revoked_at': now.toIso8601String()},
        where: 'user_id = ? AND revoked_at IS NULL',
        whereArgs: [user.id],
      );

      await txn.insert('auth_sessions', {
        'id': const Uuid().v4(),
        'user_id': user.id,
        'token_hash': tokenHash,
        'created_at': now.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'last_seen_at': now.toIso8601String(),
        'revoked_at': null,
      });
    });

    _ephemeralToken = rawToken;
    _ephemeralUserId = user.id;

    if (keepSignedIn) {
      await _secureWrite(_secureTokenKey, rawToken);
      await _secureWrite(_secureUserIdKey, user.id);
    }

    return rawToken;
  }

  Future<AppUser?> restoreSession() async {
    final preview = _previewUser;
    if (preview != null) {
      if (!_previewUsesLocalUser) {
        return preview.status == 'active' ? preview : null;
      }
      final db = await _databaseProvider();
      final rows = await db.query('users',
          where: 'id = ?', whereArgs: [preview.id], limit: 1);
      if (rows.isEmpty) return null;
      final current = AppUser.fromMap(rows.single);
      return current.status == 'active' ? current : null;
    }

    final prefs = await SharedPreferences.getInstance();
    await _clearLegacyFlags(prefs);

    String? rawToken = _ephemeralToken;
    String? userId = _ephemeralUserId;

    if (rawToken == null || userId == null) {
      final keepSignedIn = prefs.getBool(_keepSignedInKey) ?? false;
      if (!keepSignedIn) {
        await _clearPersistentSession();
        return null;
      }

      rawToken = await _secureRead(_secureTokenKey);
      userId = await _secureRead(_secureUserIdKey);
    }

    if (rawToken == null || userId == null) {
      await _clearSessionMaterial();
      return null;
    }

    final db = await _databaseProvider();
    final now = DateTime.now().toUtc();

    final rows = await db.rawQuery(
      '''
      SELECT u.*
      FROM auth_sessions s
      JOIN users u ON u.id = s.user_id
      WHERE s.user_id = ?
        AND s.token_hash = ?
        AND s.revoked_at IS NULL
        AND s.expires_at > ?
        AND (u.status IS NULL OR u.status = 'active')
      LIMIT 1
      ''',
      [userId, _tokenHash(rawToken), now.toIso8601String()],
    );

    if (rows.isEmpty) {
      await _clearSessionMaterial();
      return null;
    }

    _ephemeralToken = rawToken;
    _ephemeralUserId = userId;

    await db.update(
      'auth_sessions',
      {'last_seen_at': now.toIso8601String()},
      where: 'user_id = ? AND token_hash = ? AND revoked_at IS NULL',
      whereArgs: [userId, _tokenHash(rawToken)],
    );

    return AppUser.fromMap(rows.first);
  }

  /// Called on the restored database before its file journal is committed.
  /// A backup must never reactivate sessions issued on another device.
  Future<void> invalidateAfterRestore() async {
    final db = await _databaseProvider();
    await db.update('auth_sessions',
        {'revoked_at': DateTime.now().toUtc().toIso8601String()},
        where: 'revoked_at IS NULL');
    await _clearSessionMaterial();
    await DeviceUnlockService().clear();
  }

  Future<void> logout() async {
    try {
      final rawToken = _ephemeralToken ?? await _secureRead(_secureTokenKey);
      final userId = _ephemeralUserId ?? await _secureRead(_secureUserIdKey);
      if (rawToken != null && userId != null) {
        final db = await _databaseProvider();
        await db.update('auth_sessions',
            {'revoked_at': DateTime.now().toUtc().toIso8601String()},
            where: 'user_id = ? AND token_hash = ? AND revoked_at IS NULL',
            whereArgs: [userId, _tokenHash(rawToken)]);
      }
    } finally {
      // Revocation failures must not leave process-local authority alive.
      await _clearSessionMaterial();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepSignedInKey, false);
    await _clearLegacyFlags(prefs);
  }

  Future<void> forgetSavedLoginData() async {
    await _clearPersistentSession();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberUsernameKey);
    await prefs.remove(_rememberedUsernameKey);
    await prefs.remove(_keepSignedInKey);
    await _clearLegacyFlags(prefs);
  }

  Future<void> revokeAllForUser(String userId) async {
    final db = await _databaseProvider();
    await db.update(
      'auth_sessions',
      {'revoked_at': DateTime.now().toUtc().toIso8601String()},
      where: 'user_id = ? AND revoked_at IS NULL',
      whereArgs: [userId],
    );

    if (_ephemeralUserId == userId) {
      _ephemeralToken = null;
      _ephemeralUserId = null;
    }

    final persistedUserId = await _secureRead(_secureUserIdKey);
    if (persistedUserId == userId) {
      await _clearPersistentSession();
    }
  }

  /// Ends only the process-local customer preview session. It deliberately
  /// leaves remembered username / persistent-login preferences untouched.
  Future<void> endEphemeralPreviewSession() async {
    _recoveryOnly = false;
    _previewUser = null;
    _previewUsesLocalUser = false;
    final rawToken = _ephemeralToken;
    final userId = _ephemeralUserId;
    if (rawToken != null && userId != null) {
      final db = await _databaseProvider();
      await db.update(
        'auth_sessions',
        {'revoked_at': DateTime.now().toUtc().toIso8601String()},
        where: 'user_id = ? AND token_hash = ? AND revoked_at IS NULL',
        whereArgs: [userId, _tokenHash(rawToken)],
      );
    }
    _ephemeralToken = null;
    _ephemeralUserId = null;
  }

  static String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _tokenHash(String rawToken) {
    return sha256.convert(utf8.encode(rawToken)).toString();
  }

  Future<void> _clearSessionMaterial() async {
    _recoveryOnly = false;
    _previewUser = null;
    _previewUsesLocalUser = false;
    _ephemeralToken = null;
    _ephemeralUserId = null;
    await _clearPersistentSession();
  }

  Future<void> _clearPersistentSession() async {
    await _secureDelete(_secureTokenKey);
    await _secureDelete(_secureUserIdKey);
  }

  Future<String?> _secureRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } on FlutterError {
      // Pure Dart/service tests have no Flutter services binding. In that
      // environment there cannot be valid Windows-persisted session material.
      return null;
    }
  }

  Future<void> _secureWrite(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } on FlutterError {
      // Persisted login must never fall back to plaintext or SharedPreferences.
      throw StateError(
        'Persistent login requires an initialized Flutter services binding.',
      );
    }
  }

  Future<void> _secureDelete(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on FlutterError {
      // No binding means no platform-backed secure session can be accessed by
      // this process; pure service tests should remain platform-independent.
      return;
    }
  }

  static Future<void> _clearLegacyFlags(SharedPreferences prefs) async {
    for (final key in const [
      'loggedIn',
      'userId',
      'username',
      'userRole',
      'lastActivity',
      'yalla_auth_session_token_v2',
      'yalla_auth_session_user_v2',
    ]) {
      await prefs.remove(key);
    }
  }
}
