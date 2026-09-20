import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';

class ChequeBookService {
  ChequeBookService._();

  static Future<List<Map<String, Object?>>> list({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery('''
      SELECT b.*, a.code AS bank_account_code, a.name AS bank_account_name,
        (SELECT COUNT(*) FROM cheques c
         WHERE c.cheque_book_id=b.id) AS used_count
      FROM cheque_books b
      JOIN accounts a ON a.id=b.bank_account_id
      ORDER BY datetime(b.created_at) DESC, b.book_number
    ''');
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  static Future<String> create({
    required int bankAccountId,
    required String bookNumber,
    required int firstChequeNumber,
    required int lastChequeNumber,
  }) async {
    final actor =
        await AuthorizationGuard.require(PermissionKeys.chequeBookManage);
    final db = await DBService.database;
    return SyncFoundationService.transaction<String>(db, (txn) async {
      final id = await createOnTxn(
        txn: txn,
        bankAccountId: bankAccountId,
        bookNumber: bookNumber,
        firstChequeNumber: firstChequeNumber,
        lastChequeNumber: lastChequeNumber,
        createdBy: actor?.id,
      );
      await AuditTrailService.log(
        executor: txn,
        actorUserId: actor?.id,
        actorRole: actor?.role,
        action: 'CHEQUE_BOOK_CREATED',
        entityType: 'cheque_book',
        entityId: id,
        after: {
          'bank_account_id': bankAccountId,
          'book_number': bookNumber,
          'first_cheque_number': firstChequeNumber,
          'last_cheque_number': lastChequeNumber,
        },
      );
      return id;
    });
  }

  static Future<void> close(String bookId) async {
    final actor =
        await AuthorizationGuard.require(PermissionKeys.chequeBookManage);
    final db = await DBService.database;
    await SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.query(
        'cheque_books',
        where: 'id=?',
        whereArgs: [bookId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Cheque book not found.');
      if ((rows.single['status'] ?? '').toString().toUpperCase() == 'CLOSED') {
        return;
      }
      await txn.update(
        'cheque_books',
        {
          'status': 'CLOSED',
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [bookId],
      );
      await AuditTrailService.log(
        executor: txn,
        actorUserId: actor?.id,
        actorRole: actor?.role,
        action: 'CHEQUE_BOOK_CLOSED',
        entityType: 'cheque_book',
        entityId: bookId,
        before: rows.single,
        after: {
          ...rows.single,
          'status': 'CLOSED',
        },
      );
    });
  }

  static Future<String> createOnTxn({
    required Transaction txn,
    required int bankAccountId,
    required String bookNumber,
    required int firstChequeNumber,
    required int lastChequeNumber,
    String? createdBy,
  }) async {
    if (bankAccountId <= 0) {
      throw StateError('Cheque book requires a bank account.');
    }
    if (bookNumber.trim().isEmpty) {
      throw StateError('Cheque book number is required.');
    }
    if (firstChequeNumber <= 0 || lastChequeNumber < firstChequeNumber) {
      throw StateError('Cheque book number range is invalid.');
    }

    final accountRows = await txn.query(
      'accounts',
      columns: const ['id', 'code', 'type'],
      where: 'id=?',
      whereArgs: [bankAccountId],
      limit: 1,
    );
    if (accountRows.isEmpty) {
      throw StateError('Cheque book bank account does not exist.');
    }
    final code = (accountRows.single['code'] ?? '').toString();
    if (!(code == '1010' || code.startsWith('1010.'))) {
      throw StateError('Cheque book requires a bank account code.');
    }

    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await txn.insert(
      'cheque_books',
      {
        'id': id,
        'bank_account_id': bankAccountId,
        'book_number': bookNumber.trim(),
        'first_cheque_number': firstChequeNumber,
        'last_cheque_number': lastChequeNumber,
        'next_available_number': firstChequeNumber,
        'status': 'OPEN',
        'created_by': createdBy,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return id;
  }

  static Future<int> nextAvailableNumber(
    DatabaseExecutor db,
    String bookId,
  ) async {
    final rows = await db.query(
      'cheque_books',
      where: 'id=?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Cheque book not found.');
    final row = rows.first;
    final status = (row['status'] ?? '').toString().toUpperCase();
    if (status != 'OPEN') {
      throw StateError('Cheque book is not open.');
    }
    final first = (row['first_cheque_number'] as num).toInt();
    final last = (row['last_cheque_number'] as num).toInt();
    var candidate = (row['next_available_number'] as num).toInt();
    if (candidate < first) candidate = first;

    while (candidate <= last) {
      final used = await db.query(
        'cheques',
        columns: const ['id'],
        where: 'cheque_book_id=? AND cheque_no=?',
        whereArgs: [bookId, candidate.toString()],
        limit: 1,
      );
      if (used.isEmpty) return candidate;
      candidate++;
    }
    throw StateError('Cheque book is exhausted.');
  }

  static Future<int> reserveNumberOnTxn({
    required Transaction txn,
    required String bookId,
    int? requestedNumber,
    bool allowOverride = false,
  }) async {
    final rows = await txn.query(
      'cheque_books',
      where: 'id=?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Cheque book not found.');
    final row = rows.first;
    final status = (row['status'] ?? '').toString().toUpperCase();
    if (status != 'OPEN') throw StateError('Cheque book is not open.');

    final first = (row['first_cheque_number'] as num).toInt();
    final last = (row['last_cheque_number'] as num).toInt();
    final next = await nextAvailableNumber(txn, bookId);
    final number = requestedNumber ?? next;

    if (number < first || number > last) {
      throw StateError('Cheque number is outside the cheque book range.');
    }
    if (!allowOverride && number != next) {
      throw StateError(
        'Cheque number must match the next available number.',
      );
    }

    final used = await txn.query(
      'cheques',
      columns: const ['id', 'status'],
      where: 'cheque_book_id=? AND cheque_no=?',
      whereArgs: [bookId, number.toString()],
      limit: 1,
    );
    if (used.isNotEmpty) {
      throw StateError(
        'Cheque number was already used and cannot be reused.',
      );
    }

    var newNext = (row['next_available_number'] as num).toInt();
    if (number == next) {
      newNext = number + 1;
    }
    final exhausted = newNext > last;
    await txn.update(
      'cheque_books',
      {
        'next_available_number': newNext,
        'status': exhausted ? 'EXHAUSTED' : 'OPEN',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [bookId],
    );
    return number;
  }
}
