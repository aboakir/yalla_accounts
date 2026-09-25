import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('SEC.015 customer login exposes safe remember/session controls', () {
    final login = read('lib/features/auth/screens/login_screen.dart');
    final sessions =
        read('lib/features/auth/services/auth_session_service.dart');

    expect(login, contains('حفظ الدخول على هذا الجهاز باستخدام PIN'));
    expect(login, contains('نسيت بيانات الدخول'));
    expect(login, contains('إنشاء ورشة جديدة'));
    expect(login, contains('DeviceUnlockScaffold'));

    expect(sessions, contains('FlutterSecureStorage'));
    expect(sessions, contains('forgetSavedLoginData'));
    expect(sessions, contains('_ephemeralToken'));
    expect(sessions, contains('on FlutterError'));
    expect(sessions, isNot(contains('ServicesBinding.instance;')));
    expect(sessions, isNot(contains("setString(_tokenKey")));
  });

  test('SEC.015 owner can manage users and temporary passwords', () {
    final users = read('lib/features/auth/screens/manage_users_screen.dart');
    final service = read('lib/features/auth/services/user_service.dart');
    final add = read('lib/features/auth/widgets/add_user_dialog.dart');

    expect(users, contains('المستخدمون والصلاحيات'));
    expect(users, contains('إضافة مستخدم'));
    expect(users, contains('تعيين كلمة مرور مؤقتة'));
    expect(users, contains('resetUserPasswordByOwner'));
    expect(service, contains('resetUserPasswordByOwner'));
    expect(service, contains("'must_change_password': 1"));
    expect(add, contains('سيُجبر المستخدم على تغييرها'));
    expect(add, contains('Icons.visibility'));
  });

  test('SEC.015 password change/recovery supports visibility and owner flow',
      () {
    final reset = read('lib/features/auth/screens/reset_password_screen.dart');
    final recover =
        read('lib/features/auth/screens/recover_access_dialog.dart');
    final account =
        read('lib/features/auth/screens/account_security_screen.dart');

    expect(reset, contains('إظهار كلمة المرور'));
    expect(reset, contains('كلمة المرور الحالية'));
    expect(reset, contains('تأكيد كلمة المرور'));
    expect(recover, contains('نسيت اسم المستخدم'));
    expect(recover, contains('نسيت كلمة المرور'));
    expect(recover, contains('createResetGrantWithRecoveryCode'));
    expect(account, contains('حسابي وأمان الحساب'));
    expect(account, contains('نسيان بيانات الدخول المحفوظة'));
    expect(account, contains('إنشاء كود استعادة جديد'));
  });

  test('SEC.015 workshop settings links account and user management', () {
    final settings =
        read('lib/features/settings/screens/workshop_settings_screen.dart');

    expect(settings, contains('AccountSecurityScreen'));
    expect(settings, contains('ManageUsersScreen'));
    expect(settings, contains('الحسابات وكلمات المرور'));
  });

  test('SEC.015 first-owner setup remains one-time and activation-gated', () {
    final register =
        read('lib/features/auth/screens/register_user_screen.dart');
    final bootstrap =
        read('lib/features/auth/services/first_owner_bootstrap_service.dart');

    expect(register, contains('إنشاء بيانات دخول المالك'));
    expect(register, contains('hasAnyUsers'));
    expect(bootstrap, contains('Verified online activation is required'));
    expect(bootstrap, contains("'status': 'COMPLETED'"));
  });
}
