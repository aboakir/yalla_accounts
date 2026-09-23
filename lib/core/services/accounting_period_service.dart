import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/accounting_integrity_service.dart';
import 'package:yalla_accounts/core/services/accounting_period_guard.dart';
import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';

class AccountingPeriodService {
  AccountingPeriodService._();

  static Future<Database> _database(Database? provided) async =>
      provided ?? await DBService.database;

  static Future<String> _actor(String permission) async {
    final user = await AuthorizationGuard.require(permission);
    return user?.id ?? await CurrentUserContext.userId() ?? 'SYSTEM';
  }

  static Future<int> closePeriod({
    required DateTime start,
    required DateTime end,
    String? note,
    Database? database,
  }) async {
    final actor = await _actor(PermissionKeys.periodClose);
    final db = await _database(database);
    await AccountingPeriodGuard.ensureSchemaOn(db);
    await AccountingIntegrityService.assertHealthyOn(db);

    final startUtc = AccountingPeriodGuard.localDayStartUtc(start);
    final endExclusiveUtc = AccountingPeriodGuard.localDayAfterUtc(end);
    if (!endExclusiveUtc.isAfter(startUtc)) {
      throw ArgumentError('Accounting period end must be on/after start.');
    }

    return db.transaction((tx) async {
      await AccountingPeriodGuard.ensureSchemaOn(tx);
      final overlap = await tx.rawQuery(
        '''
        SELECT id, period_start_utc, period_end_exclusive_utc, status
        FROM ${AccountingPeriodGuard.closesTable}
        WHERE status='CLOSED'
          AND NOT (? <= period_start_utc OR ? >= period_end_exclusive_utc)
        LIMIT 1
        ''',
        [
          endExclusiveUtc.toIso8601String(),
          startUtc.toIso8601String(),
        ],
      );
      if (overlap.isNotEmpty) {
        final row = overlap.single;
        final same = row['period_start_utc'] == startUtc.toIso8601String() &&
            row['period_end_exclusive_utc'] ==
                endExclusiveUtc.toIso8601String();
        if (same) return (row['id'] as num).toInt();
        throw StateError('ACCOUNTING_PERIOD_OVERLAP:${row['id']}');
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final id = await tx.insert(
        AccountingPeriodGuard.closesTable,
        {
          'period_start_utc': startUtc.toIso8601String(),
          'period_end_exclusive_utc': endExclusiveUtc.toIso8601String(),
          'status': 'CLOSED',
          'closed_at': now,
          'closed_by': actor,
          'reopened_at': null,
          'reopened_by': null,
          'note': note?.trim(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await tx.insert(
        AccountingPeriodGuard.eventsTable,
        {
          'close_id': id,
          'action': 'CLOSE',
          'actor_id': actor,
          'reason': note?.trim(),
          'created_at': now,
        },
      );
      return id;
    });
  }

  static Future<void> reopenPeriod(
    int closeId, {
    required String reason,
    Database? database,
  }) async {
    if (closeId <= 0) throw ArgumentError.value(closeId, 'closeId');
    if (reason.trim().isEmpty) {
      throw ArgumentError('Reopen reason is required.');
    }
    final actor = await _actor(PermissionKeys.periodReopen);
    final db = await _database(database);
    await AccountingPeriodGuard.ensureSchemaOn(db);

    await db.transaction((tx) async {
      final rows = await tx.query(
        AccountingPeriodGuard.closesTable,
        where: 'id=?',
        whereArgs: [closeId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('ACCOUNTING_PERIOD_NOT_FOUND');
      if (rows.single['status'] == 'OPEN') return;

      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        AccountingPeriodGuard.closesTable,
        {
          'status': 'OPEN',
          'reopened_at': now,
          'reopened_by': actor,
        },
        where: 'id=?',
        whereArgs: [closeId],
      );
      await tx.insert(
        AccountingPeriodGuard.eventsTable,
        {
          'close_id': closeId,
          'action': 'REOPEN',
          'actor_id': actor,
          'reason': reason.trim(),
          'created_at': now,
        },
      );
    });
  }

  static Future<bool> isClosed(
    DateTime date, {
    Database? database,
  }) async {
    final db = await _database(database);
    return AccountingPeriodGuard.isClosedOn(db, date);
  }

  static Future<List<Map<String, Object?>>> periods({
    Database? database,
  }) async {
    final db = await _database(database);
    await AccountingPeriodGuard.ensureSchemaOn(db);
    return db.query(
      AccountingPeriodGuard.closesTable,
      orderBy: 'period_start_utc DESC, id DESC',
    );
  }

  static Future<List<Map<String, Object?>>> events(
    int closeId, {
    Database? database,
  }) async {
    final db = await _database(database);
    await AccountingPeriodGuard.ensureSchemaOn(db);
    return db.query(
      AccountingPeriodGuard.eventsTable,
      where: 'close_id=?',
      whereArgs: [closeId],
      orderBy: 'id ASC',
    );
  }
}
