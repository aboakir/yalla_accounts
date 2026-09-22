import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

void main() {
  test('mandatory 2400/2000 pricing scenario is exact', () {
    final result = InsurancePricingEngine.calculate(
      const InsurancePricingInput(
        purchasePrice: 2000,
        salePrice: 2400,
      ),
    );

    expect(result.netSaleAmount, 2400);
    expect(result.netInsurerPayable, 2000);
    expect(result.grossProfit, 400);
    expect(result.markupPercent, closeTo(20, 0.000001));
    expect(result.marginPercent, closeTo(16.6666667, 0.00001));
  });

  test('tax collected for a third party is excluded from commercial profit',
      () {
    final result = InsurancePricingEngine.calculate(
      const InsurancePricingInput(
        purchasePrice: 2000,
        salePrice: 2400,
        tax: 100,
      ),
    );

    expect(result.customerTotalAmount, 2500);
    expect(result.netSaleAmount, 2500);
    expect(result.netRevenueAmount, 2400);
    expect(result.tax, 100);
    expect(result.netInsurerPayable, 2000);
    expect(result.grossProfit, 400);
    expect(result.markupPercent, closeTo(20, 0.000001));
    expect(result.marginPercent, closeTo(16.6666667, 0.00001));
  });

  test('discount fees tax commission and direct cost are deterministic', () {
    final result = InsurancePricingEngine.calculate(
      const InsurancePricingInput(
        purchasePrice: 2000,
        salePrice: 2500,
        basePremium: 2000,
        discount: 100,
        fees: 25,
        tax: 75,
        commissionRate: 10,
        directCost: 50,
      ),
    );

    expect(result.customerTotalAmount, 2500);
    expect(result.netRevenueAmount, 2425);
    expect(result.commissionAmount, 200);
    expect(result.netInsurerPayable, 2000);
    expect(result.grossProfit, 375);
    expect(result.markupPercent, closeTo(18.2926829, 0.00001));
    expect(result.marginPercent, closeTo(15.4639175, 0.00001));
  });

  test('invalid negative pricing and excessive discount are rejected', () {
    expect(
      () => InsurancePricingEngine.calculate(
        const InsurancePricingInput(purchasePrice: -1, salePrice: 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => InsurancePricingEngine.calculate(
        const InsurancePricingInput(
          purchasePrice: 1,
          salePrice: 100,
          discount: 101,
        ),
      ),
      throwsArgumentError,
    );
  });
}
