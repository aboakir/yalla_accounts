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

  /// Total amount collectible from the customer, including tax collected
  /// for third parties. Kept as netSaleAmount for storage/API compatibility.
  final double netSaleAmount;
  final double netInsurerPayable;
  final double grossProfit;
  final double markupPercent;
  final double marginPercent;

  double get customerTotalAmount => netSaleAmount;
  double get netRevenueAmount => netSaleAmount - tax;
  bool get markupCalculable => purchasePrice + directCost != 0;
  bool get marginCalculable => netRevenueAmount != 0;
}

class InsurancePricingEngine {
  InsurancePricingEngine._();

  static int _minor(double value) => (value * 100).round();
  static double _fromMinor(int value) => value / 100.0;

  static double money(double value) => _fromMinor(_minor(value));

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

    final purchaseMinor = _minor(input.purchasePrice);
    final saleMinor = _minor(input.salePrice);
    final basePremiumMinor = _minor(input.basePremium);
    final discountMinor = _minor(input.discount);
    final feesMinor = _minor(input.fees);
    final taxMinor = _minor(input.tax);
    final directCostMinor = _minor(input.directCost);

    final commissionBaseMinor =
        basePremiumMinor > 0 ? basePremiumMinor : purchaseMinor;
    final commissionMinor =
        (commissionBaseMinor * input.commissionRate / 100).round();
    final customerTotalMinor = saleMinor - discountMinor + feesMinor + taxMinor;
    final netRevenueMinor = customerTotalMinor - taxMinor;
    final costBaseMinor = purchaseMinor + directCostMinor;
    final profitMinor = netRevenueMinor - costBaseMinor;
    final markup = costBaseMinor == 0 ? 0.0 : profitMinor / costBaseMinor * 100;
    final margin =
        netRevenueMinor == 0 ? 0.0 : profitMinor / netRevenueMinor * 100;

    return InsurancePricingResult(
      purchasePrice: _fromMinor(purchaseMinor),
      salePrice: _fromMinor(saleMinor),
      basePremium: _fromMinor(basePremiumMinor),
      discount: _fromMinor(discountMinor),
      fees: _fromMinor(feesMinor),
      tax: _fromMinor(taxMinor),
      commissionRate: input.commissionRate,
      commissionAmount: _fromMinor(commissionMinor),
      directCost: _fromMinor(directCostMinor),
      netSaleAmount: _fromMinor(customerTotalMinor),
      netInsurerPayable: _fromMinor(purchaseMinor),
      grossProfit: _fromMinor(profitMinor),
      markupPercent: markup,
      marginPercent: margin,
    );
  }
}
