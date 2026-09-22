import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

double fromMinor(int value) => value / 100.0;
int toMinor(double value) => (value * 100).round();

void main() {
  test('10,000 pricing cases match an independent minor-unit reference', () {
    final random = Random(982026);
    var negativeProfitCases = 0;
    var taxCases = 0;
    var discountCases = 0;
    var feeCases = 0;
    var commissionCases = 0;

    for (var index = 0; index < 10000; index++) {
      final purchaseMinor = random.nextInt(1000001);
      final saleMinor = random.nextInt(1200001);
      final discountMinor = saleMinor == 0 ? 0 : random.nextInt(saleMinor + 1);
      final feesMinor = random.nextInt(50001);
      final taxMinor = random.nextInt(30001);
      final directCostMinor = random.nextInt(50001);
      final basePremiumUnits = 1 + random.nextInt(10000);
      final commissionRate = random.nextInt(31);

      final expectedCustomerMinor =
          saleMinor - discountMinor + feesMinor + taxMinor;
      final expectedRevenueMinor = saleMinor - discountMinor + feesMinor;
      final expectedCostMinor = purchaseMinor + directCostMinor;
      final expectedProfitMinor = expectedRevenueMinor - expectedCostMinor;
      final expectedCommissionMinor = basePremiumUnits * commissionRate;

      final result = InsurancePricingEngine.calculate(
        InsurancePricingInput(
          purchasePrice: fromMinor(purchaseMinor),
          salePrice: fromMinor(saleMinor),
          basePremium: basePremiumUnits.toDouble(),
          discount: fromMinor(discountMinor),
          fees: fromMinor(feesMinor),
          tax: fromMinor(taxMinor),
          commissionRate: commissionRate.toDouble(),
          directCost: fromMinor(directCostMinor),
        ),
      );

      expect(toMinor(result.customerTotalAmount), expectedCustomerMinor,
          reason: 'case $index customer total');
      expect(toMinor(result.netRevenueAmount), expectedRevenueMinor,
          reason: 'case $index net revenue');
      expect(toMinor(result.netInsurerPayable), purchaseMinor,
          reason: 'case $index insurer payable');

      expect(toMinor(result.directCost), directCostMinor,
          reason: 'case $index direct cost');
      expect(toMinor(result.grossProfit), expectedProfitMinor,
          reason: 'case $index profit');
      expect(toMinor(result.tax), taxMinor, reason: 'case $index tax');
      expect(toMinor(result.commissionAmount), expectedCommissionMinor,
          reason: 'case $index commission');

      if (expectedCostMinor == 0) {
        expect(result.markupCalculable, isFalse, reason: 'case $index markup');
        expect(result.markupPercent, 0, reason: 'case $index markup');
      } else {
        expect(result.markupCalculable, isTrue, reason: 'case $index markup');
        expect(
          result.markupPercent,
          closeTo(expectedProfitMinor / expectedCostMinor * 100, 1e-9),
          reason: 'case $index markup',
        );
      }

      if (expectedRevenueMinor == 0) {
        expect(result.marginCalculable, isFalse, reason: 'case $index margin');
        expect(result.marginPercent, 0, reason: 'case $index margin');
      } else {
        expect(result.marginCalculable, isTrue, reason: 'case $index margin');
        expect(
          result.marginPercent,
          closeTo(expectedProfitMinor / expectedRevenueMinor * 100, 1e-9),
          reason: 'case $index margin',
        );
      }

      if (expectedProfitMinor < 0) negativeProfitCases++;
      if (taxMinor > 0) taxCases++;
      if (discountMinor > 0) discountCases++;
      if (feesMinor > 0) feeCases++;
      if (commissionRate > 0) commissionCases++;
    }

    expect(negativeProfitCases, greaterThan(0));
    expect(taxCases, greaterThan(0));
    expect(discountCases, greaterThan(0));
    expect(feeCases, greaterThan(0));
    expect(commissionCases, greaterThan(0));
  });

  test('commission fallback rounds once at the minor-unit boundary', () {
    final result = InsurancePricingEngine.calculate(
      const InsurancePricingInput(
        purchasePrice: 1234.56,
        salePrice: 1600,
        commissionRate: 7.5,
      ),
    );

    final expectedMinor = (123456 * 7.5 / 100).round();
    expect(toMinor(result.commissionAmount), expectedMinor);
  });

  test('zero denominators are explicitly marked non-calculable', () {
    final result = InsurancePricingEngine.calculate(
      const InsurancePricingInput(
        purchasePrice: 0,
        salePrice: 0,
      ),
    );

    expect(result.markupCalculable, isFalse);
    expect(result.marginCalculable, isFalse);
    expect(result.markupPercent, 0);
    expect(result.marginPercent, 0);
  });
}
