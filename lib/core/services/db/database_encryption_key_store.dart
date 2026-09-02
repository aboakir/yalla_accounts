import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the SQLCipher key outside the SQLite file.
///
/// The key is installation-local and never written to logs, preferences,
/// database tables, exported JSON, or source code.
class DatabaseEncryptionKeyStore {
  DatabaseEncryptionKeyStore._();

  static const String storageKey = 'yalla_accounts.database_key.v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String?> readExisting() async {
    final value = await _storage.read(key: storageKey);
    if (value == null) return null;
    _validate(value);
    return value;
  }

  static Future<String> readOrCreate() async {
    final existing = await readExisting();
    if (existing != null) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final generated = base64UrlEncode(bytes);

    await _storage.write(key: storageKey, value: generated);

    final persisted = await _storage.read(key: storageKey);
    if (persisted != generated) {
      throw StateError(
          'Database encryption key could not be persisted safely.');
    }

    _validate(generated);
    return generated;
  }

  static void _validate(String value) {
    try {
      final decoded = base64Url.decode(value);
      if (decoded.length != 32) {
        throw const FormatException('Unexpected key length.');
      }
    } catch (_) {
      throw StateError(
        'Stored database encryption key is invalid. '
        'The database will not be reset or replaced.',
      );
    }
  }
}
