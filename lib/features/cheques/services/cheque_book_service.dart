import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class ChequeBookService {
  ChequeBookService._();

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
      columns: const ['id'],
      where: 'id=?',
      whereArgs: [bankAccountId],
      limit: 1,
    );
    if (accountRows.isEmpty) {
      throw StateError('Cheque book bank account does not exist.');
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
