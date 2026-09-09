import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class CountryPreset {
  final String code;
  final String nameAr;
  final String currencyCode;
  final String currencySymbol;
  final int decimals;

  const CountryPreset(
    this.code,
    this.nameAr,
    this.currencyCode,
    this.currencySymbol,
    this.decimals,
  );
}

class CommercialSettings {
  final String countryCode;
  final String baseCurrencyCode;
  final String currencySymbol;
  final int currencyDecimals;
  final double defaultVatRate;
  final bool pricesIncludeVat;
  final String taxRegistrationNumber;

  const CommercialSettings({
    required this.countryCode,
    required this.baseCurrencyCode,
    required this.currencySymbol,
    required this.currencyDecimals,
    required this.defaultVatRate,
    required this.pricesIncludeVat,
    required this.taxRegistrationNumber,
  });
}

class CommercialSettingsService {
  CommercialSettingsService._();
  static final instance = CommercialSettingsService._();

  static const presets = <CountryPreset>[
    CountryPreset('PS', 'فلسطين', 'ILS', '₪', 2),
    CountryPreset('JO', 'الأردن', 'JOD', 'د.أ', 3),
    CountryPreset('EG', 'مصر', 'EGP', 'ج.م', 2),
    CountryPreset('SA', 'السعودية', 'SAR', 'ر.س', 2),
    CountryPreset('AE', 'الإمارات', 'AED', 'د.إ', 2),
    CountryPreset('QA', 'قطر', 'QAR', 'ر.ق', 2),
    CountryPreset('KW', 'الكويت', 'KWD', 'د.ك', 3),
    CountryPreset('BH', 'البحرين', 'BHD', 'د.ب', 3),
    CountryPreset('OM', 'عُمان', 'OMR', 'ر.ع', 3),
  ];

  Future<CommercialSettings> get({DatabaseExecutor? executor}) async {
    final db = executor ?? await DBService.database;
    final rows = await db.query(
      'workshop_settings',
      columns: [
        'country_code',
        'base_currency_code',
        'currency_symbol',
        'currency_decimals',
        'default_vat_rate',
        'prices_include_vat',
        'tax_registration_number',
      ],
      where: 'id=1',
      limit: 1,
    );
    final row = rows.isEmpty ? <String, Object?>{} : rows.first;
    final settings = CommercialSettings(
      countryCode: (row['country_code'] ?? 'PS').toString(),
      baseCurrencyCode: (row['base_currency_code'] ?? 'ILS').toString(),
      currencySymbol: (row['currency_symbol'] ?? '₪').toString(),
      currencyDecimals: (row['currency_decimals'] as num?)?.toInt() ?? 2,
      defaultVatRate: (row['default_vat_rate'] as num?)?.toDouble() ?? 0,
      pricesIncludeVat:
          ((row['prices_include_vat'] as num?)?.toInt() ?? 0) == 1,
      taxRegistrationNumber: (row['tax_registration_number'] ?? '').toString(),
    );

    MoneyFormatter.configure(
      currencyCode: settings.baseCurrencyCode,
      symbol: settings.currencySymbol,
      decimals: settings.currencyDecimals,
    );
    return settings;
  }

  Future<void> save(CommercialSettings value,
      {DatabaseExecutor? executor}) async {
    if (value.baseCurrencyCode.trim().length != 3) {
      throw ArgumentError('Currency code must contain 3 ISO letters.');
    }
    if (value.currencyDecimals < 0 || value.currencyDecimals > 4) {
      throw ArgumentError('Currency decimals must be 0..4.');
    }
    if (value.defaultVatRate < 0 || value.defaultVatRate > 100) {
      throw ArgumentError('VAT rate must be 0..100.');
    }

    final db = executor ?? await DBService.database;
    final current = await get(executor: db);
    final nextCurrency = value.baseCurrencyCode.trim().toUpperCase();

    if (nextCurrency != current.baseCurrencyCode.trim().toUpperCase()) {
      final rows = await db.rawQuery(r'''
        SELECT
          (SELECT COUNT(*) FROM gl_entries) +
          (SELECT COUNT(*) FROM invoices) +
          (SELECT COUNT(*) FROM purchase_invoices) +
          (SELECT COUNT(*) FROM payments) +
          (SELECT COUNT(*) FROM vouchers) AS financial_rows
      ''');
      final raw = rows.isEmpty ? 0 : rows.first['financial_rows'];
      final financialRows =
          raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;

      if (financialRows > 0) {
        throw StateError(
          'لا يمكن تغيير عملة الأساس بعد وجود حركات مالية. '
          'أنشئ قاعدة بيانات/منشأة جديدة للعملة الجديدة حتى لا تختلط '
          'المبالغ التاريخية بعملة مختلفة.',
        );
      }
    }

    await db.update(
      'workshop_settings',
      {
        'country_code': value.countryCode.trim().toUpperCase(),
        'base_currency_code': nextCurrency,
        'currency_symbol': value.currencySymbol.trim(),
        'currency_decimals': value.currencyDecimals,
        'default_vat_rate': value.defaultVatRate,
        'prices_include_vat': value.pricesIncludeVat ? 1 : 0,
        'tax_registration_number': value.taxRegistrationNumber.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=1',
    );

    MoneyFormatter.configure(
      currencyCode: nextCurrency,
      symbol: value.currencySymbol,
      decimals: value.currencyDecimals,
    );
  }
}
