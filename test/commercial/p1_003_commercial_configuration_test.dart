import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/document_number_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
  });

  test('P1.003 fresh v60 commercial schema and sequence', () async {
    final temp = await Directory.systemTemp.createTemp('p1_003_');
    final path = '${temp.path}${Platform.pathSeparator}fresh.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      final v = sq.Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      expect(v, 60);
      expect(DatabaseConstants.dbVersion, 60);
      expect(await db.query('document_sequences'), hasLength(6));
      expect(
        await DocumentNumberService.nextOn(
          db,
          documentType: 'SALES_INVOICE',
        ),
        'INV-0001',
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.003 country presets carry currency only, not tax law', () {
    expect(CommercialSettingsService.presets.length, 9);
    for (final p in CommercialSettingsService.presets) {
      expect(p.currencyCode.length, 3);
      expect(p.decimals, inInclusiveRange(0, 3));
    }
  });

  test('P1.003 voucher numbering no longer scans MAX string', () {
    final s = File(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    ).readAsStringSync();
    expect(s.contains('ORDER BY voucher_number DESC'), isFalse);
    expect(s.contains('DocumentNumberService.nextOn'), isTrue);
  });
}
