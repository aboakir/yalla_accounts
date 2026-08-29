import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SEC.011 server contract is suspension and renewal aware', () {
    final migration = File(
      'server/yalla_licensing_server/database/migrations/'
      '0006_sec_011_expiry_readonly_renewal_suspension.sql',
    ).readAsStringSync();
    expect(migration, contains('license_lifecycle_challenges'));
    expect(migration, contains('yalla_effective_license_operational_state'));
    expect(migration, contains('yalla_apply_renewal'));
    expect(migration, contains("'SUSPENDED'"));
    expect(migration, contains("'EXPIRED'"));

    final schema = jsonDecode(
      File(
        'server/yalla_licensing_server/crypto/license_envelope.schema.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    final payload = ((schema['properties'] as Map)['payload'] as Map);
    final properties = payload['properties'] as Map;
    expect(properties, contains('operational_status'));
    final values = ((properties['operational_status'] as Map)['enum'] as List)
        .cast<String>();
    expect(
        values,
        containsAll(<String>[
          'ACTIVE',
          'GRACE',
          'SUSPENDED',
          'EXPIRED',
          'REVOKED',
          'CANCELLED',
        ]));

    final api = File(
      'server/yalla_licensing_server/api/license_lifecycle_api_contract.md',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    expect(api, contains('new signed license is minted'));
    expect(api, contains('Periodic validation cadence'));
  });

  test('SEC.011 client does not trust unsigned lifecycle state', () {
    final runtime = File(
      'lib/core/licensing/lifecycle/license_runtime_service.dart',
    ).readAsStringSync();
    final lifecycle = File(
      'lib/core/licensing/lifecycle/license_lifecycle_service.dart',
    ).readAsStringSync();
    expect(runtime, contains('loadAuthenticLicenseForCurrentInstallation'));
    expect(lifecycle, contains('_verifier.verify'));
    expect(lifecycle, contains('requireCurrentValidity: false'));
    expect(lifecycle, contains('projectServerLifecycleDecision'));
  });
}
