import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The SDK's default SharedPreferences storage must not receive auth secrets.
class CloudSecureStorage extends LocalStorage {
  CloudSecureStorage(this.namespace, {FlutterSecureStorage? storage})
      : storage = storage ?? const FlutterSecureStorage();
  final String namespace;
  final FlutterSecureStorage storage;
  String get sessionKey => 'yalla_cloud_${namespace}_session';
  Future<void> verifiedWrite(String key, String value) async {
    await storage.write(key: key, value: value);
    if (await storage.read(key: key) != value) {
      await storage.delete(key: key);
      throw StateError('Secure cloud session persistence failed');
    }
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => storage.read(key: sessionKey);
  @override
  Future<void> persistSession(String persistSessionString) =>
      verifiedWrite(sessionKey, persistSessionString);
  @override
  Future<void> removePersistedSession() => storage.delete(key: sessionKey);
}

class CloudPkceStorage extends GotrueAsyncStorage {
  CloudPkceStorage(this.secure);
  final CloudSecureStorage secure;
  String _key(String key) => 'yalla_cloud_${secure.namespace}_pkce_$key';
  @override
  Future<String?> getItem({required String key}) =>
      secure.storage.read(key: _key(key));
  @override
  Future<void> setItem({required String key, required String value}) =>
      secure.verifiedWrite(_key(key), value);
  @override
  Future<void> removeItem({required String key}) =>
      secure.storage.delete(key: _key(key));
}
