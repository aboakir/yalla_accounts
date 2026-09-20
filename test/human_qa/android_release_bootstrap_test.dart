import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release bootstrap has no unused Facebook auth plugin', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final androidBuild = File('android/build.gradle.kts').readAsStringSync();

    expect(
      pubspec,
      isNot(contains('flutter_facebook_auth:')),
      reason: 'Facebook login is not a supported Yallah Accounts auth path; '
          'auto-registering the plugin without an App ID breaks Android startup.',
    );
    expect(
      androidBuild,
      isNot(contains('flutter_facebook_auth')),
    );
  });
}
