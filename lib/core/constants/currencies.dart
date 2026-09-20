class SupportedCurrency {
  final String code;
  final String name;
  final String symbol;

  const SupportedCurrency({
    required this.code,
    required this.name,
    required this.symbol,
  });
}

class Currencies {
  /// Historical documents without a currency predate configurable currency.
  /// Keep their original base currency independent of the display settings.
  static const String legacyDocumentCurrencyCode = 'ILS';

  static const List<SupportedCurrency> list = [
    SupportedCurrency(code: 'ILS', name: 'شيكل', symbol: '₪'),
    SupportedCurrency(code: 'USD', name: 'دولار أمريكي', symbol: '\$'),
    SupportedCurrency(code: 'EUR', name: 'يورو', symbol: '€'),
    SupportedCurrency(code: 'SAR', name: 'ريال سعودي', symbol: '﷼'),
    SupportedCurrency(code: 'JOD', name: 'دينار أردني', symbol: 'د.أ'),
    SupportedCurrency(code: 'EGP', name: 'جنيه مصري', symbol: 'ج.م'),
  ];
}
