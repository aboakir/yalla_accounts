import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SEC.010 server device lifecycle and capacity contract is canonical',
      () {
    final sql = File(
      'server/yalla_licensing_server/database/migrations/0005_sec_010_device_management.sql',
    ).readAsStringSync();
    final model = jsonDecode(File(
      'server/yalla_licensing_server/database/model/sec_010_device_management_model.json',
    ).readAsStringSync()) as Map<String, dynamic>;

    expect(model['server_model_version'], 5);
    expect(model['client_database_version'], 67);
    expect(model['client_schema_changed'], isFalse);
    expect(model['client_declares_activation_kind'], isFalse);
    expect((model['device_statuses'] as List).toSet(),
        {'ACTIVE', 'SUSPENDED', 'REVOKED', 'REPLACED'});
    expect((model['actions'] as List).toSet(),
        {'ADD_DEVICE', 'REACTIVATE', 'SUSPEND', 'RESUME', 'REVOKE', 'REPLACE'});

    expect(sql, contains('yalla_device_slots_used'));
    expect(sql, contains('yalla_max_devices'));
    expect(sql, contains('yalla_assert_device_capacity'));
    expect(sql, contains("status IN ('ACTIVE','SUSPENDED')"));
    expect(
        sql,
        contains(
            "activation_kind IN ('FIRST','ADD_DEVICE','REACTIVATION','DEVICE_REPLACEMENT','LICENSE_REFRESH')"));
    expect(sql,
        contains('management_protocol_version SMALLINT NOT NULL DEFAULT 1'));
    expect(sql, contains('management_protocol_version = 2'));
    expect(model['managed_grant_protocol_version'], 2);
    expect(model['legacy_grant_protocol_version'], 1);
    expect(sql, contains('Terminal device status'));
    expect(sql, contains("VALUES (5, 'SEC.010'"));
  });

  test('SEC.010 activation request protocol does not let client choose kind',
      () {
    final source = File(
      'lib/core/licensing/activation/activation_transport.dart',
    ).readAsStringSync();
    final schema = jsonDecode(File(
      'server/yalla_licensing_server/api/schemas/activation_challenge_request.schema.json',
    ).readAsStringSync()) as Map<String, dynamic>;
    final required = (schema['required'] as List).cast<String>();
    final props = schema['properties'] as Map<String, dynamic>;

    expect(source, contains("'api_version': 2"));
    expect(source, isNot(contains("'activation_kind': 'FIRST'")));
    expect(required, isNot(contains('activation_kind')));
    expect(props.containsKey('activation_kind'), isFalse);
    expect((props['api_version'] as Map)['const'], 2);
  });

  test('SEC.010 does not implement Control Center or Super Owner early', () {
    final api = File(
      'server/yalla_licensing_server/api/device_management_api_contract.md',
    ).readAsStringSync();
    final normalizedApi = api.replaceAll(RegExp(r'\s+'), ' ');
    expect(api, contains('SEC.013'));
    expect(api, contains('SEC.014'));
    expect(normalizedApi, contains('never trusts a desktop customer'));
  });
}
