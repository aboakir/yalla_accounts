import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/repairs/services/repair_historical_reconciliation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realDb = Platform.environment['YALLAH_TRACK_B_REAL_DB'];
  final realBackup = Platform.environment['YALLAH_TRACK_B_RECON_BACKUP'];
  final realReport = Platform.environment['YALLAH_TRACK_B_RECON_REPORT'];

  test('B12 real-data repair reconciliation is evidenced and idempotent',
      () async {
    final path = realDb!;
    final backup = realBackup!;
    final report = realReport!;
    expect(File(path).existsSync(), isTrue);
    expect(File(backup).existsSync(), isTrue);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      final before = await RepairHistoricalReconciliationService.audit(db);
      final result = await RepairHistoricalReconciliationService.reconcile(
        db,
        backupPath: backup,
      );
      final after = await RepairHistoricalReconciliationService.audit(db);
      final retry = await RepairHistoricalReconciliationService.reconcile(
        db,
        backupPath: backup,
      );

      final unbalanced = await db.rawQuery('''
        SELECT l.entry_id
        FROM gl_lines l
        GROUP BY l.entry_id
        HAVING ABS(SUM(l.debit-l.credit)) > 0.001
      ''');
      final duplicateRecon = await db.rawQuery('''
        SELECT source_id, COUNT(*) n
        FROM gl_entries
        WHERE source=?
        GROUP BY source_id
        HAVING COUNT(*) > 1
      ''', [RepairHistoricalReconciliationService.source]);
      final payload = {
        'before_count': before.length,
        'before_repairable': before.where((x) => x.repairable).length,
        'repaired': result.repaired,
        'corrected_amount': result.correctedAmount,
        'after_count': after.length,
        'after_repairable': after.where((x) => x.repairable).length,
        'retry_repaired': retry.repaired,
        'unbalanced_gl': unbalanced.length,
        'duplicate_reconciliation_postings': duplicateRecon.length,
        'before': before.map((x) => x.toJson()).toList(),
        'after': after.map((x) => x.toJson()).toList(),
      };
      await File(report).writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );

      expect(result.repaired, before.where((x) => x.repairable).length);
      expect(after.where((x) => x.repairable), isEmpty);
      expect(retry.repaired, 0);
      expect(unbalanced, isEmpty);
      expect(duplicateRecon, isEmpty);
    } finally {
      await db.close();
      DatabaseMigration.useDatabaseForTesting(null);
    }
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: realDb == null || realBackup == null || realReport == null
          ? 'Requires Track B real-data environment.'
          : false);
}
