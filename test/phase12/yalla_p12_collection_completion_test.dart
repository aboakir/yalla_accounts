import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/features/account_statements/customers/services/customer_account_statement_service.dart';
import 'package:yalla_accounts/features/finance/services/collection_service.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE clients(id INTEGER PRIMARY KEY, name TEXT, account_id INTEGER)');
    await db.execute('''
      CREATE TABLE repairs(
        id TEXT PRIMARY KEY,
        client_id INTEGER,
        beneficiaryName TEXT,
        vehicleType TEXT,
        vehicleModel TEXT,
        vehicleNumber TEXT,
        receivedDate TEXT
      )
    ''');
    await db
        .execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY, code TEXT)');
    await db.execute('''
      CREATE TABLE gl_entries(
        id INTEGER PRIMARY KEY,
        date TEXT,
        source TEXT,
        source_id TEXT,
        source_number TEXT,
        note TEXT,
        reversal_of INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE gl_lines(
        id INTEGER PRIMARY KEY,
        entry_id INTEGER,
        account_id INTEGER,
        debit REAL,
        credit REAL,
        party_type TEXT,
        party_id TEXT,
        repair_id TEXT,
        invoice_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE cheques(
        id INTEGER PRIMARY KEY,
        cheque_no TEXT,
        number TEXT,
        due_date TEXT,
        status TEXT,
        updated_at TEXT
      )
    ''');

    await db.insert('clients', {'id': 1, 'name': 'Client A', 'account_id': 10});
    await db.insert('repairs', {
      'id': 'R1',
      'client_id': 1,
      'beneficiaryName': 'Client A',
      'vehicleType': 'Toyota',
      'vehicleModel': 'Corolla',
      'vehicleNumber': '1-2345',
      'receivedDate': '2026-01-01T00:00:00.000',
    });
    await db.insert('accounts', {'id': 10, 'code': '1200.C1'});
    await db.insert('gl_entries', {
      'id': 1,
      'date': '2026-01-10T00:00:00.000',
      'source': 'INVOICE',
      'source_id': 'I1',
      'source_number': 'INV-1',
    });
    await db.insert('gl_lines', {
      'id': 1,
      'entry_id': 1,
      'account_id': 10,
      'debit': 1000.0,
      'credit': 0.0,
      'party_type': 'CLIENT',
      'party_id': '1',
      'repair_id': 'R1',
      'invoice_id': 'I1',
    });
  });

  tearDown(() async => db.close());

  test('P12 due date is dedicated, persisted and editable', () async {
    final generated =
        await CollectionService.ensureRepairDueDate('R1', executor: db);
    expect(generated, DateTime(2026, 2, 9));

    final manual = DateTime(2026, 3, 15);
    await CollectionService.setRepairDueDate('R1', manual, executor: db);
    final reread =
        await CollectionService.ensureRepairDueDate('R1', executor: db);
    expect(reread, manual);

    final row = (await db.query('collection_due_dates')).single;
    expect(row['source'], 'manual');
  });

  test('P12 collection amount is GL AR, not invoice-minus-payments', () async {
    final items = await CollectionService.loadOpenDues(executor: db);
    expect(items, hasLength(1));
    expect(items.single.amount, 1000.0);

    await db.insert('gl_entries', {
      'id': 2,
      'date': '2026-01-20T00:00:00.000',
      'source': 'RECEIPT',
      'source_id': 'P1',
      'source_number': 'RC-000001',
    });
    await db.insert('gl_lines', {
      'id': 2,
      'entry_id': 2,
      'account_id': 10,
      'debit': 0.0,
      'credit': 400.0,
      'party_type': 'CLIENT',
      'party_id': '1',
      'repair_id': 'R1',
    });

    final after = await CollectionService.loadOpenDues(executor: db);
    expect(after.single.amount, 600.0);
  });

  test('P12 customer statement has running GL balance', () async {
    await db.insert('gl_entries', {
      'id': 2,
      'date': '2026-01-20T00:00:00.000',
      'source': 'RECEIPT',
      'source_id': 'P1',
      'source_number': 'RC-000001',
    });
    await db.insert('gl_lines', {
      'id': 2,
      'entry_id': 2,
      'account_id': 10,
      'debit': 0.0,
      'credit': 400.0,
      'party_type': 'CLIENT',
      'party_id': '1',
      'repair_id': 'R1',
    });

    final statement =
        await CustomerAccountStatementService.load(clientId: 1, executor: db);
    expect(statement.lines, hasLength(2));
    expect(statement.lines.first.balance, 1000.0);
    expect(statement.lines.last.balance, 600.0);
    expect(statement.closingBalance, 600.0);
  });

  test('P12 alerts use due dates and canonical cheque lifecycle', () async {
    await CollectionService.setRepairDueDate(
      'R1',
      DateTime.now().subtract(const Duration(days: 2)),
      executor: db,
    );
    await db.insert('cheques', {
      'id': 1,
      'cheque_no': 'C1',
      'due_date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      'status': 'pending',
    });
    await db.insert('cheques', {
      'id': 2,
      'cheque_no': 'C2',
      'due_date': DateTime.now().toIso8601String(),
      'status': 'returned',
    });

    final alerts = await CollectionService.loadAlerts(executor: db);
    expect(
        alerts.any((a) => a.id == 'ar:R1' && a.severity == 'critical'), isTrue);
    expect(alerts.any((a) => a.id == 'cheque:1'), isTrue);
    expect(alerts.any((a) => a.id == 'returned:2' && a.severity == 'critical'),
        isTrue);
  });

  test('P12 source contracts remove legacy AR/postdated shortcuts', () async {
    final postdated =
        File('lib/features/cheques/screens/cheques_postdated_screen.dart')
            .readAsStringSync();
    final collection =
        File('lib/features/cheques/screens/cheques_collection_screen.dart')
            .readAsStringSync();
    final alerts = File('lib/features/home/services/alerts_service.dart')
        .readAsStringSync();
    final critical = File('lib/core/providers/critical_ops_provider.dart')
        .readAsStringSync();
    final aging =
        File('lib/features/finance/reports/screens/ar_aging_screen.dart')
            .readAsStringSync();
    final routes = File('lib/core/routes/app_routes.dart').readAsStringSync();
    final sidebar =
        File('lib/core/widgets/sidebar/yalla_sidebar.dart').readAsStringSync();

    expect(postdated.contains("status: ChequeStatus.pending"), isTrue);
    expect(postdated.contains('POSTDATED'), isFalse);
    expect(collection.contains('ChequeStatus.deposited'), isTrue);
    expect(alerts.contains('CollectionService.loadAlerts'), isTrue);
    expect(alerts.contains('accounts_receivable'), isFalse);
    expect(critical.contains('CollectionService.loadOpenDues'), isTrue);
    expect(critical.contains('receivedDate'), isFalse);
    expect(aging.contains('ARAgingPage'), isTrue);
    expect(aging.contains('FROM invoices'), isFalse);
    expect(routes.contains("collectionDashboard = '/finance/collections'"),
        isTrue);
    expect(sidebar.contains('التحصيل والذمم'), isTrue);
  });
}
