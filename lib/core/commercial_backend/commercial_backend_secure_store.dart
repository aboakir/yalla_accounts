import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CommercialBackendSecureState {
  const CommercialBackendSecureState({
    this.customerCode,
    this.requestId,
    this.activationSecret,
    this.deviceToken,
    this.leaseToken,
    this.trustedServerTime,
  });

  final String? customerCode;
  final String? requestId;
  final String? activationSecret;
  final String? deviceToken;
  final String? leaseToken;
  final DateTime? trustedServerTime;

  bool get hasPendingRequest =>
      requestId?.isNotEmpty == true && activationSecret?.isNotEmpty == true;

  bool get hasApprovedDevice => deviceToken?.isNotEmpty == true;
}

abstract class CommercialSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> delete(String key);
}

class FlutterCommercialSecretStorage implements CommercialSecretStorage {
  FlutterCommercialSecretStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class CommercialBackendSecureStore {
  CommercialBackendSecureStore({CommercialSecretStorage? storage})
      : _storage = storage ?? FlutterCommercialSecretStorage();

  static const _customerCodeKey = 'yallah_commercial_customer_code_v1';
  static const _requestIdKey = 'yallah_commercial_request_id_v1';
  static const _activationSecretKey = 'yallah_commercial_activation_secret_v1';
  static const _deviceTokenKey = 'yallah_commercial_device_token_v1';
  static const _leaseTokenKey = 'yallah_commercial_lease_token_v1';
  static const _trustedServerTimeKey = 'yallah_commercial_server_time_v1';

  final CommercialSecretStorage _storage;

  Future<CommercialBackendSecureState> read() async {
    return CommercialBackendSecureState(
      customerCode: await _storage.read(_customerCodeKey),
      requestId: await _storage.read(_requestIdKey),
      activationSecret: await _storage.read(_activationSecretKey),
      deviceToken: await _storage.read(_deviceTokenKey),
      leaseToken: await _storage.read(_leaseTokenKey),
      trustedServerTime: DateTime.tryParse(
        await _storage.read(_trustedServerTimeKey) ?? '',
      )?.toUtc(),
    );
  }

  Future<void> savePending({
    required String customerCode,
    required String requestId,
    required String activationSecret,
  }) async {
    await _storage.write(_customerCodeKey, customerCode);
    await _storage.write(_requestIdKey, requestId);
    await _storage.write(_activationSecretKey, activationSecret);
    await _storage.delete(_deviceTokenKey);
    await _storage.delete(_leaseTokenKey);
    await _storage.delete(_trustedServerTimeKey);
  }

  Future<void> saveApprovedDeviceToken(String token) async {
    await _storage.write(_deviceTokenKey, token);
  }

  Future<void> saveLease({
    required String leaseToken,
    required DateTime serverTime,
  }) async {
    await _storage.write(_leaseTokenKey, leaseToken);
    await _storage.write(
      _trustedServerTimeKey,
      serverTime.toUtc().toIso8601String(),
    );
  }

  Future<void> clearPendingSecrets() async {
    await _storage.delete(_requestIdKey);
    await _storage.delete(_activationSecretKey);
  }

  Future<void> clearAll() async {
    await _storage.delete(_customerCodeKey);
    await _storage.delete(_requestIdKey);
    await _storage.delete(_activationSecretKey);
    await _storage.delete(_deviceTokenKey);
    await _storage.delete(_leaseTokenKey);
    await _storage.delete(_trustedServerTimeKey);
  }
}
