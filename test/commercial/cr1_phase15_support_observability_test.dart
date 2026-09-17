import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_transport.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_lifecycle_transport.dart';
import 'package:yalla_accounts/core/security/release_diagnostics.dart';
import 'package:yalla_accounts/core/services/sync/sync_v3_transport.dart';

void main() {
  test('Phase 15 release diagnostics hide raw runtime details', () {
    final text = ReleaseDiagnostics.publicFailureText(
      StateError('secret-token-password-otp'),
      debugMode: false,
    );
    expect(text, 'رمز الخطأ: ${ReleaseDiagnostics.startupBlockedCode}');
    expect(text, isNot(contains('secret-token-password-otp')));
  });

  test('Phase 15 client transport errors preserve safe support request IDs',
      () {
    const activation = ActivationTransportException('rejected',
        statusCode: 409, supportRequestId: 'req-act-1');
    const lifecycle = LicenseLifecycleTransportException('rejected',
        statusCode: 409, supportRequestId: 'req-life-1');
    const sync = SyncV3TransportException('rejected',
        statusCode: 409, code: 'SYNC_REJECTED', supportRequestId: 'req-sync-1');
    expect(activation.toString(), contains('req-act-1'));
    expect(lifecycle.toString(), contains('req-life-1'));
    expect(sync.toString(), contains('req-sync-1'));
  });

  test(
      'Phase 15 HTTP transports extract request correlation without logging payloads',
      () {
    for (final path in [
      'lib/core/licensing/activation/activation_transport.dart',
      'lib/core/licensing/lifecycle/license_lifecycle_transport.dart',
      'lib/core/services/sync/sync_v3_transport.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains("['request_id']"), reason: path);
      expect(source, contains("value('x-request-id')"), reason: path);
      expect(source, isNot(contains('debugPrint(jsonEncode(body))')),
          reason: path);
      expect(source, isNot(contains('print(token)')), reason: path);
    }
  });
}
