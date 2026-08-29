import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';

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

Future<void> main() async {
  sqfliteFfiInit();

  final path = await DatabaseConstants.dbFilePath();
  if (!File(path).existsSync()) {
    throw StateError('Live DB not found at $path');
  }

  final db = await databaseFactoryFfi.openDatabase(path);

  try {
    final version = firstInt(await db.rawQuery('PRAGMA user_version'));
    if (version != 58) {
      throw StateError('Expected live DB v58, found v$version');
    }

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first.toString() != 'ok') {
      throw StateError('integrity_check failed: $integrity');
    }

    final fk = await db.rawQuery('PRAGMA foreign_key_check');
    if (fk.isNotEmpty) {
      throw StateError('foreign_key_check failed: $fk');
    }

    final gl = await db.rawQuery(r'''
      SELECT
        COUNT(*) AS line_count,
        COALESCE(SUM(debit),0) AS debit_total,
        COALESCE(SUM(credit),0) AS credit_total
      FROM gl_lines
    ''');

    final lineCount = firstInt(gl);
    final debit = number(gl.first['debit_total']);
    final credit = number(gl.first['credit_total']);

    if (lineCount != 1040 ||
        (debit - 1305517.93555).abs() > 0.001 ||
        (credit - 1305517.93555).abs() > 0.001) {
      throw StateError(
        'P1.001 refused: historical GL baseline changed. '
        'lines=$lineCount debit=$debit credit=$credit',
      );
    }

    final unbalanced = firstInt(
      await db.rawQuery(r'''
        SELECT COUNT(*)
        FROM (
          SELECT entry_id, SUM(debit-credit) AS diff
          FROM gl_lines
          GROUP BY entry_id
          HAVING ABS(diff) > 0.01
        )
      '''),
    );

    if (unbalanced != 0) {
      throw StateError('Unbalanced GL entries: $unbalanced');
    }

    stdout.writeln('P1.001 live DB validation PASS.');
    stdout.writeln('Database version: 58');
    stdout.writeln('Integrity check: PASS');
    stdout.writeln('Foreign-key check: PASS');
    stdout.writeln('GL lines unchanged: 1,040');
    stdout.writeln('GL debit total unchanged: 1,305,517.93555 ILS');
    stdout.writeln('GL credit total unchanged: 1,305,517.93555 ILS');
    stdout.writeln('Unbalanced GL entries: 0');
  } finally {
    await db.close();
  }
}
