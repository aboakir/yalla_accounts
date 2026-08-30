import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class NumberUtils {
  static String formatCurrency(
    double value, {
    String locale = 'ar-u-nu-latn',
    String? symbol,
    int? decimalDigits,
  }) {
    return MoneyFormatter.format(
      value,
      symbol: symbol,
      decimals: decimalDigits,
    );
  }

  static String formatNumber(double value, {int decimalDigits = 2}) {
    final formatter = NumberFormat.decimalPattern('ar');
    formatter.minimumFractionDigits = decimalDigits;
    formatter.maximumFractionDigits = decimalDigits;
    return formatter.format(value);
  }

  static String formatPercentage(double value, {int decimalDigits = 1}) {
    return '${value.toStringAsFixed(decimalDigits)}%';
  }
}
