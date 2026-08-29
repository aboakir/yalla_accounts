import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _norm(String path) =>
    File(path).absolute.path.replaceAll('\\', '/').toLowerCase();

void main() {
  test('SQLite runtime tuning has one central owner', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final migration = File(
      'lib/core/services/db/database_migration.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/core/services/db/database_platform_policy.dart',
    ).readAsStringSync();
    final health = File(
      'lib/features/settings/services/data_health_service.dart',
    ).readAsStringSync();

    expect(mainSource, isNot(contains('PRAGMA journal_mode')));
    expect(mainSource, isNot(contains('PRAGMA busy_timeout')));
    expect(mainSource, isNot(contains('PRAGMA synchronous')));
    expect(mainSource, isNot(contains('PRAGMA foreign_keys')));

    expect(migration, contains('DatabasePlatformPolicy.configure(db)'));
    expect(migration, contains('DatabasePlatformPolicy.checkpoint(db)'));
    expect(migration, isNot(contains('PRAGMA journal_mode')));
    expect(migration, isNot(contains('PRAGMA busy_timeout')));
    expect(migration, isNot(contains('PRAGMA synchronous')));
    expect(migration, isNot(contains('PRAGMA wal_checkpoint')));

    expect(health, contains('DatabasePlatformPolicy.checkpoint'));
    expect(health, isNot(contains('PRAGMA wal_checkpoint')));

    expect(policy, contains('if (isIOS) return;'));
    expect(policy, contains('PRAGMA foreign_keys = ON;'));
    expect(policy, contains('PRAGMA journal_mode = WAL;'));
    expect(policy, contains('PRAGMA synchronous = NORMAL;'));
    expect(policy, contains('PRAGMA busy_timeout = 8000;'));
  });

  test('no runtime tuning PRAGMA escapes central policy', () {
    final policyPath = _norm(
      'lib/core/services/db/database_platform_policy.dart',
    );

    final forbidden = RegExp(
      r'PRAGMA\s+(journal_mode|busy_timeout|synchronous|wal_checkpoint)'
      r'|PRAGMA\s+foreign_keys\s*=',
      caseSensitive: false,
    );

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_norm(entity.path) == policyPath) continue;

      if (forbidden.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Runtime tuning PRAGMAs must live only in DatabasePlatformPolicy.',
    );
  });

  test('mobile canonical DB path uses Application Support sandbox', () {
    final constants = File(
      'lib/core/services/db/database_constants.dart',
    ).readAsStringSync();

    expect(constants, contains('Platform.isIOS || Platform.isAndroid'));
    expect(constants, contains('getApplicationSupportDirectory()'));
  });
}
