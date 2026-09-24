import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';

void main() {
  tearDown(CommercialBackendRuntimeAccess.reset);

  test('FULL permits writes', () {
    CommercialBackendRuntimeAccess.applyAccessMode('FULL');
    expect(CommercialBackendRuntimeAccess.canRead, isTrue);
    expect(CommercialBackendRuntimeAccess.canWrite, isTrue);
    expect(() => CommercialBackendRuntimeAccess.requireWrite('SAVE'),
        returnsNormally);
  });

  test('READ_ONLY keeps reads and blocks writes', () {
    CommercialBackendRuntimeAccess.applyAccessMode('READ_ONLY');
    expect(CommercialBackendRuntimeAccess.canRead, isTrue);
    expect(CommercialBackendRuntimeAccess.canWrite, isFalse);
    expect(
      () => CommercialBackendRuntimeAccess.requireWrite('PAYMENT_CREATE'),
      throwsA(isA<CommercialBackendWriteBlocked>()),
    );
  });

  test('BLOCKED and unknown fail closed', () {
    for (final mode in ['BLOCKED', 'unexpected']) {
      CommercialBackendRuntimeAccess.applyAccessMode(mode);
      expect(CommercialBackendRuntimeAccess.canWrite, isFalse);
      expect(
        () => CommercialBackendRuntimeAccess.requireWrite('CHEQUE_CREATE'),
        throwsA(isA<CommercialBackendWriteBlocked>()),
      );
    }
  });
}
