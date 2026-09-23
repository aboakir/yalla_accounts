import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/finance/reports/screens/balance_sheet_screen.dart';
import 'package:yalla_accounts/features/reports/screens/trial_balance_screen.dart';

void main() {
  test('Stage 5 export screens compile and construct', () {
    expect(const BalanceSheetScreen(), isA<BalanceSheetScreen>());
    expect(const TrialBalanceScreen(), isA<TrialBalanceScreen>());
  });
}
