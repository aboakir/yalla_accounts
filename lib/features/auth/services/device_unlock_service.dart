import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'package:yalla_accounts/features/auth/services/password_hasher.dart';

final deviceUnlockServiceProvider = Provider<DeviceUnlockService>(
  (ref) => DeviceUnlockService(),
);

class DeviceUnlockService {
  DeviceUnlockService({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuthentication,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _localAuthentication = localAuthentication ?? LocalAuthentication();

  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuthentication;

  static const _userKey = 'yalla_device_unlock_user_v1';
  static const _pinHashKey = 'yalla_device_unlock_pin_hash_v1';
  static const _biometricKey = 'yalla_device_unlock_biometric_v1';

  Future<bool> isConfiguredFor(String userId) async {
    final storedUser = await _read(_userKey);
    final hash = await _read(_pinHashKey);
    return storedUser == userId && hash != null && hash.isNotEmpty;
  }

  Future<void> configure({
    required String userId,
    required String pin,
    required bool enableBiometric,
  }) async {
    final normalized = pin.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(normalized)) {
      throw ArgumentError('PIN must contain 4 to 6 digits.');
    }

    if (enableBiometric && !await biometricAvailable()) {
      throw StateError(
          'Biometric authentication is not available on this device.');
    }

    await _write(_userKey, userId);
    await _write(_pinHashKey, PasswordHasher.hash(normalized));
    await _write(_biometricKey, enableBiometric ? '1' : '0');
  }

  Future<bool> verifyPin({
    required String userId,
    required String pin,
  }) async {
    if (!await isConfiguredFor(userId)) return false;
    final hash = await _read(_pinHashKey);
    if (hash == null) return false;
    return PasswordHasher.verify(pin.trim(), hash).isValid;
  }

  Future<bool> biometricEnabledFor(String userId) async {
    if (!await isConfiguredFor(userId)) return false;
    return await _read(_biometricKey) == '1';
  }

  Future<bool> biometricAvailable() async {
    try {
      final supported = await _localAuthentication.isDeviceSupported();
      if (!supported) return false;
      final enrolled = await _localAuthentication.getAvailableBiometrics();
      if (enrolled.isNotEmpty) return true;
      return defaultTargetPlatform == TargetPlatform.windows;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric({required String userId}) async {
    if (!await biometricEnabledFor(userId)) return false;
    try {
      return await _localAuthentication.authenticate(
        localizedReason: 'تحقق لفتح Yalla Accounts',
        biometricOnly: defaultTargetPlatform != TargetPlatform.windows,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    await _delete(_userKey);
    await _delete(_pinHashKey);
    await _delete(_biometricKey);
  }

  Future<String?> _read(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } on FlutterError {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } on FlutterError {
      throw StateError('Secure device storage is unavailable.');
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on FlutterError {
      return;
    }
  }
}
