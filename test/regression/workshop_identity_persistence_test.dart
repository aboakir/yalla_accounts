import 'dart:io';
import 'dart:convert';
import 'package:yalla_accounts/core/pdf/account_ledger_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/services/workshop_logo_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
      'profile and portable logo survive cache deletion, DB reopen and root move',
      () async {
    final temp = await Directory.systemTemp.createTemp('workshop_identity_');
    var root = Directory('${temp.path}/old/YallaAccounts');
    final dbPath = '${temp.path}/identity.db';
    var db = await databaseFactoryFfi.openDatabase(dbPath);
    try {
      await WorkshopSettingsService.createTable(db);
      for (final column in [
        'country_code TEXT',
        'base_currency_code TEXT',
        'currency_symbol TEXT',
        'currency_decimals INTEGER',
        'default_vat_rate REAL',
        'prices_include_vat INTEGER',
        'tax_registration_number TEXT'
      ]) {
        await db.execute('ALTER TABLE workshop_settings ADD COLUMN $column');
      }
      WorkshopSettingsService service() => WorkshopSettingsService(
          databaseProvider: () async => db,
          logos: WorkshopLogoService(rootProvider: () async => root));
      final image = await File('assets/logo/logo.png').readAsBytes();
      final cache = File('${temp.path}/gallery.png');
      await cache.writeAsBytes(image);
      await service().saveSettings(WorkshopSettings.defaults().copyWith(
          workshopName: 'ورشة الاختبار',
          address: 'شارع الورش',
          city: 'الخليل',
          phone1: '0599000000',
          phone2: '022000000',
          email: 'test@example.com',
          logoPath: cache.path,
          workStart: '08:00',
          workEnd: '17:00',
          dailyHours: 8,
          breakMinutes: 60,
          weekWorkdays: '1,2,3,4,5'));
      await CommercialSettingsService.instance.save(
          const CommercialSettings(
              countryCode: 'PS',
              baseCurrencyCode: 'ILS',
              currencySymbol: '₪',
              currencyDecimals: 2,
              defaultVatRate: 16,
              pricesIncludeVat: true,
              taxRegistrationNumber: 'TAX-123'),
          executor: db);
      final saved = (await db.query('workshop_settings')).single;
      expect(saved['logoPath'], startsWith('documents/branding/'));
      await cache.delete();
      await db.close();
      root = await root.rename('${temp.path}/moved-YallaAccounts');
      db = await databaseFactoryFfi.openDatabase(dbPath);
      final restored = await service().getOrDefaults();
      expect(await File(restored.logoPath!).readAsBytes(), image);
      final pdf = await AccountLedgerPdf.generate(
          workshop: restored, accountName: 'الصندوق', opening: 0, rows: []);
      expect(RegExp(r'/Subtype\s*/Image').hasMatch(latin1.decode(pdf)), isTrue);
      expect(restored.workshopName, 'ورشة الاختبار');
      expect(restored.address, 'شارع الورش');
      expect(restored.phone1, '0599000000');
      expect(restored.email, 'test@example.com');
      expect(restored.weekWorkdays, '1,2,3,4,5');
      expect(restored.workStart, '08:00');
      expect(restored.workEnd, '17:00');
      expect(restored.breakMinutes, 60);
      await service().saveSettings(restored.copyWith(workshopName: 'اسم معدل'));
      final commercial =
          await CommercialSettingsService.instance.get(executor: db);
      expect(commercial.baseCurrencyCode, 'ILS');
      expect(commercial.taxRegistrationNumber, 'TAX-123');
      expect(commercial.defaultVatRate, 16);
      expect(commercial.pricesIncludeVat, isTrue);
      expect((await db.query('workshop_settings')).length, 1);
      expect(
          await root.list(recursive: true).where((e) => e is File).length, 1);
      // A legacy gallery path is recovered on read without losing profile fields.
      final legacy = File('${temp.path}/legacy.png');
      await legacy.writeAsBytes(image);
      await db.update('workshop_settings', {'logoPath': legacy.path},
          where: 'id=1');
      final migrated = await service().getOrDefaults();
      await legacy.delete();
      expect(await File(migrated.logoPath!).exists(), isTrue);
      expect(migrated.workshopName, 'اسم معدل');
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });
}
