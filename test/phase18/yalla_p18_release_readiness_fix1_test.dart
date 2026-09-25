import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('P18 release readiness FIX1', () {
    test(
      'Android release manifest uses scoped storage and production internet',
      () {
        final source = _read('android/app/src/main/AndroidManifest.xml');

        expect(source, contains('android.permission.INTERNET'));
        expect(source, contains('android.permission.USE_BIOMETRIC'));
        expect(source, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
        expect(source, isNot(contains('READ_EXTERNAL_STORAGE')));
        expect(source, isNot(contains('WRITE_EXTERNAL_STORAGE')));
        expect(source, isNot(contains('tools:ignore')));
      },
    );

    test(
      'Android targets API 36 and release never falls back to debug signing',
      () {
        final source = _read('android/app/build.gradle.kts');

        expect(source, contains('compileSdk = 36'));
        expect(source, contains('targetSdk = 36'));
        expect(source, isNot(contains('signingConfigs.getByName("debug")')));
      },
    );

    test('iOS declares camera and photo-library purpose strings', () {
      final source = _read('ios/Runner/Info.plist');

      expect(source, contains('NSCameraUsageDescription'));
      expect(source, contains('NSPhotoLibraryUsageDescription'));
    });

    test(
      'store distribution bundles legal documents and keeps onboarding available',
      () {
        final config = _read(
          'lib/core/release/release_distribution_config.dart',
        );
        final links = _read(
          'lib/core/release/widgets/release_legal_links.dart',
        );
        final login = _read('lib/features/auth/screens/login_screen.dart');
        final subscription = _read(
          'lib/features/subscription/screens/subscription_screen.dart',
        );

        expect(config, contains('YALLA_STORE_DISTRIBUTION'));
        expect(config, isNot(contains('YALLA_PRIVACY_URL')));
        expect(config, isNot(contains('YALLA_TERMS_URL')));
        expect(links, contains('LocalLegalDocumentScreen'));
        expect(links, contains('LocalLegalDocuments.privacy'));
        expect(links, contains('LocalLegalDocuments.terms'));
        expect(links, isNot(contains('launchUrl')));
        expect(login, contains('إنشاء ورشة جديدة'));
        expect(login, isNot(contains('ReleaseDistributionConfig')));
        expect(login, contains('ReleaseLegalLinks('));
        expect(login, contains('compact: true'));
        expect(subscription, contains('ReleaseLegalLinks()'));
        expect(subscription, isNot(contains('أرغب بالاشتراك')));
        expect(subscription, isNot(contains('+970598888888')));
        expect(subscription, contains('لا يوجد شراء أو تجديد مدفوع ذاتي'));
        expect(File('assets/legal/privacy_ps_v2.html').existsSync(), isTrue);
        expect(File('assets/legal/terms_ps_v2.html').existsSync(), isTrue);
      },
    );

    test('C06 identifiers are finalized for Yalla Accounts', () {
      final android = _read('android/app/build.gradle.kts');
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      final ios = _read('ios/Runner.xcodeproj/project.pbxproj');

      expect(android, contains('namespace = "ps.yalla.accounts"'));
      expect(android, contains('applicationId = "ps.yalla.accounts"'));
      expect(manifest, contains('package="ps.yalla.accounts"'));
      expect(ios, contains('PRODUCT_BUNDLE_IDENTIFIER = ps.yalla.accounts;'));

      expect(android, isNot(contains('com.example')));
      expect(manifest, isNot(contains('com.example')));
      expect(ios, isNot(contains('com.example.yallaAccounts')));
    });
  });
}
