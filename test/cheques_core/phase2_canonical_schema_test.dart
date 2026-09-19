import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cheques_core_v78_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<int> insertReceived({
    required String number,
    required String instrumentKey,
    String sourceId = 'RC-1',
    double amount = 1000,
  }) {
    final now = DateTime(2026, 9, 19).toIso8601String();
    return db.insert('cheques', {
      'uuid': 'uuid-$instrumentKey',
      'cheque_no': number,
      'cheque_type': 'incoming',
      'direction': 'RECEIVED',
      'status': 'received',
      'instrument_key': instrumentKey,
      'drawer_name': 'Drawer',
      'bank_name': 'Bank',
      'bank_branch': 'Branch',
      'amount': amount,
      'currency': 'ILS',
      'issue_date': now,
      'due_date': now,
      'source_type': 'RECEIPT',
      'source_id': sourceId,
      'recipient_type': 'WORKSHOP',
      'recipient_name': 'Workshop',
      'is_legacy_incomplete': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('PHASE2 current DB version and canonical cheque tables exist', () async {
    expect(DatabaseConstants.dbVersion, 78);
    final version = await db.rawQuery('PRAGMA user_version');
    expect((version.single.values.first as num).toInt(), 78);

    final names = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
        .map((r) => r['name'])
        .toSet();

    for (final table in const [
      'cheques',
      'cheque_events',
      'cheque_voucher_links',
      'cheque_allocations',
      'cheque_books',
      'cheque_deposit_batches',
      'cheque_deposit_items',
      'cheque_endorsements',
    ]) {
      expect(names, contains(table), reason: table);
    }

    final chequeCols =
        (await db.rawQuery('PRAGMA table_info(cheques)')).map((r) => r['name']);
    for (final col in const [
      'direction',
      'instrument_key',
      'receipt_voucher_id',
      'payment_voucher_id',
      'source_party_type',
      'source_party_id',
      'bank_account_id',
      'cheque_book_id',
      'created_by',
      'deposited_at',
      'collection_date',
      'delivered_at',
      'presented_at',
      'cleared_at',
      'returned_at',
      'cancelled_at',
      'cancelled_by',
      'cancellation_reason',
    ]) {
      expect(chequeCols, contains(col), reason: col);
    }
  });

  test('PHASE2 material constraints reject invalid cheque rows', () async {
    final now = DateTime(2026, 9, 19).toIso8601String();

    await expectLater(
      db.insert('cheques', {
        'uuid': 'bad-amount',
        'cheque_no': '1',
        'cheque_type': 'incoming',
        'direction': 'RECEIVED',
        'status': 'received',
        'instrument_key': 'bad-amount',
        'drawer_name': 'Drawer',
        'bank_name': 'Bank',
        'amount': 0,
        'currency': 'ILS',
        'issue_date': now,
        'due_date': now,
        'is_legacy_incomplete': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.insert('cheques', {
        'uuid': 'bad-drawer',
        'cheque_no': '2',
        'cheque_type': 'incoming',
        'direction': 'RECEIVED',
        'status': 'received',
        'instrument_key': 'bad-drawer',
        'drawer_name': '',
        'bank_name': 'Bank',
        'amount': 10,
        'currency': 'ILS',
        'issue_date': now,
        'due_date': now,
        'is_legacy_incomplete': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.insert('cheques', {
        'uuid': 'bad-issued',
        'cheque_no': '3',
        'cheque_type': 'outgoing',
        'direction': 'ISSUED',
        'status': 'issued',
        'instrument_key': 'bad-issued',
        'drawer_name': 'Workshop',
        'recipient_name': 'Supplier',
        'bank_name': 'Bank',
        'amount': 10,
        'currency': 'ILS',
        'issue_date': now,
        'due_date': now,
        'is_legacy_incomplete': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
      'PHASE2 multiple cheques can share voucher with distinct instrument keys',
      () async {
    await db.insert('receipt_headers', {
      'receipt_number': 1,
      'client_id': 1,
      'date': '2026-09-19',
      'method': 'mixed',
      'total_amount': 1500.0,
      'allocated_amount': 1500.0,
      'credit_amount': 0.0,
      'status': 'posted',
      'created_at': DateTime.now().toIso8601String(),
    });

    final first = await insertReceived(
      number: 'RCV-100',
      instrumentKey: 'cheque-a',
    );
    final second = await insertReceived(
      number: 'RCV-101',
      instrumentKey: 'cheque-b',
      amount: 500,
    );

    await db.insert('cheque_voucher_links', {
      'cheque_id': first,
      'voucher_type': 'RECEIPT',
      'voucher_id': '1',
      'instrument_key': 'cheque-a',
      'amount': 1000.0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('cheque_voucher_links', {
      'cheque_id': second,
      'voucher_type': 'RECEIPT',
      'voucher_id': '1',
      'instrument_key': 'cheque-b',
      'amount': 500.0,
      'created_at': DateTime.now().toIso8601String(),
    });

    expect(
      await db.query(
        'cheque_voucher_links',
        where: 'voucher_type=? AND voucher_id=?',
        whereArgs: ['RECEIPT', '1'],
      ),
      hasLength(2),
    );

    await expectLater(
      insertReceived(
        number: 'RCV-102',
        instrumentKey: 'cheque-a',
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('PHASE2 allocation total cannot exceed cheque amount', () async {
    await db.insert('receipt_headers', {
      'receipt_number': 1,
      'client_id': 1,
      'date': '2026-09-19',
      'method': 'cheque',
      'total_amount': 1000.0,
      'allocated_amount': 1000.0,
      'credit_amount': 0.0,
      'status': 'posted',
      'created_at': DateTime.now().toIso8601String(),
    });
    final chequeId =
        await insertReceived(number: 'ALLOC-1', instrumentKey: 'alloc');

    Future<int> allocation(String target, double amount) {
      return db.insert('cheque_allocations', {
        'cheque_id': chequeId,
        'voucher_type': 'RECEIPT',
        'voucher_id': '1',
        'allocation_type': 'REPAIR',
        'target_id': target,
        'amount': amount,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    await allocation('R-A', 600);
    await allocation('R-B', 400);
    await expectLater(
      allocation('R-C', 1),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('PHASE2 cheque book number is never reusable', () async {
    final bankId = (await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code=?',
      whereArgs: const ['1010'],
      limit: 1,
    ))
        .single['id'] as int;

    final now = DateTime.now().toIso8601String();
    await db.insert('cheque_books', {
      'id': 'BOOK-1',
      'bank_account_id': bankId,
      'book_number': 'B-1',
      'first_cheque_number': 100,
      'last_cheque_number': 110,
      'next_available_number': 100,
      'status': 'OPEN',
      'created_at': now,
      'updated_at': now,
    });

    Future<int> issued(String uuid) => db.insert('cheques', {
          'uuid': uuid,
          'cheque_no': '100',
          'cheque_type': 'outgoing',
          'direction': 'ISSUED',
          'status': uuid == 'one' ? 'issued' : 'cancelled',
          'instrument_key': uuid,
          'drawer_name': 'Workshop',
          'recipient_name': 'Supplier',
          'bank_name': 'Bank',
          'amount': 100.0,
          'currency': 'ILS',
          'issue_date': now,
          'due_date': now,
          'bank_account_id': bankId,
          'cheque_book_id': 'BOOK-1',
          'is_legacy_incomplete': 0,
          'created_at': now,
          'updated_at': now,
        });

    await issued('one');
    await expectLater(issued('two'), throwsA(isA<DatabaseException>()));
  });

  test('PHASE2 voucher direction and amount must match cheque', () async {
    await db.insert('receipt_headers', {
      'receipt_number': 1,
      'client_id': 1,
      'date': '2026-09-19',
      'method': 'cheque',
      'total_amount': 1000.0,
      'allocated_amount': 1000.0,
      'credit_amount': 0.0,
      'status': 'posted',
      'created_at': DateTime.now().toIso8601String(),
    });
    final chequeId =
        await insertReceived(number: 'LINK-1', instrumentKey: 'link');

    await expectLater(
      db.insert('cheque_voucher_links', {
        'cheque_id': chequeId,
        'voucher_type': 'PAYMENT',
        'voucher_id': 'missing-payment-voucher',
        'instrument_key': 'link',
        'amount': 1000.0,
        'created_at': DateTime.now().toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.insert('cheque_voucher_links', {
        'cheque_id': chequeId,
        'voucher_type': 'RECEIPT',
        'voucher_id': '1',
        'instrument_key': 'link',
        'amount': 999.0,
        'created_at': DateTime.now().toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
