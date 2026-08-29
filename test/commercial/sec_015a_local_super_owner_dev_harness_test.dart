import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SEC.015A insecure loopback is compile-time opt-in and defaults off',
      () {
    final source = File(
      'lib/features/auth/services/yalla_admin_auth_service.dart',
    ).readAsStringSync();

    expect(source, contains('YALLA_ALLOW_INSECURE_LOOPBACK_FOR_TESTING'));
    expect(source, contains('defaultValue: false'));
    expect(
      source,
      contains(
        "allowInsecureLoopbackForTesting && uri.scheme == 'http' && loopback",
      ),
    );
  });

  test('SEC.015A local harness is explicitly development-only', () {
    final server = File(
      'tools/sec015a/dev_yalla_admin_server.ps1',
    ).readAsStringSync();
    final runner = File(
      'tools/sec015a/run_local_super_owner.ps1',
    ).readAsStringSync();
    final helper = File(
      'tools/sec015a/show_local_mfa_code.ps1',
    ).readAsStringSync();

    expect(server, contains('LOCAL_DEVELOPMENT_ONLY'));
    expect(server, contains('http://127.0.0.1:'));
    expect(server, isNot(contains('0.0.0.0')));
    expect(server, isNot(contains('admin123')));

    expect(server, contains('[LOGIN] Current TOTP code:'));
    expect(server, contains('[LOGIN] MFA rejected. Current TOTP code:'));
    expect(runner, contains(r'$env:USERPROFILE\Downloads'));
    expect(runner, contains('YALLA_ALLOW_INSECURE_LOOPBACK_FOR_TESTING=true'));
    expect(runner, contains('-Verb RunAs'));
    expect(helper, contains('LOCAL DEVELOPMENT MFA CODE'));
    expect(helper, contains(r'\Downloads\Yalla_Local_Admin_Dev'));
  });
}
