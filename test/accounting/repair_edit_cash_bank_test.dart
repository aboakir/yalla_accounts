import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/edit_repair_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/services/liquidity_ledger_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';
import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      '6800 repair edits, receipts, cash and bank reconcile without duplicate postings',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final temp = await Directory.systemTemp.createTemp('repair_flow_');
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    final session = await startAccountingSession(db, 'flow-user');
    try {
      final client = await db.insert(
          'clients', {'name': 'Lifecycle client', 'type': 'individual'});
      final vehicle = await VehicleService.upsertFromRepairOn(db,
          number: 'TEST-6800', type: 'Car', model: '2020', clientId: client);
      expect(
          (await db.query('vehicles', where: 'id=?', whereArgs: [vehicle]))
              .single['client_id'],
          client);
      await db.insert('repairs', {
        'id': 'flow',
        'client_id': client,
        'vehicleNumber': 'TEST-6800',
        'vehicleType': 'Car',
        'vehicleModel': '2020',
        'fileValue': 6800,
        'notes': '',
        'paymentType': 'cash',
        'status': 'DRAFT'
      });
      for (final l in [
        {'name': 'work', 'price': 4000.0, 'line_type': 'work'},
        {'name': 'part', 'price': 2500.0, 'line_type': 'part'},
        {'name': 'remove', 'price': 300.0, 'line_type': 'work'}
      ]) {
        await db.insert('repair_lines', {
          'id': l['name'],
          'repair_id': 'flow',
          ...l,
          'qty': 1,
          'total': l['price']
        });
      }
      await db.transaction(
          (tx) => RepairAutoAccountingService.finalizeNewRepairOn(tx, 'flow'));
      Future<void> check(double total, double paid) async {
        final f = await RepairFinancialTruthService.load('flow', executor: db);
        final overview =
            await FinancialOverviewService.loadOn(db, to: DateTime(2100));
        final statement = await PartyFinancialService.statement(
            role: 'CUSTOMER',
            legacyId: client,
            executor: db,
            to: DateTime(2100));
        expect(statement.closingBalance, total - paid);
        expect(overview.customerReceivables, total - paid);
        expect(overview.revenue, total);
        final direct = await db.rawQuery(
            "SELECT SUM(l.debit-l.credit) balance FROM gl_lines l JOIN accounts a ON a.id=l.account_id WHERE a.code='1200' OR a.code LIKE '1200.%'");
        expect((direct.single['balance'] as num).toDouble(), total - paid);
        expect(f.fileValue, total);
        expect(f.paid, paid);
        expect(f.remaining, total - paid);
        expect(f.recognizedRevenue, total);
        expect(f.customerArBalance, total - paid);
        final row =
            (await db.query('repairs', where: 'id=?', whereArgs: ['flow']))
                .single;
        expect(row['paymentStatus'],
            RepairFinancialTruthService.paymentStatusFor(total, paid));
        expect(
            await db.rawQuery(
                'SELECT entry_id FROM gl_lines GROUP BY entry_id HAVING ABS(SUM(debit-credit))>0.005'),
            isEmpty);
      }

      expect(
          (await VehicleService.getHistoryByNumber('TEST-6800', database: db))
              .single
              .id,
          'flow');
      await check(6800, 0);
      Future<void> edit(List<Map<String, dynamic>> works,
          {double partPrice = 2500}) async {
        final r = Repair.fromMap(
            (await db.query('repairs', where: 'id=?', whereArgs: ['flow']))
                .single);
        await EditRepairService.editRepairWithAccounting(
            database: db,
            repairId: 'flow',
            updatedRepair: r,
            newWorks: works,
            newParts: [
              {'name': 'part', 'qty': 1, 'price': partPrice, 'total': 2500}
            ],
            notes: '',
            editedBy: 'flow-user');
      }

      Map<String, dynamic> line(String name, double price) =>
          {'name': name, 'qty': 1, 'price': price};
      var works = [line('work', 4000), line('remove', 300), line('added', 500)];
      await edit(works);
      await check(7300, 0);
      works = [line('work', 4000), line('added', 500)];
      await edit(works);
      await check(7000, 0);
      await edit(works, partPrice: 2700);
      await check(7200, 0);
      final count =
          (await db.rawQuery('SELECT COUNT(*) n FROM gl_entries')).single['n'];
      await edit(works, partPrice: 2700);
      await check(7200, 0);
      expect(
          (await db.rawQuery('SELECT COUNT(*) n FROM gl_entries')).single['n'],
          count);
      Future<CanonicalReceiptResult> receive(
              String id, String method, double value) =>
          PaymentService.insertCanonicalReceipt(
              operationId: id,
              database: db,
              clientId: client,
              customerName: 'Lifecycle client',
              method: method,
              date: DateTime(2026, 9, 8, 23, 59, 59, 900),
              allocations: [
                ReceiptAllocationInput(repairId: 'flow', amount: value)
              ],
              unallocatedAmount: 0);
      final cashReceipt = await receive('cash-receipt', 'cash', 970);
      await receive('cash-receipt', 'cash', 970);
      await check(7200, 970);
      await receive('bank-receipt', 'bank_transfer', 230);
      await check(7200, 1200);
      final cash =
          (await db.query('accounts', where: 'code=?', whereArgs: ['1000']))
              .single['id'] as int;
      final bank =
          (await db.query('accounts', where: 'code=?', whereArgs: ['1010']))
              .single['id'] as int;
      expect((await LiquidityLedgerService.load(db, cash)).closing, 970);
      expect((await LiquidityLedgerService.load(db, bank)).closing, 230);
      expect(
          (await LiquidityLedgerService.load(db, cash,
                  to: DateTime(2026, 9, 8)))
              .closing,
          970);
      final empty = await LiquidityLedgerService.load(db, cash,
          from: DateTime(2026, 9, 9), query: 'absent');
      expect(empty.rows, isEmpty);
      expect(empty.opening, 970);
      expect(empty.closing, 970);
      final searched = await LiquidityLedgerService.load(db, cash,
          query: 'no matching note');
      expect(searched.rows, isEmpty);
      expect(searched.closing, 970);
      await PaymentService.reverseReceipt(cashReceipt.receiptNumber,
          reason: 'test reversal', database: db);
      await check(7200, 230);
      expect((await LiquidityLedgerService.load(db, cash)).closing, 0);
      await receive('final-payment', 'cash', 6970);
      await check(7200, 7200);
      await receive('final-payment', 'cash', 6970);
      await check(7200, 7200);
      await expectLater(
          edit(works, partPrice: 2600), throwsA(isA<StateError>()));
      await check(7200, 7200);
      Future<void> spend(String id, String method, double amount) async {
        await VoucherPaymentService.insertAndPost(
            database: db,
            partyName: 'Workshop expense',
            voucher: VoucherPayment(
                id: id,
                voucherType: 'PAYMENT',
                partyType: 'EXPENSE',
                amount: amount,
                currency: 'ILS',
                date: DateTime(2026, 9, 8),
                method: method));
      }

      await spend('cash-expense', 'CASH', 70);
      await spend('cash-expense', 'CASH', 70);
      await spend('bank-expense', 'BANK', 30);
      expect((await LiquidityLedgerService.load(db, cash)).closing, 6900);
      expect((await LiquidityLedgerService.load(db, bank)).closing, 200);
      await VoucherPaymentService.reverseVoucher('bank-expense',
          reason: 'test reversal', database: db);
      expect((await LiquidityLedgerService.load(db, bank)).closing, 230);
      Future<void> transfer() async {
        await AccountingTables.postEntryGLOn(
            ex: db,
            date: DateTime(2026, 9, 8),
            source: 'CASH_BANK_TRANSFER',
            sourceId: 'test-transfer',
            lines: [
              {'account_id': bank, 'debit': 100.0, 'credit': 0.0},
              {'account_id': cash, 'debit': 0.0, 'credit': 100.0}
            ]);
      }

      await transfer();
      await transfer();
      expect((await LiquidityLedgerService.load(db, cash)).closing, 6800);
      expect((await LiquidityLedgerService.load(db, bank)).closing, 330);
      await check(7200, 7200);
      final ids = await db.rawQuery('SELECT id,code FROM accounts ORDER BY id');
      await AccountingTables.ensureDefaultAccounts(db);
      await AccountingTables.ensureDefaultAccounts(db);
      expect(
          await db.rawQuery('SELECT id,code FROM accounts ORDER BY id'), ids);
      Future<int> custom(String code, {int? parent, String type = 'ASSET'}) =>
          db.insert('accounts', {
            'code': code,
            'name': code,
            'type': type,
            'normal_balance': type == 'ASSET' ? 'DEBIT' : 'CREDIT',
            'parent_id': parent
          });
      final a = await custom('1801');
      final b = await custom('1802', parent: a);
      final c = await custom('1803', parent: b);
      await expectLater(
          db.update(
              'accounts', {'type': 'LIABILITY', 'normal_balance': 'CREDIT'},
              where: 'id=?', whereArgs: [a]),
          throwsA(isA<DatabaseException>()));
      await expectLater(
          db.update('accounts', {'parent_id': c},
              where: 'id=?', whereArgs: [a]),
          throwsA(isA<DatabaseException>()));
      await expectLater(
          custom('1804', parent: 999999), throwsA(isA<DatabaseException>()));
      await expectLater(custom('2801', parent: a, type: 'LIABILITY'),
          throwsA(isA<DatabaseException>()));
      await expectLater(db.delete('accounts', where: 'id=?', whereArgs: [a]),
          throwsA(isA<DatabaseException>()));
      await expectLater(db.delete('accounts', where: 'id=?', whereArgs: [cash]),
          throwsA(isA<DatabaseException>()));
      await expectLater(custom('1802'), throwsA(isA<DatabaseException>()));
    } finally {
      await session.endEphemeralPreviewSession();
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
