import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SEC.012 server policy signs concrete periodic validation deadlines',
      () {
    final migration = File(
      'server/yalla_licensing_server/database/migrations/'
      '0007_sec_012_periodic_online_validation_grace.sql',
    ).readAsStringSync();
    expect(migration,
        contains('validation_interval_days INTEGER NOT NULL DEFAULT 30'));
    expect(migration,
        contains('validation_grace_days INTEGER NOT NULL DEFAULT 7'));
    expect(migration, contains('yalla_license_validation_window'));
    expect(migration, contains('yalla_record_periodic_validation'));

    final schema = jsonDecode(
      File(
        'server/yalla_licensing_server/crypto/license_envelope.schema.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    final payload = ((schema['properties'] as Map)['payload'] as Map);
    final required = (payload['required'] as List).cast<String>();
    expect(required, contains('validation_required_at'));
    expect(required, contains('validation_grace_until'));

    final contract = File(
      'server/yalla_licensing_server/api/periodic_validation_contract.md',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    expect(contract, contains('30 validation days plus 7 offline grace days'));
    expect(contract, contains('fresh Yalla-signed license'));
    expect(contract, contains('operational writes fail closed into READ ONLY'));
  });

  test('SEC.012 client has scheduler plus DB-level grace enforcement', () {
    final scheduler = File(
      'lib/core/licensing/validation/periodic_license_validation_service.dart',
    ).readAsStringSync();
    final triggers = File(
      'lib/core/services/db/tables/license_runtime_tables.dart',
    ).readAsStringSync();
    expect(scheduler, contains('Duration(hours: 1)'));
    expect(scheduler, contains("_safeEvaluate(service, 'STARTUP')"));
    expect(scheduler, contains("_lifecycleService.validateNow()"));
    expect(triggers, contains('READ_ONLY_VALIDATION_REQUIRED'));
    expect(triggers, contains('validation_grace_until'));
  });
}
