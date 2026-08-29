import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SEC.013 Control Center sections remain present after later stages', () {
    final manifest = jsonDecode(
      File('server/yalla_licensing_server/control_center/control_center_manifest.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final sections = (manifest['sections'] as List)
        .cast<Map<String, dynamic>>()
        .map((e) => e['label'])
        .toSet();
    for (final required in {
      'Dashboard',
      'Organizations',
      'Subscriptions',
      'Licenses',
      'Devices',
      'Plans',
      'Features',
      'Entitlements',
      'Activations',
      'Renewals',
      'Overrides',
      'Security Events',
      'Audit Logs',
      'Yalla Admin Users',
    }) {
      expect(sections, contains(required));
    }
    expect((manifest['server_model_version'] as num).toInt(),
        greaterThanOrEqualTo(8));
    expect(manifest['client_database_version'], 69);
  });

  test('SEC.013 deployment boundary remains separate from client SQLite', () {
    final original = jsonDecode(File(
            'server/yalla_licensing_server/database/model/sec_013_control_center_model.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final version =
        File('server/yalla_licensing_server/database/schema_version.txt')
            .readAsLinesSync();
    expect(original['server_model_version'], 8);
    expect(original['client_database_version'], 69);
    expect(original['client_schema_changed'], isFalse);
    expect(original['deployment_boundary'], 'SEPARATE_FROM_CUSTOMER_CLIENT');
    expect(original['customer_accounting_data_exposed'], isFalse);
    expect(int.parse(version.first.trim()), greaterThanOrEqualTo(8));
  });

  test('SEC.013 canonical read models are preserved', () {
    final sql = File(
            'server/yalla_licensing_server/database/migrations/0008_sec_013_yalla_control_center.sql')
        .readAsStringSync();
    for (final view in [
      'yalla_cc_dashboard',
      'yalla_cc_organizations',
      'yalla_cc_subscriptions',
      'yalla_cc_licenses',
      'yalla_cc_devices',
      'yalla_cc_plans',
      'yalla_cc_features',
      'yalla_cc_entitlements',
      'yalla_cc_activations',
      'yalla_cc_renewals',
      'yalla_cc_overrides',
      'yalla_cc_security_events',
      'yalla_cc_audit_logs',
      'yalla_cc_admin_users'
    ]) {
      expect(sql, contains('VIEW $view'));
    }
    expect(sql, contains("VALUES (8, 'SEC.013'"));
  });

  test('Control Center still uses server API and no hardcoded secret', () {
    final js = File('server/yalla_licensing_server/control_center/web/app.js')
        .readAsStringSync();
    final config = File(
            'server/yalla_licensing_server/control_center/web/config.example.js')
        .readAsStringSync();
    expect(js, contains("method='GET'"));
    expect(js, contains("credentials:'include'"));
    expect(js.toLowerCase(), isNot(contains('master password')));
    expect(config, isNot(contains('Bearer ')));
  });
}
