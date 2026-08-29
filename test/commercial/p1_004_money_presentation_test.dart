import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

void main() {
  test('P1.004 formats 2-decimal and 3-decimal currencies correctly', () {
    MoneyFormatter.configure(
      currencyCode: 'ILS',
      symbol: '₪',
      decimals: 2,
    );
    expect(MoneyFormatter.format(12.5), '12.50 ₪');

    MoneyFormatter.configure(
      currencyCode: 'JOD',
      symbol: 'د.أ',
      decimals: 3,
    );
    expect(MoneyFormatter.format(12.5), '12.500 د.أ');
    expect(MoneyFormatter.number(0), '0.000');

    MoneyFormatter.configure(
      currencyCode: 'KWD',
      symbol: 'د.ك',
      decimals: 3,
    );
    expect(MoneyFormatter.format(1234.567), '1,234.567 د.ك');

    MoneyFormatter.configure(
      currencyCode: 'AED',
      symbol: 'د.إ',
      decimals: 2,
    );
    expect(MoneyFormatter.format(1234.5), '1,234.50 د.إ');

    // Restore the live installation default for isolated test behavior.
    MoneyFormatter.configure(
      currencyCode: 'ILS',
      symbol: '₪',
      decimals: 2,
    );
  });

  test('P1.004 presentation surfaces have no hardcoded shekel markers', () {
    const allow = <String>{
      'lib/core/constants/currencies.dart',
      'lib/core/services/db/database_migration.dart',
      'lib/core/services/db/tables/cheque_tables.dart',
      'lib/core/services/db/tables/voucher_tables.dart',
      'lib/features/cheques/models/cheque.dart',
      'lib/features/cheques/screens/cheque_add_screen.dart',
      'lib/features/cheques/services/cheque_accounting_service.dart',
      'lib/features/employees/services/advance_database_service.dart',
      'lib/features/finance/payments/services/payment_service.dart',
      'lib/features/settings/services/commercial_settings_service.dart',
      'lib/features/subscription/screens/current_subscription_screen.dart',
      'lib/features/subscription/screens/subscription_screen.dart',
      'lib/features/vouchers/models/voucher_payment_model.dart',
      'lib/features/vouchers/services/voucher_payment_service.dart',
      'lib/core/utils/money_formatter.dart',
    };

    final forbidden = RegExp(r'(₪|شيكل|\bILS\b|\bNIS\b)');
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final rel = entity.path.replaceAll('\\', '/');
      if (allow.contains(rel)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (forbidden.hasMatch(lines[i])) {
          violations.add('$rel:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Hardcoded workshop-currency presentation remains:\n'
          '${violations.join('\n')}',
    );
  });

  test('P1.004 locks base-currency changes once financial history exists', () {
    final source = File(
      'lib/features/settings/services/commercial_settings_service.dart',
    ).readAsStringSync();

    expect(source.contains('financial_rows'), isTrue);
    expect(source.contains('لا يمكن تغيير عملة الأساس بعد وجود حركات مالية'),
        isTrue);
    expect(source.contains('MoneyFormatter.configure'), isTrue);
  });
}
