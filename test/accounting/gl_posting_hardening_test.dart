import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_integrity_tables.dart';
import 'package:yalla_accounts/core/services/accounting_integrity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        '''CREATE TABLE gl_entries(id INTEGER PRIMARY KEY, date TEXT, ref TEXT,
      source TEXT, source_id TEXT, source_number TEXT, posting_version INTEGER DEFAULT 1,
      reversal_of INTEGER, created_by TEXT, note TEXT, created_at TEXT)''');
    await db.execute(
        '''CREATE TABLE gl_lines(id INTEGER PRIMARY KEY, entry_id INTEGER,
      account_id INTEGER, debit REAL, credit REAL, party_type TEXT, party_id TEXT,
      invoice_id TEXT, repair_id TEXT, cheque_id INTEGER, created_at TEXT)''');
    await db.execute(
        'CREATE TABLE purchase_invoices(id TEXT PRIMARY KEY, amount_total REAL)');
    await db.insert('purchase_invoices', {'id': 'doc', 'amount_total': 100});
    await AccountingIntegrityTables.ensure(db);
  });
  tearDown(() async => db.close());
  Future<int> post(
          {String id = 'doc',
          String source = 'PURCHASE',
          double debit = 100,
          double credit = 100,
          String? actor = 'accountant',
          DateTime? date,
          String? note}) =>
      AccountingTables.postEntryGLOn(
          ex: db,
          date: date ?? DateTime(2026, 9, 8, 14, 30),
          source: source,
          sourceId: id,
          createdBy: actor,
          note: note,
          lines: [
            {'account_id': 1, 'debit': debit, 'credit': 0.0},
            {'account_id': 2, 'debit': 0.0, 'credit': credit},
          ]);
  test('exact currency balance and invalid money fail before writing anything',
      () async {
    for (final amounts in [
      (100.0, 99.99),
      (100.0, 99.999),
      (double.nan, 100.0),
      (double.infinity, double.infinity),
      (-100.0, -100.0),
      (0.0, 0.0)
    ]) {
      await expectLater(
          post(debit: amounts.$1, credit: amounts.$2), throwsA(anything));
      expect(await db.query('gl_entries'), isEmpty);
      expect(await db.query('gl_lines'), isEmpty);
    }
    await post(debit: 0.1 + 0.2, credit: 0.3);
  });
  test(
      'metadata is attributed and the source document and reversal remain traceable',
      () async {
    final id = await post();
    final head = (await db.query('gl_entries')).single;
    expect(head['created_by'], 'accountant');
    expect(head['ref'], 'PURCHASE:doc');
    expect((head['note'] as String).isNotEmpty, isTrue);
    expect(DateTime.tryParse('${head['created_at']}'), isNotNull);
    expect(head['date'], '2026-09-08T14:30:00.000');
    final trace = await AccountingIntegrityService.traceSourceOn(db,
        source: 'PURCHASE', sourceId: 'doc');
    expect((trace['source_document'] as Map)['id'], 'doc');
    expect(
        (trace['audit_events'] as List).single['actor_user_id'], 'accountant');
    expect(await post(source: 'PURCHASE_INVOICE'), id);
    final reversedId = await AccountingTables.reverseEntryGLOn(db, id,
        createdBy: 'accountant', note: 'Reversal test');
    final reversedTrace = await AccountingIntegrityService.traceSourceOn(db,
        source: 'PURCHASE_REV', sourceId: 'GLREV:$id');
    expect((reversedTrace['entry'] as Map)['id'], reversedId);
    expect((reversedTrace['source_document'] as Map)['id'], 'doc');
    expect((reversedTrace['original_entry'] as Map)['id'], id);

    await expectLater(post(date: DateTime(2026, 9, 9)), throwsStateError);
    await expectLater(post(note: 'Changed meaning'), throwsStateError);
    await expectLater(
        db.insert('gl_entries',
            {'source': ' purchase_invoice ', 'source_id': ' doc '}),
        throwsA(isA<DatabaseException>()));
    await expectLater(
        db.insert('gl_lines',
            {'entry_id': id, 'account_id': 1, 'debit': 1, 'credit': 0}),
        throwsA(isA<DatabaseException>()));
  });
  test(
      'missing actor and downstream audit failures cannot leave partial journals',
      () async {
    await expectLater(post(actor: null), throwsStateError);
    expect(await db.query('gl_entries'), isEmpty);
    await db.execute(
        "CREATE TRIGGER fail_audit BEFORE INSERT ON accounting_audit_events BEGIN SELECT RAISE(ABORT,'TEST_FAILURE'); END;");
    await expectLater(post(), throwsA(isA<DatabaseException>()));
    expect(await db.query('gl_entries'), isEmpty);
    expect(await db.query('gl_lines'), isEmpty);
    await db.transaction((txn) async {
      await expectLater(
          AccountingTables.postEntryGLOn(
              ex: txn,
              date: DateTime(2026, 9, 8),
              source: 'PURCHASE',
              sourceId: 'caught',
              createdBy: 'accountant',
              lines: [
                {'account_id': 1, 'debit': 10, 'credit': 0},
                {'account_id': 2, 'debit': 0, 'credit': 10}
              ]),
          throwsA(isA<DatabaseException>()));
      // The caller catches the failure and commits its outer transaction.
    });
    expect(await db.query('gl_entries'), isEmpty);
    expect(await db.query('gl_lines'), isEmpty);
  });
  test('database prevents sealing an unbalanced entry', () async {
    final id =
        await db.insert('gl_entries', {'source': 'RAW', 'source_id': 'raw'});
    await db.insert('gl_lines',
        {'entry_id': id, 'account_id': 1, 'debit': 100, 'credit': 0});
    await db.insert('gl_lines',
        {'entry_id': id, 'account_id': 2, 'debit': 0, 'credit': 99.99});
    await expectLater(
        db.insert('accounting_audit_events', {
          'gl_entry_id': id,
          'event_type': 'POST',
          'source': 'RAW',
          'source_id': 'raw',
          'canonical_source': 'RAW',
          'created_at': DateTime.now().toIso8601String()
        }),
        throwsA(isA<DatabaseException>()));
  });
}
