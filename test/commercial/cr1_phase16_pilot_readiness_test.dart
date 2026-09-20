import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/pilot/pilot_readiness_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Database> openFixture() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY,code TEXT)');
    await db.execute('''CREATE TABLE gl_entries(
      id INTEGER PRIMARY KEY,source TEXT NOT NULL,source_id TEXT NOT NULL)''');
    await db.execute(
      '''CREATE TABLE gl_lines(
      id INTEGER PRIMARY KEY,entry_id INTEGER,account_id INTEGER,debit REAL,credit REAL)''',
    );
    await db.execute('''CREATE TABLE accounting_audit_events(
      id INTEGER PRIMARY KEY,gl_entry_id INTEGER UNIQUE)''');
    await db.execute('''CREATE TABLE sync_outbox(
      outbox_id TEXT PRIMARY KEY,
      state TEXT NOT NULL,
      last_error TEXT)''');
    await db.execute('''CREATE TABLE sync_conflicts(
      conflict_id TEXT PRIMARY KEY,status TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE inventory_movements(
      id INTEGER PRIMARY KEY,on_hand_delta REAL)''');
    await db.execute('CREATE TABLE inventory_stock_balances(available REAL)');
    return db;
  }

  test(
    'Phase 16 local pilot snapshot derives accounting and sync evidence',
    () async {
      final db = await openFixture();
      addTearDown(db.close);
      await db.insert('accounts', {'id': 1, 'code': '1200.C1'});
      await db.insert('accounts', {'id': 2, 'code': '2100'});
      await db.insert('accounts', {'id': 3, 'code': '2105'});
      await db.insert('accounts', {'id': 4, 'code': '1000'});
      await db.insert('gl_entries', {
        'id': 10,
        'source': 'INVOICE',
        'source_id': 'INV-1',
      });
      await db.insert('gl_lines', {
        'id': 1,
        'entry_id': 10,
        'account_id': 1,
        'debit': 117.0,
        'credit': 0.0,
      });
      await db.insert('gl_lines', {
        'id': 2,
        'entry_id': 10,
        'account_id': 3,
        'debit': 0.0,
        'credit': 17.0,
      });
      await db.insert('gl_lines', {
        'id': 3,
        'entry_id': 10,
        'account_id': 4,
        'debit': 0.0,
        'credit': 100.0,
      });
      await db.insert('accounting_audit_events', {'id': 1, 'gl_entry_id': 10});
      await db.insert('sync_outbox', {'outbox_id': 'o1', 'state': 'PENDING'});
      await db.insert('inventory_movements', {'id': 1, 'on_hand_delta': 2.0});
      await db.insert('inventory_stock_balances', {'available': 2.0});

      final snapshot = await PilotReadinessService.inspect(db);
      expect(snapshot.accountingPass, isTrue);
      expect(snapshot.unbalancedEntries, 0);
      expect(snapshot.entriesMissingAudit, 0);
      expect(snapshot.duplicateSourcePostings, 0);
      expect(snapshot.pendingSync, 1);
      expect(snapshot.openLocalConflicts, 0);
      expect(snapshot.inventoryMovements, 1);
      expect(snapshot.negativeInventoryBalances, 0);
      expect(snapshot.accountsReceivable, 117.0);
      expect(snapshot.vatPayable, 17.0);
    },
  );

  test(
    'Phase 16 local pilot snapshot fails closed on accounting defects',
    () async {
      final db = await openFixture();
      addTearDown(db.close);
      await db.insert('accounts', {'id': 1, 'code': '1200.C1'});
      await db.insert('accounts', {'id': 2, 'code': '1000'});
      await db.insert('gl_entries', {
        'id': 20,
        'source': 'INVOICE',
        'source_id': 'INV-X',
      });
      await db.insert('gl_entries', {
        'id': 21,
        'source': 'INVOICE',
        'source_id': 'INV-X',
      });
      await db.insert('gl_lines', {
        'id': 20,
        'entry_id': 20,
        'account_id': 1,
        'debit': 100.0,
        'credit': 0.0,
      });
      await db.insert('gl_lines', {
        'id': 21,
        'entry_id': 20,
        'account_id': 2,
        'debit': 0.0,
        'credit': 90.0,
      });
      await db.insert('sync_outbox', {'outbox_id': 'o2', 'state': 'CONFLICT'});
      await db.insert('sync_conflicts', {
        'conflict_id': 'c1',
        'status': 'open',
      });
      await db.insert('inventory_stock_balances', {'available': -1.0});

      final snapshot = await PilotReadinessService.inspect(db);
      expect(snapshot.accountingPass, isFalse);
      expect(snapshot.unbalancedEntries, 2);
      expect(snapshot.entriesMissingAudit, 2);
      expect(snapshot.duplicateSourcePostings, 1);
      expect(snapshot.conflictedSync, 1);
      expect(snapshot.openLocalConflicts, 1);
      expect(snapshot.negativeInventoryBalances, 1);
    },
  );
}
