import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/features/reports/providers/ar_aging_provider.dart';
import 'package:yalla_accounts/features/reports/providers/supplier_aging_provider.dart';

Future<Database> openDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE clients(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE suppliers(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE employees(
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE accounts(
      id INTEGER PRIMARY KEY,
      code TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      normal_balance TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE gl_entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      source TEXT NOT NULL,
      source_id TEXT NOT NULL,
      source_number TEXT,
      note TEXT,
      reversal_of INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE gl_lines(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL,
      debit REAL NOT NULL DEFAULT 0,
      credit REAL NOT NULL DEFAULT 0,
      party_type TEXT,
      party_id TEXT,
      invoice_id TEXT,
      repair_id TEXT,
      cheque_id TEXT,
      reference_id TEXT,
      reference_type TEXT
    )
  ''');

  final accounts = [
    [1, '1000', 'الصندوق', 'ASSET', 'DEBIT'],
    [2, '1200', 'ذمم العملاء', 'ASSET', 'DEBIT'],
    [3, '2100', 'ذمم الموردين', 'LIABILITY', 'CREDIT'],
    [4, '4000', 'الإيرادات', 'REVENUE', 'CREDIT'],
    [5, '5005', 'المشتريات', 'EXPENSE', 'DEBIT'],
  ];
  for (final a in accounts) {
    await db.insert('accounts', {
      'id': a[0],
      'code': a[1],
      'name': a[2],
      'type': a[3],
      'normal_balance': a[4],
    });
  }
  await db.insert('clients', {'id': 1, 'name': 'عميل أ', 'type': 'individual'});
  await db.insert('suppliers', {'id': 2, 'name': 'مورد ب'});
  await db.insert('employees', {'id': 'E1', 'full_name': 'عامل'});
  await PartyTables.ensure(db);
  return db;
}

Future<int> entry(Database db, String date, String source, String id) {
  return db.insert('gl_entries', {
    'date': date,
    'source': source,
    'source_id': id,
    'source_number': id,
    'note': id,
  });
}

Future<void> line(
  Database db,
  int entryId,
  int accountId,
  double debit,
  double credit, {
  String? partyType,
  String? partyId,
}) async {
  await db.insert('gl_lines', {
    'entry_id': entryId,
    'account_id': accountId,
    'debit': debit,
    'credit': credit,
    'party_type': partyType,
    'party_id': partyId,
  });
}

Future<void> seed(Database db) async {
  var e = await entry(db, '2026-06-01T10:00:00.000', 'INVOICE', 'AR-1');
  await line(db, e, 2, 1000, 0, partyType: 'client', partyId: '1');
  await line(db, e, 4, 0, 1000);

  e = await entry(
    db,
    '2026-09-23T23:59:59.999999',
    'PAYMENT',
    'AR-PAY',
  );
  await line(db, e, 1, 250, 0);
  await line(db, e, 2, 0, 250, partyType: 'CUSTOMER', partyId: '1');

  e = await entry(db, '2026-08-01T09:00:00.000', 'PURCHASE', 'AP-1');
  await line(db, e, 5, 600, 0);
  await line(db, e, 3, 0, 600, partyType: 'supplier', partyId: 'S0002');

  e = await entry(
    db,
    '2026-09-23T23:59:59.999999',
    'SUPPLIER_PAYMENT',
    'AP-PAY',
  );
  await line(db, e, 3, 100, 0, partyType: 'SUPPLIER', partyId: 'S0002');
  await line(db, e, 1, 0, 100);

  // Must be excluded by the half-open end boundary.
  e = await entry(db, '2026-09-24T00:00:00.000', 'INVOICE', 'NEXT-DAY');
  await line(db, e, 2, 999, 0, partyType: 'CUSTOMER', partyId: '1');
  await line(db, e, 4, 0, 999);
}

double number(Object? value) =>
    value is num ? value.toDouble() : double.parse(value.toString());

void main() {
  test('AR/AP aging reconcile to canonical GL through fractional day end', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seed(db);
    final asOf = DateTime(2026, 9, 23);

    final ar = await ARAgingProvider.fetch(asOf: asOf, executor: db);
    final ap = await SupplierAgingProvider.fetch(asOf: asOf, executor: db);

    expect(ar, hasLength(1));
    expect(ar.single.clientName, 'عميل أ');
    expect(ar.single.balance, 750);
    expect(ar.single.b90p, 750);

    expect(ap, hasLength(1));
    expect(ap.single.supplierId, '2');
    expect(ap.single.supplierName, 'مورد ب');
    expect(ap.single.total, 500);
    expect(ap.single.b31_60, 500);

    final gl = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN v.party_role='CUSTOMER'
          THEN v.debit-v.credit ELSE 0 END) AS ar,
        SUM(CASE WHEN v.party_role='SUPPLIER'
          THEN v.credit-v.debit ELSE 0 END) AS ap
      FROM v_party_gl_lines v
      JOIN gl_entries e ON e.id=v.entry_id
      WHERE e.date < ?
    ''', ['2026-09-24T00:00:00.000']);

    expect(ar.single.balance, number(gl.single['ar']));
    expect(ap.single.total, number(gl.single['ap']));
  });

  test('supplier aging search accepts canonical name and S-prefixed reference', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seed(db);
    final asOf = DateTime(2026, 9, 23);
    final byName = await SupplierAgingProvider.fetch(
      asOf: asOf,
      query: 'مورد ب',
      executor: db,
    );
    final byReference = await SupplierAgingProvider.fetch(
      asOf: asOf,
      query: 'S0002',
      executor: db,
    );

    expect(byName, hasLength(1));
    expect(byReference, hasLength(1));
    expect(byReference.single.total, 500);
  });
}
