import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/global_search_service.dart';

Future<Database> openSearchDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  await db.execute('''
    CREATE TABLE repairs(
      id TEXT PRIMARY KEY,
      invoiceNumber TEXT,
      vehicleModel TEXT,
      vehicleType TEXT,
      vehicleNumber TEXT,
      beneficiaryName TEXT,
      notes TEXT,
      receivedDate TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE clients(
      id INTEGER PRIMARY KEY,
      name TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      notes TEXT,
      type TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE invoices(
      id TEXT PRIMARY KEY,
      notes TEXT,
      date TEXT,
      total REAL,
      paid REAL,
      status TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE payments(
      id TEXT PRIMARY KEY,
      method TEXT,
      notes TEXT,
      accountName TEXT,
      date TEXT,
      amount REAL
    )
  ''');
  await db.execute('''
    CREATE TABLE employees(
      id TEXT PRIMARY KEY,
      full_name TEXT,
      job_title TEXT,
      phone TEXT,
      email TEXT,
      notes TEXT,
      created_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE suppliers(
      id INTEGER PRIMARY KEY,
      name TEXT,
      phone TEXT,
      address TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE receipt_headers(
      receipt_number INTEGER PRIMARY KEY,
      total_amount REAL,
      date TEXT,
      status TEXT,
      notes TEXT,
      client_id INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE cheques(
      id INTEGER PRIMARY KEY,
      cheque_no TEXT,
      number TEXT,
      bank_name TEXT,
      bank TEXT,
      drawer_name TEXT,
      recipient_name TEXT,
      notes TEXT,
      due_date TEXT,
      amount REAL,
      status TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE purchase_invoices(
      id TEXT PRIMARY KEY,
      invoice_number TEXT,
      date TEXT,
      total REAL,
      amount_total REAL,
      status TEXT,
      note TEXT,
      supplier_id INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE vehicles(
      id INTEGER PRIMARY KEY,
      number TEXT,
      normalized_number TEXT,
      type TEXT,
      model TEXT,
      client_id INTEGER,
      notes TEXT,
      is_active INTEGER,
      updated_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE insurance_policies(
      id TEXT PRIMARY KEY,
      policy_number TEXT,
      document_number TEXT,
      insured_name TEXT,
      insured_phone TEXT,
      company_name TEXT,
      vehicle_plate TEXT,
      notes TEXT,
      updated_at TEXT,
      created_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE raw_materials(
      id INTEGER PRIMARY KEY,
      name TEXT,
      supplier TEXT,
      description TEXT,
      quantity REAL
    )
  ''');
  return db;
}

Future<void> seed(Database db) async {
  const token = 'ZZKEY';
  await db.insert('repairs', {
    'id': 'R1',
    'invoiceNumber': 'REP-1',
    'vehicleModel': 'Model',
    'vehicleType': 'Car',
    'vehicleNumber': 'PLATE-1',
    'beneficiaryName': 'Repair Client',
    'notes': token,
    'receivedDate': '2026-09-23T10:00:00',
  });
  await db.insert('clients', {
    'id': 1,
    'name': 'Client',
    'phone': '0599999999',
    'email': 'client@example.com',
    'address': 'Bethlehem',
    'notes': token,
    'type': 'individual',
  });
  await db.insert('invoices', {
    'id': 'INV1',
    'notes': token,
    'date': '2026-09-23T10:00:00',
    'total': 100,
    'paid': 20,
    'status': 'open',
  });
  await db.insert('payments', {
    'id': 'PAY1',
    'method': 'cash',
    'notes': token,
    'accountName': 'Cash',
    'date': '2026-09-23T10:00:00',
    'amount': 20,
  });
  await db.insert('employees', {
    'id': 'E1',
    'full_name': 'Employee',
    'job_title': 'Painter',
    'phone': '0560000000',
    'email': 'e@example.com',
    'notes': token,
    'created_at': '2026-09-23T10:00:00',
  });
  await db.insert('suppliers', {
    'id': 2,
    'name': 'Supplier $token',
    'phone': '022222222',
    'address': 'Hebron',
  });
  await db.insert('receipt_headers', {
    'receipt_number': 7,
    'total_amount': 50,
    'date': '2026-09-23T10:00:00',
    'status': 'posted',
    'notes': token,
    'client_id': 1,
  });
  await db.insert('cheques', {
    'id': 3,
    'cheque_no': 'CH-3',
    'number': '3',
    'bank_name': 'Bank',
    'bank': 'Bank',
    'drawer_name': 'Drawer',
    'recipient_name': 'Recipient',
    'notes': token,
    'due_date': '2026-10-01',
    'amount': 70,
    'status': 'pending',
  });
  await db.insert('purchase_invoices', {
    'id': 'P1',
    'invoice_number': 'PUR-1',
    'date': '2026-09-23T10:00:00',
    'total': 80,
    'amount_total': 80,
    'status': 'posted',
    'note': token,
    'supplier_id': 2,
  });
  await db.insert('vehicles', {
    'id': 4,
    'number': 'ABC-123',
    'normalized_number': 'ABC123',
    'type': 'Sedan',
    'model': '2024',
    'client_id': 1,
    'notes': token,
    'is_active': 1,
    'updated_at': '2026-09-23T10:00:00',
  });
  await db.insert('insurance_policies', {
    'id': 'POL1',
    'policy_number': 'POL-77',
    'document_number': 'DOC-77',
    'insured_name': 'Insured',
    'insured_phone': '0591111111',
    'company_name': 'Insurance Co',
    'vehicle_plate': 'ABC-123',
    'notes': token,
    'updated_at': '2026-09-23T10:00:00',
    'created_at': '2026-09-20T10:00:00',
  });
  await db.insert('raw_materials', {
    'id': 5,
    'name': 'Paint',
    'supplier': 'Supplier',
    'description': token,
    'quantity': 12,
  });
}

void main() {
  test('global search returns every required Stage 5 entity without starvation',
      () async {
    final db = await openSearchDb();
    DatabaseMigration.useDatabaseForTesting(db);
    addTearDown(() async {
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
    });
    await seed(db);

    final hits = await GlobalSearchService.search('ZZKEY');
    final bySource = <String, SearchHit>{
      for (final hit in hits) hit.source: hit,
    };

    expect(bySource.keys.toSet(), containsAll(<String>{
      'repairs',
      'clients',
      'invoices',
      'payments',
      'employees',
      'suppliers',
      'receipts',
      'cheques',
      'purchases',
      'vehicles',
      'documents',
      'items',
    }));

    expect(bySource['repairs']?.id, 'R1');
    expect(bySource['clients']?.id, '1');
    expect(bySource['invoices']?.id, 'INV1');
    expect(bySource['payments']?.id, 'PAY1');
    expect(bySource['employees']?.id, 'E1');
    expect(bySource['suppliers']?.id, '2');
    expect(bySource['receipts']?.id, '7');
    expect(bySource['cheques']?.id, '3');
    expect(bySource['purchases']?.id, 'P1');
    expect(bySource['vehicles']?.id, '4');
    expect(bySource['documents']?.id, 'POL1');
    expect(bySource['items']?.id, '5');
  });
  test('global search supports phone plate policy and item reference forms',
      () async {
    final db = await openSearchDb();
    DatabaseMigration.useDatabaseForTesting(db);
    addTearDown(() async {
      DatabaseMigration.useDatabaseForTesting(null);
      await db.close();
    });
    await seed(db);

    final phone = await GlobalSearchService.search('0599999999');
    final plate = await GlobalSearchService.search('ABC123');
    final policy = await GlobalSearchService.search('POL-77');
    final item = await GlobalSearchService.search('5');

    expect(phone.any((h) => h.source == 'clients' && h.id == '1'), isTrue);
    expect(plate.any((h) => h.source == 'vehicles' && h.id == '4'), isTrue);
    expect(policy.any((h) => h.source == 'documents' && h.id == 'POL1'), isTrue);
    expect(item.any((h) => h.source == 'items' && h.id == '5'), isTrue);
  });
}
