import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Group3A historical live DB tests require explicit fixtures', () {
    final checks = <String, String>{
      'test/commercial/p1_002_live_migration_validate_test.dart':
          'YALLA_P1002_LIVE_DB_PATH',
      'test/commercial/p1_003_live_migration_validate_test.dart':
          'YALLA_P1003_LIVE_DB_PATH',
      'test/commercial/p1_004_live_presentation_validate_test.dart':
          'YALLA_P1004_LIVE_DB_PATH',
      'test/commercial/sec_001_live_migration_test.dart':
          'YALLA_SEC001_LIVE_DB_PATH',
      'test/commercial/sec_005_live_migration_test.dart':
          'YALLA_SEC005_LIVE_DB_PATH',
      'test/commercial/sec_006_live_migration_test.dart':
          'YALLA_SEC006_LIVE_DB_PATH',
      'test/commercial/sec_007_live_migration_test.dart':
          'YALLA_SEC007_LIVE_DB_PATH',
      'test/commercial/sec_008_live_migration_test.dart':
          'YALLA_SEC008_LIVE_DB_PATH',
      'test/commercial/sec_009_live_validation_test.dart':
          'YALLA_SEC009_LIVE_DB_PATH',
      'test/commercial/sec_010_live_validation_test.dart':
          'YALLA_SEC010_LIVE_DB_PATH',
      'test/commercial/sec_011_live_migration_test.dart':
          'YALLA_SEC011_LIVE_DB_PATH',
      'test/commercial/sec_012_live_migration_test.dart':
          'YALLA_SEC012_LIVE_DB_PATH',
    };

    for (final entry in checks.entries) {
      final source = File(entry.key).readAsStringSync();
      expect(source, contains(entry.value), reason: entry.key);
      expect(source, contains('skip:'), reason: entry.key);
    }

    for (final path in [
      'test/commercial/p1_002_live_migration_validate_test.dart',
      'test/commercial/p1_003_live_migration_validate_test.dart',
      'test/commercial/p1_004_live_presentation_validate_test.dart',
      'test/commercial/sec_010_live_validation_test.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('DatabaseConstants.dbFilePath()'), isFalse,
          reason: path);
    }
  });

  test('Group3A historical visual tests no longer gate current phase state',
      () {
    for (final path in [
      'test/phase03/yalla_c01_fix3d_iphone_visual_regression_test.dart',
      'test/phase03/yalla_c01_fix4b_phone_report_responsive_test.dart',
      'test/phase03/yalla_phase03_home_shell_test.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('YALLA_PROJECT_STATE.json'), isFalse,
          reason: path);
      expect(source.contains('"last_completed_phase": "P03"'), isFalse,
          reason: path);
    }
  });
}
