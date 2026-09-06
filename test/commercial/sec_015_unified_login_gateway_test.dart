import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  String read(String relative) => File('$root/$relative').readAsStringSync();

  test('SEC.015 uses one login screen for Yalla admin and customer realms', () {
    final login = read('lib/features/auth/screens/login_screen.dart');

    expect(login, contains('اسم المستخدم أو البريد الإلكتروني'));
    expect(login, contains('yallaAdminAuthServiceProvider'));
    expect(login, contains('YallaControlCenterScreen'));
    expect(login, contains('YallaAdminLoginState.mfaRequired'));
    expect(login, contains('authenticateUser('));
    expect(login, contains('نفس شاشة الدخول لحسابات Yalla الإدارية'));
  });

  test('Yalla admin credentials remain server-side and sessions memory-only',
      () {
    final transport =
        read('lib/features/auth/services/yalla_admin_auth_service.dart');

    expect(transport,
        contains("String.fromEnvironment('YALLA_LICENSING_BASE_URL')"));
    expect(transport, contains('/v1/control-center/auth/login'));
    expect(transport, contains('/v1/control-center/auth/mfa/verify'));
    expect(transport, contains('/v1/control-center/auth/session'));
    expect(transport, contains('final Map<String, String> _sessionCookies'));
    expect(transport, isNot(contains('SharedPreferences')));
    expect(transport, isNot(contains('FlutterSecureStorage')));
    expect(transport, isNot(contains('sqflite')));
    expect(transport, isNot(contains('password =')));
  });

  test('first Yalla admin enrollment is one-time server-authorized', () {
    final transport =
        read('lib/features/auth/services/yalla_admin_auth_service.dart');
    final dialogs =
        read('lib/features/auth/screens/yalla_admin_account_dialogs.dart');
    final contract = read(
      'server/yalla_licensing_server/api/admin_auth_security_contract.md',
    );

    expect(transport, contains('/auth/enrollment/start'));
    expect(transport, contains('/auth/enrollment/complete'));
    expect(dialogs, contains('Enrollment Secret لمرة واحدة'));
    expect(contract, contains('one-time server-issued enrollment secret'));
    expect(contract, contains('never seeds a default password'));
  });

  test('native Control Center exposes server sections and protected actions',
      () {
    final screen =
        read('lib/features/auth/screens/yalla_control_center_screen.dart');

    expect(screen, contains("'organizations'"));
    expect(screen, contains("'subscriptions'"));
    expect(screen, contains("'licenses'"));
    expect(screen, contains("'devices'"));
    expect(screen, contains("'admin-users'"));
    expect(screen, contains('ADMIN.USERS_MANAGE'));
    expect(screen, contains('Break Glass'));
    expect(screen, contains('reauthenticateForBreakGlass'));
  });

  test('Control Center server model stays v10 and client DB stays v69', () {
    final manifest = jsonDecode(
      read(
        'server/yalla_licensing_server/control_center/control_center_manifest.json',
      ),
    ) as Map<String, dynamic>;

    final presentation = manifest['presentation'] as Map<String, dynamic>;
    final authentication = manifest['authentication'] as Map<String, dynamic>;

    expect(manifest['server_model_version'], 10);
    expect(manifest['client_database_version'], 69);
    expect(presentation['native_same_executable'], isTrue);
    expect(presentation['customer_sqlite_control_plane_exposure'], isFalse);
    expect(authentication['native_persisted_admin_tokens'], isFalse);
  });

  test('no master password or hardcoded Super Owner credential is introduced',
      () {
    final login = read('lib/features/auth/screens/login_screen.dart');
    final transport =
        read('lib/features/auth/services/yalla_admin_auth_service.dart');
    final combined = '$login\n$transport'.toLowerCase();

    expect(combined, isNot(contains('admin123')));
    expect(combined, isNot(contains('master_password')));
    expect(combined, isNot(contains('universal password')));
    expect(combined, isNot(contains('hardcoded password')));
  });
}
