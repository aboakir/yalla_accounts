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
      'P02 first owner remains activation-authoritative and no fake OTP is introduced',
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
  });

  test('P02 registration is a four-step mobile flow', () {
    final s = source('lib/features/auth/screens/register_user_screen.dart');
    for (final marker in ['1/4', '2/4', '3/4', '4/4']) {
      expect(s, contains(marker));
    }
    expect(s, contains('ابدأ استخدام Yalla Accounts'));
  });
}
