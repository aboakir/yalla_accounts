// -----------------------------------------------------------------------------
// lib/features/cheques/services/cheque_service.dart
// P0.008 — safe cheque register + canonical lifecycle gateway
// -----------------------------------------------------------------------------

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/cheque_tables.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';

import 'cheque_accounting_service.dart';

class ChequeService {
  static const _table = 'cheques';

  Future<int> addCheque(Cheque cheque) async {
    final db = await DBService.database;

    if (cheque.chequeType == ChequeType.collection) {
      throw StateError(
        'Collection is a lifecycle status, not a new cheque direction.',
      );
    }
    if ((cheque.sourceType ?? '').trim().isNotEmpty ||
        (cheque.sourceId ?? '').trim().isNotEmpty ||
        cheque.glEntryId != null) {
      throw StateError(
        'Accounting-linked cheques must be created by the voucher/payment flow.',
      );
    }
    if (cheque.amount <= 0 ||
        cheque.chequeNo.trim().isEmpty ||
        cheque.drawerName.trim().isEmpty ||
        cheque.bankName.trim().isEmpty) {
      throw StateError('Cheque number, drawer, bank and amount are required.');
    }

    await ChequeTables.ensureChequesSchema(db);

    return db.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();

      final id = await txn.insert(
        _table,
        {
          ...cheque.toMap(),
          'id': null,
          'status': ChequeStatus.pending.name,
          'source_type': null,
          'source_id': null,
          'gl_entry_id': null,
          'is_legacy_incomplete': 0,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await txn.insert(
        'cheque_events',
        {
          'cheque_id': id,
          'event_type': 'registered_manual',
          'from_status': null,
          'to_status': ChequeStatus.pending.name,
          'event_date': now,
          'gl_entry_id': null,
          'note': 'Operational cheque register entry',
          'created_at': now,
        },
      );

      return id;
    });
  }

  Future<void> updateCheque(Cheque updated) async {
    if (updated.id == null) throw StateError('Cheque id is required.');

    final db = await DBService.database;
    await ChequeTables.ensureChequesSchema(db);

    await db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        where: 'id=?',
        whereArgs: [updated.id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Cheque not found.');

      final old = Cheque.fromMap(rows.first);

      final lifecycleCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              "SELECT COUNT(*) FROM cheque_events "
              "WHERE cheque_id=? AND "
              "(event_type LIKE 'status:%' OR event_type='endorsed')",
              [updated.id],
            ),
          ) ??
          0;

      final linked = old.glEntryId != null ||
          (old.sourceType ?? '').trim().isNotEmpty ||
          (old.sourceId ?? '').trim().isNotEmpty ||
          lifecycleCount > 0;

      if (linked && old.isLegacyIncomplete != 1) {
        throw StateError(
          'An accounted/linked cheque is immutable. '
          'Use cheque lifecycle actions instead of editing it.',
        );
      }

      if (old.isLegacyIncomplete == 1) {
        if (updated.chequeNo.trim().isEmpty ||
            updated.drawerName.trim().isEmpty ||
            updated.bankName.trim().isEmpty) {
          throw StateError(
            'Complete cheque number, drawer and bank before saving.',
          );
        }

        // One-time metadata completion only. Material/accounting fields stay
        // exactly as recovered from the historical voucher.
        final sameAmount = (old.amount - updated.amount).abs() <= 0.01;
        if (!sameAmount ||
            old.chequeType != updated.chequeType ||
            old.status != updated.status ||
            old.sourceType != updated.sourceType ||
            old.sourceId != updated.sourceId ||
            old.supplierPid != updated.supplierPid ||
            old.clientId != updated.clientId) {
          throw StateError(
            'Recovered cheque accounting fields cannot be changed.',
          );
        }

        await txn.update(
          _table,
          {
            'cheque_no': updated.chequeNo.trim(),
            'number': updated.chequeNo.trim(),
            'drawer_name': updated.drawerName.trim(),
            'bank_name': updated.bankName.trim(),
            'bank': updated.bankName.trim(),
            'bank_branch': updated.bankBranch.trim(),
            'issue_date': updated.issueDate.toIso8601String(),
            'date': updated.issueDate.toIso8601String(),
            'due_date': updated.dueDate.toIso8601String(),
            'notes': updated.notes,
            'is_legacy_incomplete': 0,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [updated.id],
        );

        await txn.insert(
          'cheque_events',
          {
            'cheque_id': updated.id,
            'event_type': 'legacy_metadata_completed',
            'from_status': old.status.name,
            'to_status': old.status.name,
            'event_date': DateTime.now().toIso8601String(),
            'gl_entry_id': null,
            'note': 'Historical missing cheque metadata completed',
            'created_at': DateTime.now().toIso8601String(),
          },
        );
        return;
      }

      final data = updated.toMap()
        ..remove('id')
        ..remove('status')
        ..remove('source_type')
        ..remove('source_id')
        ..remove('gl_entry_id')
        ..remove('is_legacy_incomplete')
        ..remove('created_at');

      data['updated_at'] = DateTime.now().toIso8601String();

      await txn.update(
        _table,
        data,
        where: 'id=?',
        whereArgs: [updated.id],
      );
    });
  }

  Future<void> deleteCheque(int chequeId) async {
    final db = await DBService.database;
    await ChequeTables.ensureChequesSchema(db);

    await db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        where: 'id=?',
        whereArgs: [chequeId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final cheque = Cheque.fromMap(rows.first);

      final eventCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM cheque_events WHERE cheque_id=?',
              [chequeId],
            ),
          ) ??
          0;

      final linked = cheque.glEntryId != null ||
          (cheque.sourceType ?? '').trim().isNotEmpty ||
          (cheque.sourceId ?? '').trim().isNotEmpty ||
          eventCount > 1;

      if (linked) {
        throw StateError(
          'Cannot delete a linked/accounted cheque. '
          'Use return/cancel lifecycle actions.',
        );
      }

      await txn.delete(
        'cheque_events',
        where: 'cheque_id=?',
        whereArgs: [chequeId],
      );
      await txn.delete(
        _table,
        where: 'id=?',
        whereArgs: [chequeId],
      );
    });
  }

  Future<Cheque> endorseCheque({
    required int chequeId,
    required String supplierPid,
    required DateTime endorsementDate,
  }) {
    return ChequeAccountingService.endorseToSupplier(
      chequeId: chequeId,
      supplierPid: supplierPid,
      endorsementDate: endorsementDate,
    );
  }

  Future<Cheque> transitionStatus({
    required int chequeId,
    required ChequeStatus status,
    String? reason,
    DateTime? eventDate,
  }) {
    return ChequeAccountingService.transitionStatus(
      chequeId: chequeId,
      newStatus: status,
      reason: reason,
      eventDate: eventDate,
    );
  }

  Future<Cheque?> getById(int id) async {
    final db = await DBService.database;
    await ChequeTables.ensureChequesSchema(db);

    final rows = await db.query(
      _table,
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Cheque.fromMap(rows.first);
  }

  Future<List<Cheque>> fetchFiltered({
    String? search,
    ChequeStatus? status,
    ChequeType? type,
    DateTime? issueFrom,
    DateTime? issueTo,
    DateTime? dueFrom,
    DateTime? dueTo,
  }) async {
    final db = await DBService.database;
    await ChequeTables.ensureChequesSchema(db);

    final where = <String>[];
    final args = <Object?>[];

    if (search != null && search.trim().isNotEmpty) {
      where.add(
        '(cheque_no LIKE ? OR drawer_name LIKE ? OR bank_name LIKE ?)',
      );
      args.add('%$search%');
      args.add('%$search%');
      args.add('%$search%');
    }

    if (status != null) {
      where.add('status=?');
      args.add(status.name);
    }

    if (type != null) {
      where.add('cheque_type=?');
      args.add(type.name);
    }

    final f = DateFormat('yyyy-MM-dd');

    if (issueFrom != null) {
      where.add('DATE(issue_date) >= DATE(?)');
      args.add(f.format(issueFrom));
    }
    if (issueTo != null) {
      where.add('DATE(issue_date) <= DATE(?)');
      args.add(f.format(issueTo));
    }
    if (dueFrom != null) {
      where.add('DATE(due_date) >= DATE(?)');
      args.add(f.format(dueFrom));
    }
    if (dueTo != null) {
      where.add('DATE(due_date) <= DATE(?)');
      args.add(f.format(dueTo));
    }

    final rows = await db.query(
      _table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'due_date ASC, issue_date ASC',
    );

    return rows.map(Cheque.fromMap).toList();
  }
}
