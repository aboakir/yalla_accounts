import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Phase 10 Android blocks cleartext and platform data extraction', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final extraction = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    for (final domain in [
      'root',
      'file',
      'database',
      'sharedpref',
      'external'
    ]) {
      expect(extraction, contains('domain="$domain" path="."'));
    }
    expect(extraction, contains('<cloud-backup>'));
    expect(extraction, contains('<device-transfer>'));
  });

  test('Phase 10 iOS keeps App Transport Security fail-closed', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
    expect(plist, isNot(contains('NSAllowsLocalNetworking')));
    expect(plist, isNot(contains('NSExceptionDomains')));
  });
}
