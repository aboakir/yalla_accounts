import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import '../support/accounting_session.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/pdf/account_ledger_pdf.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ledger embeds Arabic and paginates mixed text with opening and totals',
      () async {
    await initializeDateFormatting('en');
    final bytes = await AccountLedgerPdf.generate(
        workshop: const WorkshopSettings(
            workshopName: 'ورشة لؤي أبو عكر لصيانة المركبات',
            city: 'الخليل',
            address: 'المنطقة الصناعية - شارع القدس',
            phone1: '0598636020'),
        accountName: '1100 - ذمم العميل أبو طارق الجعبري',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 9, 9),
        opening: 1250,
        rows: List.generate(
            85,
            (i) => {
                  'date': '2026-09-08 14:35',
                  'ref': 'INV-2026-${i + 1}',
                  'note': i % 2 == 0
                      ? 'إصلاح مركبة BMW وتركيب قطع أصلية - أجور صيانة المحرك'
                      : 'سند قبض من أبو طارق الجعبري مقابل فاتورة إصلاح المركبة',
                  'debit': i % 2 == 0 ? 6800.0 : 0.0,
                  'credit': i % 2 == 0 ? 0.0 : 970.0
                }));
    expect(bytes.take(4), [37, 80, 68, 70]);
    await Directory('output/pdf').create(recursive: true);
    await File('output/pdf/ledger-arabic-sample.pdf').writeAsBytes(bytes);
  });
  test(
      'repair document uses persisted lines and GL payment instead of stale model',
      () async {
    await initializeDateFormatting('en');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final temp = await Directory.systemTemp.createTemp('pdf_repair_');
    YallaStorageService.useRootDirectoryForTesting(
      Directory('${temp.path}/storage'),
    );
    final db = await DatabaseMigration.initDatabase(
        pathOverride: '${temp.path}/test.db');
    DatabaseMigration.useDatabaseForTesting(db);
    final session = await startAccountingSession(db, 'pdf-owner');
    try {
      await WorkshopSettingsService.instance.saveSettings(WorkshopSettings(
          logoPath: File('assets/logo/logo.png').absolute.path,
          workshopName: 'ورشة لؤي أبو عكر',
          city: 'الخليل',
          address: 'المنطقة الصناعية - شارع القدس',
          phone1: '0598636020'));
      final client = await db.insert(
          'clients', {'name': 'أبو طارق الجعبري', 'type': 'individual'});
      await db.insert('repairs', {
        'id': 'pdf-repair',
        'client_id': client,
        'vehicleNumber': '12-345-67',
        'vehicleType': 'BMW X5',
        'vehicleModel': '2020',
        'fileValue': 6800,
        'paymentType': 'cash',
        'status': 'DRAFT',
        'beneficiaryName': 'أبو طارق الجعبري',
        'beneficiaryType': 'individual',
        'receivedDate': '2026-09-09',
        'invoiceNumber': 'R-2026-025'
      });
      for (final line in [
        {
          'id': 'w',
          'name': 'صيانة المحرك وفحص نظام التبريد',
          'line_type': 'work',
          'qty': 2,
          'price': 1400,
          'total': 2800
        },
        {
          'id': 'p',
          'name': 'قطع أصلية BMW - طقم مضخة مياه',
          'line_type': 'part',
          'qty': 2,
          'price': 2000,
          'total': 4000
        }
      ]) {
        await db.insert('repair_lines', {'repair_id': 'pdf-repair', ...line});
      }
      await db.transaction((tx) =>
          RepairAutoAccountingService.finalizeNewRepairOn(tx, 'pdf-repair'));
      await PaymentService.insertCanonicalReceipt(
          operationId: 'pdf-receipt',
          database: db,
          clientId: client,
          customerName: 'أبو طارق الجعبري',
          method: 'cash',
          date: DateTime(2026, 9, 9),
          allocations: [
            ReceiptAllocationInput(repairId: 'pdf-repair', amount: 970)
          ],
          unallocatedAmount: 0);
      final saved = Repair.fromMap(
          (await db.query('repairs', where: 'id=?', whereArgs: ['pdf-repair']))
              .single);
      final stale = saved.copyWith(fileValue: 99999, paidAmount: 0);
      final bytes = await RepairPdfGenerator.generate(stale);
      await Directory('output/pdf').create(recursive: true);
      await File('output/pdf/repair-arabic-sample.pdf').writeAsBytes(bytes);
      expect(bytes.take(4), [37, 80, 68, 70]);
      // Export is read-only and repeatable financially.
      final before = (await db.query('gl_entries')).length;
      await RepairPdfGenerator.generate(stale);
      expect((await db.query('gl_entries')).length, before);
      for (var i = 0; i < 100; i++) {
        await db.insert('repair_lines', {
          'id': 'extra$i',
          'repair_id': 'pdf-repair',
          'line_type': 'part',
          'name': 'قطعة تفصيلية BMW X5 رقم $i',
          'qty': 1,
          'price': 0,
          'total': 0
        });
      }
      final long = await RepairPdfGenerator.generate(stale);
      await File('output/pdf/repair-long-sample.pdf').writeAsBytes(long);

      final cash =
          (await db.query('accounts', where: 'code=?', whereArgs: ['1000']))
              .single['id'] as int;
      final ledger = await AccountLedgerPdf.generateForAccount(cash,
          from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 30));
      await File('output/pdf/ledger-opening-only-sample.pdf')
          .writeAsBytes(ledger);
    } finally {
      await session.endEphemeralPreviewSession();
      DatabaseMigration.useDatabaseForTesting(null);
      YallaStorageService.useRootDirectoryForTesting(null);
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
