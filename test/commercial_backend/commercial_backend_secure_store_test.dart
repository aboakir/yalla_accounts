import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_secure_store.dart';

class _MemoryStorage implements CommercialSecretStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  test('pending credentials and approved device token stay in secure store',
      () async {
    final memory = _MemoryStorage();
    final store = CommercialBackendSecureStore(storage: memory);

    await store.savePending(
      customerCode: '+970599000000',
      requestId: 'request-1',
      activationSecret: 'secret-1',
    );
    var state = await store.read();

    expect(state.customerCode, '+970599000000');
    expect(state.hasPendingRequest, isTrue);
    expect(state.hasApprovedDevice, isFalse);
    await store.saveApprovedDeviceToken('device-token-1');
    await store.saveLease(
      leaseToken: 'lease-1',
      serverTime: DateTime.utc(2026, 9, 25, 10),
    );
    state = await store.read();
    expect(state.hasApprovedDevice, isTrue);
    expect(state.deviceToken, 'device-token-1');
    expect(state.leaseToken, 'lease-1');
    expect(state.trustedServerTime, DateTime.utc(2026, 9, 25, 10));

    await store.clearPendingSecrets();
    state = await store.read();
    expect(state.requestId, isNull);
    expect(state.activationSecret, isNull);
    expect(state.deviceToken, 'device-token-1');

    await store.clearAll();
    state = await store.read();
    expect(state.customerCode, isNull);
    expect(state.deviceToken, isNull);
  });
}
