import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test(
      'P02 device unlock stores PIN only through secure storage and PBKDF2 hasher',
      () {
    final s = source('lib/features/auth/services/device_unlock_service.dart');
    expect(s, contains('FlutterSecureStorage'));
    expect(s, contains('PasswordHasher.hash'));
    expect(s, contains('PasswordHasher.verify'));
    expect(s, isNot(contains("setString('yalla_device_unlock")));
  });

  test(
      'P02 supports PIN and local biometrics without bypassing commercial gate',
      () {
    final login = source('lib/features/auth/screens/login_screen.dart');
    final unlock =
        source('lib/features/auth/services/device_unlock_service.dart');
    expect(login, contains('commercialAccessGateServiceProvider'));
    expect(login, contains('DeviceUnlockScaffold'));
    expect(unlock, contains('LocalAuthentication'));
    expect(unlock, contains('biometricOnly:'));
  });

  test(
      'P02 first owner remains activation-authoritative and records contact phone without client OTP',
      () {
    final register =
        source('lib/features/auth/screens/register_user_screen.dart');
    final bootstrap =
        source('lib/features/auth/services/first_owner_bootstrap_service.dart');
    expect(register, contains('إعداد حساب مالك المنشأة'));
    expect(register, contains('bootstrapFirstOwner'));
    expect(bootstrap, contains('Verified online activation is required'));
    expect(bootstrap, contains("'address': request.workshopAddress.trim()"));
    expect(bootstrap, contains("'phone1': phone"));
    expect(register, isNot(contains('OTP =')));
    expect(register, isNot(contains('generateOtp')));
    expect(register, isNot(contains('startCustomerPhoneVerification')));
    expect(register, contains('لا يُطلب رمز SMS لإنشاء الحساب'));
    expect(
        register, contains('الجهاز مفعّلًا بترخيص صالح صادر من Yalla Control'));
  });

  test('P02 OTP client never generates or persists OTP material', () {
    final transport =
        source('lib/features/auth/services/yalla_admin_auth_service.dart');
    final server = source('tools/sec015a/dev_yalla_admin_server.ps1');
    final contract = source(
        'server/yalla_licensing_server/api/customer_phone_verification_contract.md');
    expect(transport, contains('/v1/customer-phone-verification/start'));
    expect(transport, contains('/v1/customer-phone-verification/verify'));
    expect(transport, contains('/v1/customer-phone-verification/consume'));
    expect(server,
        contains("Ensure-StateCollection 'customer_phone_verifications'"));
    expect(server, contains(r'New-PasswordRecord $code'));
    expect(server, contains('YALLA_SMS_WEBHOOK_URL'));
    expect(contract, contains('OTP plaintext is never returned by the API'));
    expect(transport, isNot(contains('Random.secure')));
    expect(transport, isNot(contains('FlutterSecureStorage')));
  });

  test('P02 registration is a three-step activation-authoritative mobile flow',
      () {
    final s = source('lib/features/auth/screens/register_user_screen.dart');
    for (final marker in ['1/3', '2/3', '3/3']) {
      expect(s, contains(marker));
    }
    expect(s, isNot(contains('4/4')));
    expect(s, contains('إنشاء الحساب ومتابعة الإعداد'));
    expect(s, contains("'حفظته'"));
  });
}
