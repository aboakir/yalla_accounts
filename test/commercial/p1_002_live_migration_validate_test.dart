import 'dart:io';

import 'package:sqflite/sqflite.dart' as sq;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/auth/services/password_hasher.dart';

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

Future<Map<String, Object?>> financialBaseline(sq.Database db) async {
  final gl = await db.rawQuery('''
    SELECT
      COUNT(*) AS line_count,
      COALESCE(SUM(debit), 0) AS debit_total,
      COALESCE(SUM(credit), 0) AS credit_total
    FROM gl_lines
  ''');

  return {
    'line_count': firstInt(gl),
    'debit_total': number(gl.first['debit_total']),
    'credit_total': number(gl.first['credit_total']),
  };
}

void main() {
  test('P1.002 live DB migration v58 -> v59 preserves accounting', () async {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;

    final path = await DatabaseConstants.dbFilePath();
    if (!File(path).existsSync()) {
      throw StateError('Live DB not found at $path');
    }

    final beforeDb = await databaseFactoryFfi.openDatabase(path);

    final int beforeVersion;
    final List<Map<String, Object?>> beforeUsers;
    final int activationCodesBefore;
    final Map<String, Object?> financialBefore;

    try {
      beforeVersion = firstInt(
        await beforeDb.rawQuery('PRAGMA user_version'),
      );

      if (beforeVersion != 58) {
        throw StateError(
          'P1.002 expected audited live DB v58, found v$beforeVersion',
        );
      }

      beforeUsers = await beforeDb.query(
        'users',
        columns: [
          'id',
          'name',
          'email',
          'password',
          'role',
          'status',
          'is_owner',
          'created_at',
        ],
        orderBy: 'created_at ASC',
      );

      if (beforeUsers.length != 1) {
        throw StateError(
          'P1.002 audited baseline expected exactly one current user; '
          'found ${beforeUsers.length}.',
        );
      }

      activationCodesBefore = firstInt(
        await beforeDb.rawQuery(
          'SELECT COUNT(*) FROM activation_codes',
        ),
      );

      financialBefore = await financialBaseline(beforeDb);
    } finally {
      await beforeDb.close();
    }

    final migrated = await DatabaseMigration.initDatabase(
      pathOverride: path,
    );

    try {
      final version = firstInt(
        await migrated.rawQuery('PRAGMA user_version'),
      );
      if (version != 59) {
        throw StateError('Expected DB v59 after P1.002, found v$version');
      }

      final integrity = await migrated.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw StateError('integrity_check failed: $integrity');
      }

      final fk = await migrated.rawQuery('PRAGMA foreign_key_check');
      if (fk.isNotEmpty) {
        throw StateError('foreign_key_check failed: $fk');
      }

      final afterUsers = await migrated.query(
        'users',
        columns: [
          'id',
          'name',
          'email',
          'password',
          'role',
          'status',
          'is_owner',
          'created_at',
          'must_change_password',
        ],
        orderBy: 'created_at ASC',
      );

      if (afterUsers.length != beforeUsers.length) {
        throw StateError('User count changed during P1.002 migration.');
      }

      for (var i = 0; i < beforeUsers.length; i++) {
        final before = beforeUsers[i];
        final after = afterUsers[i];

        for (final field in [
          'id',
          'name',
          'email',
          'password',
          'role',
          'status',
          'is_owner',
          'created_at',
        ]) {
          if (before[field]?.toString() != after[field]?.toString()) {
            throw StateError(
              'P1.002 migration unexpectedly changed users.$field',
            );
          }
        }

        final password = after['password']?.toString() ?? '';
        if (PasswordHasher.isLegacySha256(password) &&
            (after['must_change_password'] as num?)?.toInt() != 1) {
          throw StateError(
            'Legacy credential was not flagged for mandatory change.',
          );
        }
      }

      final activationCodesAfter = firstInt(
        await migrated.rawQuery(
          'SELECT COUNT(*) FROM activation_codes',
        ),
      );
      if (activationCodesAfter != activationCodesBefore) {
        throw StateError(
          'Legacy activation-code rows were modified by migration.',
        );
      }

      final sessions = firstInt(
        await migrated.rawQuery('SELECT COUNT(*) FROM auth_sessions'),
      );
      final grants = firstInt(
        await migrated.rawQuery(
          'SELECT COUNT(*) FROM password_reset_grants',
        ),
      );

      if (sessions != 0 || grants != 0) {
        throw StateError(
          'P1.002 migration must not invent sessions/reset grants.',
        );
      }

      final financialAfter = await financialBaseline(migrated);
      if (financialBefore['line_count'] != financialAfter['line_count'] ||
          (number(financialBefore['debit_total']) -
                      number(financialAfter['debit_total']))
                  .abs() >
              0.001 ||
          (number(financialBefore['credit_total']) -
                      number(financialAfter['credit_total']))
                  .abs() >
              0.001) {
        throw StateError(
          'Historical GL changed during P1.002 migration.',
        );
      }

      print('P1.002 live migration validation PASS.');
      print('Database version: 58 -> 59');
      print('Existing users preserved: ${afterUsers.length}');
      print('Existing password bytes preserved by migration: PASS');
      print('Legacy credential mandatory-change flag: PASS');
      print('Fresh auth sessions created by migration: 0');
      print('Fresh password-reset grants created by migration: 0');
      print('Legacy activation rows preserved: $activationCodesAfter');
      print('Historical GL totals unchanged: PASS');
      print('Foreign-key validation: PASS');
      print('DB integrity: PASS');
    } finally {
      await migrated.close();
    }
  });
}
