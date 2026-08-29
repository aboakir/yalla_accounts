import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'SEC.014 server model foundation remains present and client DB remains v69',
      () {
    final model = jsonDecode(File(
            'server/yalla_licensing_server/database/model/sec_014_super_owner_model.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final version =
        File('server/yalla_licensing_server/database/schema_version.txt')
            .readAsLinesSync();
    expect(model['server_model_version'], 9);
    expect(model['client_database_version'], 69);
    expect(model['client_schema_changed'], isFalse);
    expect(model['master_password'], isFalse);
    expect(model['customer_password_visibility'], isFalse);
    expect(int.parse(version.first.trim()), greaterThanOrEqualTo(9));
  });

  test('SEC.014 creates Super Owner RBAC and scoped Break Glass', () {
    final sql = File(
            'server/yalla_licensing_server/database/migrations/0009_sec_014_super_owner_break_glass.sql')
        .readAsStringSync();
    expect(sql, contains("'YALLA_SUPER_OWNER'"));
    expect(sql, contains("'YALLA_BREAK_GLASS'"));
    expect(sql, contains('yalla_admin_permissions'));
    expect(sql, contains('yalla_authorize_admin_action'));
    expect(sql, contains('yalla_open_break_glass'));
    expect(sql, contains("INTERVAL '5 minutes'"));
    expect(sql, contains("INTERVAL '60 minutes'"));
    expect(sql, contains('organization_id=p_organization_id'));
    expect(sql, contains('yalla_bootstrap_super_owner'));
    expect(sql,
        contains('Cannot remove or revoke the last active YALLA_SUPER_OWNER'));
  });

  test('SEC.014 permission catalog covers owner and force operations', () {
    final sql = File(
            'server/yalla_licensing_server/database/migrations/0009_sec_014_super_owner_break_glass.sql')
        .readAsStringSync();
    for (final permission in [
      'ORGANIZATION.CREATE',
      'ORGANIZATION.SUSPEND',
      'SUBSCRIPTION.RENEW',
      'SUBSCRIPTION.CHANGE_PLAN',
      'ENTITLEMENT.MAX_USERS_SET',
      'ENTITLEMENT.MAX_DEVICES_SET',
      'ACTIVATION.FORCE',
      'DEVICE.REPLACE_FORCE',
      'DEVICE.REVOKE_FORCE',
      'SEAT.OVERRIDE_FORCE',
      'FEATURE.OVERRIDE_FORCE',
      'EXPIRY.OVERRIDE_FORCE',
      'SUBSCRIPTION.RESTORE_FORCE',
      'LICENSE.REFRESH_FORCE',
      'LICENSE.ISSUE',
      'LICENSE.REVOKE',
      'ADMIN.USERS_MANAGE',
      'BREAK_GLASS.OPEN'
    ]) {
      expect(sql, contains("'$permission'"));
    }
    expect(sql, contains('requires_break_glass'));
  });

  test('SEC.014 license issuance never puts signing key in Control Center', () {
    final contract = File(
            'server/yalla_licensing_server/api/super_owner_break_glass_contract.md')
        .readAsStringSync();
    final migration = File(
            'server/yalla_licensing_server/database/migrations/0009_sec_014_super_owner_break_glass.sql')
        .readAsStringSync();
    expect(contract, contains('KMS/HSM/secret-store'));
    expect(contract, contains('private signing key'));
    expect(contract,
        contains('returns only a signed license envelope/public key metadata'));
    expect(migration, contains('yalla_license_issuance_requests'));
    expect(migration.toLowerCase(), isNot(contains('private_key_bytes')));
  });

  test(
      'SEC.014 Control Center retains typed server-authorized actions after hardening',
      () {
    final manifest = jsonDecode(File(
            'server/yalla_licensing_server/control_center/control_center_manifest.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final js = File('server/yalla_licensing_server/control_center/web/app.js')
        .readAsStringSync();
    expect((manifest['server_model_version'] as num).toInt(),
        greaterThanOrEqualTo(9));
    expect((manifest['mutations'] as Map)['enabled'], isTrue);
    expect((manifest['authorization'] as Map)['server_side_only'], isTrue);
    expect(js, contains("request('/actions'"));
    expect(js, contains("request('/break-glass'"));
    expect(js, contains('reason.length<8'));
    expect(js, contains('reason.length<15'));
    expect(js, isNot(contains('SHOW PASSWORD')));
  });
}
