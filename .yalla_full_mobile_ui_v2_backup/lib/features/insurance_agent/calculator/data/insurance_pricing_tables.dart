// 📁 lib/features/insurance_agent/calculater/data/insurance_pricing_tables.dart

class InsurancePricingTables {
  // ------------------------------------------------------------------
  // 1) المركبات الخصوصية
  // ------------------------------------------------------------------
  static const privateCarsTpByEngine = [
    _RangePrice(max: 1000, price: 935),
    _RangePrice(min: 1001, max: 1500, price: 1035),
    _RangePrice(min: 1501, max: 2000, price: 1340),
    _RangePrice(min: 2001, price: 1690),
  ];

  static const privateCarsCompRatio = 0.0175;
  static const privateCarsMinComp = 1000;

  // ------------------------------------------------------------------
  // 2) المركبات التجارية
  // ------------------------------------------------------------------
  static const commercialByWeight = [
    _RangePrice(max: 1, price: 1600),
    _RangePrice(min: 1, max: 1.6, price: 2050),
    _RangePrice(min: 1.6, max: 4, price: 2900),
    _RangePrice(min: 4, max: 6, price: 2870),
    _RangePrice(min: 6, price: 3055),
  ];

  static const commercialSpecial = {
    'باص صغير': 3305,
    'شاحنة + نصف قاطرة': 1605,
    'رأس قاطرة': 2205,
    'رأس قاطرة + نصف قاطرة': 2905,
    'خلاطة / آليات ثقيلة': 3255,
  };

  static const commercialCompRatio = 0.02;
  static const commercialMinComp = 1500;

  // ------------------------------------------------------------------
  // 3) سيارات التأجير
  // ------------------------------------------------------------------
  static const rentalCarsByEngine = [
    _RangePrice(max: 1000, price: 2095),
    _RangePrice(min: 1001, max: 1500, price: 2345),
    _RangePrice(min: 1501, max: 2000, price: 2595),
    _RangePrice(min: 2001, price: 2945),
  ];

  static const rentalCarsByWeight = [
    _RangePrice(max: 1.6, price: 4105),
    _RangePrice(min: 1.6, max: 4, price: 4905),
    _RangePrice(min: 4, price: 4655),
  ];

  static const rentalCompFixed = 3000;

  // ------------------------------------------------------------------
  // 4) التاكسيات
  // ------------------------------------------------------------------
  static const taxiOneDriver = {
    '4-6': 1750,
    'عمومي/خصوصي': 2450,
    'كبير': 2650,
  };

  static const taxiTwoDrivers = {
    '4-6': 1905,
    '7': 2655,
    '8': 2805,
  };

  static const taxiAnyDriver = {
    '4-6': 2020,
    '7': 2830,
    '8': 2960,
  };

  static const taxiCompRatio = 0.025;
  static const taxiMinComp = 1500;

  // ------------------------------------------------------------------
  // 5) الباصات
  // ------------------------------------------------------------------
  static const privateBus = {
    '21': 2760,
    '35': 3760,
    '50': 5710,
  };

  static const publicBus = {
    '21': 3960,
    '35': 4960,
    '50': 7460,
  };

  static const busCompRatio = 0.02;
  static const busMinComp = 2000;

  // ------------------------------------------------------------------
  // 6) الاتجار بالمركبات
  // ------------------------------------------------------------------
  static const tradeMandatory = 2555;
  static const tradeCompRatio = 0.0175;
  static const tradeMinComp = 1000;

  // ------------------------------------------------------------------
  // 7) الدراجات النارية
  // ------------------------------------------------------------------
  static const motorcycles = [
    _RangePrice(max: 50, price: 1150),
    _RangePrice(min: 51, max: 250, price: 1300),
    _RangePrice(min: 251, price: 1400),
  ];

  static const motorcycleCompRatio = 0.0175;
  static const motorcycleMinComp = 1000;

  // ------------------------------------------------------------------
  // 8) المجرور
  // ------------------------------------------------------------------
  static const trailersByWeight = [
    _RangePrice(max: 1, price: 755),
    _RangePrice(min: 1, max: 3, price: 1355),
    _RangePrice(min: 3, max: 6, price: 1455),
    _RangePrice(min: 6, max: 16, price: 1605),
    _RangePrice(min: 16, price: 1905),
  ];

  static const trailerSpecial = {
    'صهريج': 1805,
    'قلاب': 1505,
    'خاص': 1805,
    'زراعي': 1455,
  };

  static const trailerCompRatio = 0.02;
  static const trailerMinComp = 1500;

  // ------------------------------------------------------------------
  // 9) آليات منوعة أخرى
  // ------------------------------------------------------------------
  static const otherMachineryMandatory = {
    'مركبة اسعاف': 2170,
    'عيادة متنقلة': 2170,
    'مركبة اطفاء': 1855,
    'توزيع غاز': 2445,
    'نقل الموتى': 1920,
    'الة تسوية': 1605,
    'جرافة عجل': 1605,
    'جرافة عجل صغيرة': 1605,
    'مركبة اطفاء مع سلم': 2105,
    'حفار ابار مياه': 3805,
    'حامل تلسكوبي': 1605,
    'ماكينة دهان طرق': 1605,
    'جرافة جنزير': 1605,
    'تراكتور جنزير': 1605,
    'حفار جنزير': 2005,
    'مدحلة': 1555,
    'دنبر/مكنسة': 1105,
    'فراشة اسفلت': 2855,
    'تراكتور زراعي': 1705,
    'جرافة': 1605,
    'مركبة صحية حتى 29 طن': 3255,
    'شاحنة تبديل صناديق': 4005,
    'شاحنة نفايات': 3255,
    'ونش عنكبوت': 3805,
    'حفار اقل 19': 3505,
    'حفار اكثر 19': 3805,
    'مركبة تخليص وجر': 4205,
    'مركبة جر ونقل': 4005,
    'نقل سيارات': 2555,
    'تراكتور مع وصلة': 2205,
    'ونش كهرباء': 3805,
    'شاحنة سيطرة نقل سيارات': 4005,
  };

  static const otherMachineryCompRatio = 0.02;
  static const otherMachineryMinComp = 1500;
}

// ----------------------------------------------------------------------
// Helper class
// ----------------------------------------------------------------------

class _RangePrice {
  final double? min;
  final double? max;
  final double price;

  const _RangePrice({this.min, this.max, required this.price});

  bool match(num value) {
    if (min != null && value < min!) return false;
    if (max != null && value > max!) return false;
    return true;
  }
}
