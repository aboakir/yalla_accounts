import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('C06 final preparation contracts', () {
    test('production identifiers are no longer com.example', () {
      final gradle = read('android/app/build.gradle.kts');
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final pbx = read('ios/Runner.xcodeproj/project.pbxproj');
      final mainActivity =
          read('android/app/src/main/kotlin/ps/yalla/accounts/MainActivity.kt');

      expect(gradle, contains('namespace = "ps.yalla.accounts"'));
      expect(gradle, contains('applicationId = "ps.yalla.accounts"'));
      expect(manifest, contains('package="ps.yalla.accounts"'));
      expect(pbx, contains('PRODUCT_BUNDLE_IDENTIFIER = ps.yalla.accounts;'));
      expect(mainActivity, contains('package ps.yalla.accounts'));

      expect(gradle, isNot(contains('com.example')));
      expect(manifest, isNot(contains('com.example')));
      expect(pbx, isNot(contains('com.example')));
      expect(mainActivity, isNot(contains('com.example')));
    });

    test('RC version and Android release signing guard are present', () {
      final pubspec = read('pubspec.yaml');
      final gradle = read('android/app/build.gradle.kts');

      expect(pubspec, contains('version: 1.0.2+21'));
      expect(gradle, contains('keystorePropertiesFile'));
      expect(gradle, contains('signingConfigs'));
      expect(gradle, contains('prepare_android_signing.ps1'));
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    });

    test('C06 licensing test authority and real-client build wrapper exist',
        () {
      for (final path in <String>[
        'server/yalla_licensing_server/runtime/server.mjs',
        'server/yalla_licensing_server/runtime/init_c06.mjs',
        'server/yalla_licensing_server/runtime/selftest.mjs',
        'server/yalla_licensing_server/runtime/lib/authority.mjs',
        'tools/c06/prepare_c06_test.ps1',
        'tools/c06/stop_c06_test.ps1',
        'tools/c06/verify_c06_test.ps1',
        'ci/c06_build_ios.sh',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }

      final authority =
          read('server/yalla_licensing_server/runtime/lib/authority.mjs');
      expect(authority, contains('ACCOUNTING_CORE: true'));
      expect(authority, contains('MAX_USERS: 10'));
      expect(authority, contains('MAX_DEVICES: 3'));
      expect(authority, contains("issuer: 'yalla-licensing'"));
      expect(authority, contains("operational_status"));
    });

    test('C06 build has no commercial bypass', () {
      final build = read('ci/c06_build_ios.sh');
      expect(build, contains('YALLA_LICENSING_BASE_URL'));
      expect(build, contains('YALLA_LICENSE_TRUSTED_KEY_SHA256'));
      expect(build, contains('YALLA_STORE_DISTRIBUTION'));
      expect(build, contains('flutter build ios --release --no-codesign'));
      expect(build, isNot(contains('kTemporaryAuthBypass')));
      expect(build, isNot(contains('1000000000')));
      expect(build, isNot(contains('10 ملفات')));
    });

    test('legal test endpoints are present for C06 store-distribution build',
        () {
      final server = read('server/yalla_licensing_server/runtime/server.mjs');
      expect(server, contains("url.pathname === '/privacy'"));
      expect(server, contains("url.pathname === '/terms'"));
      expect(server, contains("url.pathname === '/account-deletion'"));
      expect(server, contains('/v1/account-deletion-requests'));
    });
  });
}
