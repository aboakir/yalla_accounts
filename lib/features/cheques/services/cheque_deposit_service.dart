import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/cheque_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';

class ChequeDepositService {
  ChequeDepositService._();

  static Future<String> depositBatch({
    String? batchId,
    required int bankAccountId,
    required List<int> chequeIds,
    required DateTime depositDate,
    String? notes,
    Database? database,
  }) async {
    final actor =
        await AuthorizationGuard.require(PermissionKeys.chequeDeposit);
    final actorId = actor?.id ?? AuthSessionService.authenticatedUserId;
    if (bankAccountId <= 0) {
      throw StateError('Deposit requires a bank account.');
    }
    final ids = chequeIds.toSet().toList();
    if (ids.isEmpty || ids.length != chequeIds.length) {
      throw StateError('Deposit batch requires unique cheque ids.');
    }

    final db = database ?? await DBService.database;
    final id = (batchId ?? const Uuid().v4()).trim();
    if (id.isEmpty) throw StateError('Deposit batch id is required.');

    return SyncFoundationService.transaction<String>(db, (txn) async {
      await ChequeTables.ensureChequesSchema(txn);
      await _assertBankAccount(txn, bankAccountId);

      final prior = await txn.query(
        'cheque_deposit_batches',
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (prior.isNotEmpty) {
        final items = await txn.query(
          'cheque_deposit_items',
          columns: const ['cheque_id'],
          where: 'batch_id=?',
          whereArgs: [id],
        );
        final priorIds =
            items.map((row) => (row['cheque_id'] as num).toInt()).toSet();
        final same =
            (prior.single['bank_account_id'] as num).toInt() == bankAccountId &&
                priorIds.length == ids.length &&
                priorIds.containsAll(ids);
        if (!same) {
          throw StateError('Deposit retry differs from original batch.');
        }
        return id;
      }

      var total = 0.0;
      final rows = <Map<String, Object?>>[];
      for (final chequeId in ids) {
        final result = await txn.query(
          'cheques',
          where: 'id=?',
          whereArgs: [chequeId],
          limit: 1,
        );
        if (result.isEmpty) {
          throw StateError('Cheque $chequeId not found.');
        }
        final cheque = Cheque.fromMap(result.single);
        if (cheque.direction != ChequeDirection.received) {
          throw StateError('Only received cheques can be deposited.');
        }
        if (!const {
          ChequeStatus.received,
          ChequeStatus.held,
        }.contains(cheque.status)) {
          throw StateError('Cheque $chequeId is not available for deposit.');
        }
        if (cheque.isLegacyIncomplete == 1) {
          throw StateError('Complete recovered cheque metadata first.');
        }
        total += cheque.amount;
        rows.add({'id': chequeId, 'amount': cheque.amount});
      }

      final now = DateTime.now().toIso8601String();
      await txn.insert(
          'cheque_deposit_batches',
          {
            'id': id,
            'bank_account_id': bankAccountId,
            'deposit_date': depositDate.toIso8601String(),
            'status': 'DEPOSITED',
            'cheque_count': rows.length,
            'total_value': total,
            'notes': notes,
            'created_by': actorId,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      for (final row in rows) {
        final chequeId = row['id'] as int;
        await txn.insert(
            'cheque_deposit_items',
            {
              'batch_id': id,
              'cheque_id': chequeId,
              'amount': row['amount'],
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort);
        await txn.update(
          'cheques',
          {'bank_account_id': bankAccountId, 'updated_at': now},
          where: 'id=?',
          whereArgs: [chequeId],
        );
        await ChequeAccountingService.transitionStatusOnTxn(
          txn: txn,
          chequeId: chequeId,
          newStatus: ChequeStatus.deposited,
          eventDate: depositDate,
          actorUserId: actorId,
        );
      }

      await AuditTrailService.log(
        executor: txn,
        actorUserId: actorId,
        actorRole: actor?.role,
        action: 'CHEQUE_DEPOSIT_BATCH_CREATED',
        entityType: 'cheque_deposit_batch',
        entityId: id,
        after: {
          'bank_account_id': bankAccountId,
          'deposit_date': depositDate.toIso8601String(),
          'cheque_ids': ids,
          'cheque_count': rows.length,
          'total_value': total,
        },
      );
      return id;
    });
  }

  static Future<void> _assertBankAccount(
    DatabaseExecutor db,
    int accountId,
  ) async {
    final rows = await db.query(
      'accounts',
      columns: const ['id', 'code', 'type'],
      where: 'id=?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Bank account does not exist.');
    final code = (rows.single['code'] ?? '').toString();
    if (!(code == '1010' || code.startsWith('1010.'))) {
      throw StateError('Selected account is not a bank account.');
    }
  }
}
