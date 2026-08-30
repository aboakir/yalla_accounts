import 'package:intl/intl.dart';

class MoneyFormatter {
  MoneyFormatter._();

  static String _currencyCode = 'ILS';
  static String _symbol = '₪';
  static int _decimals = 2;

  static const Map<String, String> _symbolsByCode = {
    'ILS': '₪',
    'JOD': 'د.أ',
    'EGP': 'ج.م',
    'SAR': 'ر.س',
    'AED': 'د.إ',
    'QAR': 'ر.ق',
    'KWD': 'د.ك',
    'BHD': 'د.ب',
    'OMR': 'ر.ع',
    'USD': r'$',
    'EUR': '€',
  };

  static const Map<String, int> _decimalsByCode = {
    'ILS': 2,
    'JOD': 3,
    'EGP': 2,
    'SAR': 2,
    'AED': 2,
    'QAR': 2,
    'KWD': 3,
    'BHD': 3,
    'OMR': 3,
    'USD': 2,
    'EUR': 2,
  };

  static String get currencyCode => _currencyCode;
  static String get symbol => _symbol;
  static int get decimals => _decimals;
  static String get zeroText => 0.toStringAsFixed(_decimals);

  static void configure({
    required String currencyCode,
    required String symbol,
    required int decimals,
  }) {
    final code = currencyCode.trim().toUpperCase();
    final safeDecimals = decimals < 0
        ? 0
        : decimals > 4
            ? 4
            : decimals;
    _currencyCode = code.isEmpty ? 'ILS' : code;
    _symbol = symbol.trim().isNotEmpty
        ? symbol.trim()
        : (_symbolsByCode[_currencyCode] ?? _currencyCode);
    _decimals = safeDecimals;
  }

  static String symbolForCode(String? currencyCode) {
    final code = (currencyCode ?? '').trim().toUpperCase();
    if (code.isEmpty || code == _currencyCode) return _symbol;
    return _symbolsByCode[code] ?? code;
  }

  static int decimalsForCode(String? currencyCode, {int? explicitDecimals}) {
    if (explicitDecimals != null) {
      return explicitDecimals < 0
          ? 0
          : explicitDecimals > 4
              ? 4
              : explicitDecimals;
    }
    final code = (currencyCode ?? '').trim().toUpperCase();
    if (code.isEmpty || code == _currencyCode) return _decimals;
    return _decimalsByCode[code] ?? 2;
  }

  static String number(
    num value, {
    int? decimals,
    String? currencyCode,
  }) {
    final d = decimalsForCode(currencyCode, explicitDecimals: decimals);
    final formatter = NumberFormat.decimalPattern('en_US')
      ..minimumFractionDigits = d
      ..maximumFractionDigits = d;
    return formatter.format(value);
  }

  static String format(
    num value, {
    String? currencyCode,
    String? symbol,
    int? decimals,
    bool showCode = false,
  }) {
    final code = (currencyCode ?? _currencyCode).trim().toUpperCase();
    final amount = number(
      value,
      decimals: decimals,
      currencyCode: code,
    );
    final displaySymbol = symbol?.trim().isNotEmpty == true
        ? symbol!.trim()
        : symbolForCode(code);

    if (showCode) {
      return '$amount $code';
    }
    return displaySymbol.isEmpty ? amount : '$amount $displaySymbol';
  }
}
