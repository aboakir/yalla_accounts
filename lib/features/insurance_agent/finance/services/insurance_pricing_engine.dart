class InsurancePricingInput {
  const InsurancePricingInput({
    required this.purchasePrice,
    required this.salePrice,
    this.basePremium = 0,
    this.discount = 0,
    this.fees = 0,
    this.tax = 0,
    this.commissionRate = 0,
    this.directCost = 0,
  });

  final double purchasePrice;
  final double salePrice;
  final double basePremium;
  final double discount;
  final double fees;
  final double tax;
  final double commissionRate;
  final double directCost;
}

class InsurancePricingResult {
  const InsurancePricingResult({
    required this.purchasePrice,
    required this.salePrice,
    required this.basePremium,
    required this.discount,
    required this.fees,
    required this.tax,
    required this.commissionRate,
    required this.commissionAmount,
    required this.directCost,
    required this.netSaleAmount,
    required this.netInsurerPayable,
    required this.grossProfit,
    required this.markupPercent,
    required this.marginPercent,
  });

  final double purchasePrice;
  final double salePrice;
  final double basePremium;
  final double discount;
  final double fees;
  final double tax;
  final double commissionRate;
  final double commissionAmount;
  final double directCost;
  final double netSaleAmount;
  final double netInsurerPayable;
  final double grossProfit;
  final double markupPercent;
  final double marginPercent;
}

class InsurancePricingEngine {
  InsurancePricingEngine._();

  static double money(double value) => double.parse(value.toStringAsFixed(2));

  static InsurancePricingResult calculate(InsurancePricingInput input) {
    final values = <double>[
      input.purchasePrice,
      input.salePrice,
      input.basePremium,
      input.discount,
      input.fees,
      input.tax,
      input.commissionRate,
      input.directCost,
    ];
    if (values.any((value) => !value.isFinite || value < 0)) {
      throw ArgumentError('Insurance pricing values must be finite and >= 0.');
    }
    if (input.discount > input.salePrice) {
      throw ArgumentError('Discount cannot exceed sale price.');
    }

    final commissionBase = input.basePremium > 0
        ? input.basePremium
        : input.purchasePrice;
    final commission = commissionBase * input.commissionRate / 100;
    final netSale = input.salePrice - input.discount + input.fees + input.tax;
    final costBase = input.purchasePrice + input.directCost;
    final profit = netSale - costBase;
    final markup = costBase == 0 ? 0.0 : profit / costBase * 100;
    final margin = netSale == 0 ? 0.0 : profit / netSale * 100;

    return InsurancePricingResult(
      purchasePrice: money(input.purchasePrice),
      salePrice: money(input.salePrice),
      basePremium: money(input.basePremium),
      discount: money(input.discount),
      fees: money(input.fees),
      tax: money(input.tax),
      commissionRate: input.commissionRate,
      commissionAmount: money(commission),
      directCost: money(input.directCost),
      netSaleAmount: money(netSale),
      netInsurerPayable: money(input.purchasePrice),
      grossProfit: money(profit),
      markupPercent: markup,
      marginPercent: margin,
    );
  }
}
