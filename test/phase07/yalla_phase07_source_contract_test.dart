import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P07 intake screen owns the official intake sequence', () {
    final screen = File('lib/features/repairs/screens/add_repair_screen.dart')
        .readAsStringSync();

    for (final marker in <String>[
      "'العميل'",
      "'المركبة'",
      "'الاستلام'",
      "'الأضرار'",
      "'التوثيق'",
      "'المراجعة'",
      'قراءة العداد',
      'مستوى الوقود',
      'الأضرار السابقة',
      'التقاط صورة',
      'توقيع العميل',
      'فتح الملف',
    ]) {
      expect(screen, contains(marker), reason: marker);
    }

    expect(screen, contains('RepairIntakeService.save'));
    expect(screen, isNot(contains('StepFinancialData')));
    expect(screen, isNot(contains('RepairSaveService.save')));
  });

  test('P07 intake save is pre-accounting and pre-approval', () {
    final service = File(
      'lib/features/repairs/services/repair_intake_service.dart',
    ).readAsStringSync();

    expect(service, contains("'status': 'QUOTE'"));
    expect(service, contains("'vehicleStatus': 'بانتظار الإصلاح'"));
    expect(service, contains("'isLedgerEnabled': 0"));
    expect(service, contains("'fileValue': 0.0"));
    expect(service, isNot(contains('createInvoiceForRepair')));
    expect(service, isNot(contains('postRepairGL')));
  });

  test(
      'P07 keeps the C02 v69 encryption contract and uses additive compatibility migration',
      () {
    final constants = File(
      'lib/core/services/db/database_constants.dart',
    ).readAsStringSync();
    final migration = File(
      'lib/core/services/db/database_migration.dart',
    ).readAsStringSync();
    final tables = File(
      'lib/core/services/db/tables/repair_tables.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/repairs/services/repair_intake_service.dart',
    ).readAsStringSync();

    // C02/P04 fail-closed encryption contract remains pinned at the deployed
    // v69 schema. P07 must not weaken it merely to add intake metadata.
    expect(constants, contains('static const int dbVersion = 69;'));
    expect(migration, isNot(contains('if (oldV < 70)')));
    expect(migration,
        isNot(contains('Upgrade v70 P07 repair intake schema applied')));

    // P07 migration is explicit, idempotent and additive at the repair-table
    // compatibility layer, following the same current-v69 bootstrap pattern
    // already used by C02 for vehicles/outbox.
    expect(tables, contains('Future<void> ensureP07IntakeSchema'));
    expect(tables,
        contains("_ensureColumn(db, 'repairs', 'odometer', 'INTEGER')"));
    expect(tables,
        contains("_ensureColumn(db, 'repairs', 'fuel_level', 'INTEGER')"));
    expect(tables,
        contains("_ensureColumn(db, 'repairs', 'previous_damage', 'TEXT')"));
    expect(
        tables,
        contains(
            "_ensureColumn(db, 'repairs', 'customer_signature_path', 'TEXT')"));
    expect(
        tables,
        contains(
            "_ensureColumn(db, 'repairs', 'intake_completed_at', 'TEXT')"));
    expect(service, contains('RepairTables.ensureP07IntakeSchema(db)'));

    for (final column in <String>[
      'odometer',
      'fuel_level',
      'previous_damage',
      'customer_signature_path',
      'intake_completed_at',
    ]) {
      expect(tables, contains(column), reason: column);
    }
    expect(tables, isNot(contains('DROP TABLE repairs')));
  });
}
