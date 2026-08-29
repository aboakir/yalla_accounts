import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SEC.015 server model is v10 and client DB remains v69', () {
    final model = jsonDecode(File(
            'server/yalla_licensing_server/database/model/sec_015_security_model.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final version =
        File('server/yalla_licensing_server/database/schema_version.txt')
            .readAsLinesSync();
    expect(model['server_model_version'], 10);
    expect(model['client_database_version'], 69);
    expect(model['client_schema_changed'], isFalse);
    expect(version.first.trim(), '10');
    expect(version[1].trim(), 'SEC.015');
  });

  test('SEC.015 stores passwords/tokens only in hardened server forms', () {
    final sql = File(
            'server/yalla_licensing_server/database/migrations/0010_sec_015_security_recovery_sessions_audit.sql')
        .readAsStringSync();
    expect(sql, contains('ARGON2ID'));
    expect(sql, contains(r"password_hash LIKE '$argon2id$%'"));
    expect(sql, contains('pepper_version'));
    expect(sql, contains('access_token_digest'));
    expect(sql, contains('token_digest BYTEA'));
    expect(sql, contains('yalla_admin_refresh_tokens'));
    final lower = sql.toLowerCase();
    expect(lower, isNot(contains('plaintext_password')));
    expect(lower, isNot(contains('refresh_token text')));
    expect(lower, isNot(contains('access_token text')));
  });

  test('SEC.015 enforces MFA, recovery and short-lived reauthentication', () {
    final model = jsonDecode(File(
            'server/yalla_licensing_server/database/model/sec_015_security_model.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final sql = File(
            'server/yalla_licensing_server/database/migrations/0010_sec_015_security_recovery_sessions_audit.sql')
        .readAsStringSync();
    final mfa = (model['mfa'] as Map<String, dynamic>);
    expect((mfa['required_for_roles'] as List),
        containsAll(['YALLA_SUPER_OWNER', 'YALLA_BREAK_GLASS']));
    expect(mfa['break_glass_reauth_max_age_minutes'], 5);
    expect(sql, contains('yalla_admin_reauth_contexts'));
    expect(sql, contains('yalla_assert_fresh_break_glass_reauth'));
    expect(sql, contains("purpose='BREAK_GLASS'"));
    expect(sql, contains('yalla_admin_recovery_codes'));
    expect(sql, contains('yalla_admin_auth_challenges'));
  });

  test('SEC.015 browser does not persist authentication tokens in JS storage',
      () {
    final js = File('server/yalla_licensing_server/control_center/web/app.js')
        .readAsStringSync();
    final html =
        File('server/yalla_licensing_server/control_center/web/index.html')
            .readAsStringSync();
    expect(js, contains("credentials:'include'"));
    expect(js, contains("headers['X-Yalla-CSRF']"));
    expect(js, contains("request('/auth/login'"));
    expect(js, contains("request('/auth/mfa/verify'"));
    expect(js, contains("request('/auth/re-auth'"));
    expect(js, isNot(contains('localStorage')));
    expect(js, isNot(contains('sessionStorage')));
    expect(js, isNot(contains('Bearer ')));
    expect(html, isNot(contains('sessionToken')));
    expect(html, contains('Secure admin access'));
  });

  test('SEC.015 session policy has rotation, reuse detection, bounded lifetime',
      () {
    final model = jsonDecode(File(
            'server/yalla_licensing_server/database/model/sec_015_security_model.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final sessions = model['sessions'] as Map<String, dynamic>;
    expect(sessions['access_minutes'], 15);
    expect(sessions['idle_minutes'], 30);
    expect(sessions['absolute_hours'], 12);
    expect(sessions['refresh_rotation'], isTrue);
    expect(sessions['refresh_reuse_detection'], isTrue);
    expect(sessions['server_token_storage'], 'DIGEST_ONLY');
  });

  test('SEC.015 audit is immutable and hash-chain sealed', () {
    final sql = File(
            'server/yalla_licensing_server/database/migrations/0010_sec_015_security_recovery_sessions_audit.sql')
        .readAsStringSync();
    expect(sql, contains('BEFORE UPDATE OR DELETE ON audit_logs'));
    expect(sql, contains('yalla_audit_chain_seals'));
    expect(sql, contains('yalla_audit_chain_heads'));
    expect(sql, contains('yalla_append_audit_chain_seal'));
    expect(sql, contains("canonicalization='RFC8785-JCS'"));
    expect(sql, contains("hash_algorithm='SHA-256'"));
    expect(sql, contains('Audit records and chain seals are immutable'));
  });

  test(
      'SEC.015 security contract does not expose customer credentials or signing secrets',
      () {
    final contract = File(
            'server/yalla_licensing_server/api/admin_auth_security_contract.md')
        .readAsStringSync();
    expect(contract, contains('No default username/password is seeded'));
    expect(contract, contains('never returns access/refresh token bytes'));
    expect(contract,
        contains('No recovery endpoint returns an existing password'));
    expect(contract, contains('signing secrets'));
    expect(
        contract,
        contains(
            'Browser JavaScript never receives HttpOnly admin-cookie bytes'));
    expect(contract, contains('process-memory only'));
    expect(
      contract,
      contains(
          'MUST NOT be written to SharedPreferences, FlutterSecureStorage, SQLite, URLs, logs, crash reports, or customer data'),
    );
  });
}
