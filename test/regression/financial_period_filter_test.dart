import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';

void main() {
  test('week crosses month boundary and presets stop today', () {
    final now = DateTime(2026, 10, 1, 23, 59);
    expect(
        FinancialPeriodFilter.preset('week', now).start, DateTime(2026, 9, 28));
    for (final key in ['today', 'week', 'month']) {
      expect(FinancialPeriodFilter.preset(key, now).end, DateTime(2026, 10, 1));
    }
    expect(FinancialPeriodFilter.preset('month', DateTime(2024, 2, 29)).start,
        DateTime(2024, 2, 1));
  });
  testWidgets('presets apply and custom date picker can be cancelled',
      (t) async {
    DateTimeRange? chosen;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FinancialPeriodFilter(onChanged: (r) => chosen = r))));
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('اليوم'));
    await t.pumpAndSettle();
    expect(chosen!.start, chosen!.end);
    final previous = chosen;
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('فترة مخصصة'));
    await t.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(chosen, previous);
    expect(t.takeException(), isNull);
  });
}
