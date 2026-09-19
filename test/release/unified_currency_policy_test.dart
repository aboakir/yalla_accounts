import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/constants/currencies.dart';
import 'package:yalla_accounts/core/services/db/tables/receipt_tables.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(sqfliteFfiInit);
  tearDown(() {
    MoneyFormatter.configure(currencyCode: 'ILS', symbol: '₪', decimals: 2);
  });

  test('legacy document currency is independent of display currency', () {
    MoneyFormatter.configure(currencyCode: 'JOD', symbol: 'د.أ', decimals: 3);
    expect(MoneyFormatter.currencyCode, 'JOD');
    expect(Currencies.legacyDocumentCurrencyCode, 'ILS');
  });

  test('receipt schema preserves legacy and explicit instrument currencies',
      () async {
    MoneyFormatter.configure(currencyCode: 'USD', symbol: r'$', decimals: 2);
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await ReceiptTables.createAllTables(db);
      final columns =
          await db.rawQuery('PRAGMA table_info(receipt_instruments)');
      final currency = columns.singleWhere((row) => row['name'] == 'currency');
      expect(currency['dflt_value'], "'ILS'");
      for (final code in <String?>[null, 'JOD', 'USD']) {
        final id = code ?? 'legacy';
        await db.insert('receipt_instruments', {
          'id': id,
          'receipt_number': 1,
          'instrument_key': id,
          'method': 'cash',
          'amount': 12.5,
          if (code != null) 'currency': code,
          'created_at': DateTime.utc(2026, 9, 20).toIso8601String(),
        });
      }
      final rows = await db.query('receipt_instruments');
      final saved = {for (final row in rows) row['id']: row['currency']};
      expect(saved, {'legacy': 'ILS', 'JOD': 'JOD', 'USD': 'USD'});
    } finally {
      await db.close();
    }
  });
}
