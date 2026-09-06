import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackupKeyStore {
  BackupKeyStore._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'yalla_p16_backup_password_v1';

  static Future<void> savePassword(String password) async {
    final value = password.trim();
    if (value.length < 10) {
      throw ArgumentError('كلمة حماية النسخ يجب أن تكون 10 أحرف على الأقل.');
    }
    await _storage.write(key: _key, value: value);
  }

  static Future<String?> readPassword() async {
    final value = (await _storage.read(key: _key))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<bool> hasPassword() async => (await readPassword()) != null;

  static Future<void> clear() => _storage.delete(key: _key);
}
