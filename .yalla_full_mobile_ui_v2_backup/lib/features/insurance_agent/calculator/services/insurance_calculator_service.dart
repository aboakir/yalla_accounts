import '../models/insurance_input.dart';
import '../models/insurance_breakdown.dart';

class InsuranceCalculatorService {
  InsuranceBreakdown calculate(InsuranceInput input) {
    double mandatory = 0;
    double comprehensive = 0;
    double minComprehensive = 0;
    double ratio = 0;

    switch (input.category.key) {
      // ------------------------------------------------------------------
      // المركبات الخصوصية
      // ------------------------------------------------------------------
      case 'private':
        mandatory = _privateMandatory(input.engineCc!);
        ratio = 0.0175;
        minComprehensive = 1000;
        break;

      // ------------------------------------------------------------------
      // المركبات التجارية
      // fixedOption now represents mode/type key:
      // - by_weight, bus_small, truck_semi, tractor_head, tractor_head_semi, mixer
      // ------------------------------------------------------------------
      case 'commercial':
        mandatory = _commercialMandatory(
          weight: input.weightTon,
          type: input.fixedOption,
        );
        ratio = 0.02;
        minComprehensive = 1500;
        break;

      // ------------------------------------------------------------------
      // سيارات التأجير
      // fixedOption represents mode: by_engine / by_weight
      // ------------------------------------------------------------------
      case 'rental':
        mandatory = _rentalMandatory(
          mode: input.fixedOption,
          engineBandValue: input.engineCc,
          weightBandValue: input.weightTon,
        );
        comprehensive = 3000; // ثابت
        return _result(
          mandatory: mandatory,
          comprehensive: comprehensive,
          minApplied: false,
        );

      // ------------------------------------------------------------------
      // تاكسي – سائق واحد (passengers is encoded as: 6 / 7 / 8)
      // ------------------------------------------------------------------
      case 'taxi_single':
        mandatory = _taxiSingleMandatory(input.passengers!);
        ratio = 0.025;
        minComprehensive = 1500;
        break;

      // ------------------------------------------------------------------
      // تاكسي – سائقين
      // ------------------------------------------------------------------
      case 'taxi_double':
        mandatory = _taxiDoubleMandatory(input.passengers!);
        ratio = 0.025;
        minComprehensive = 1500;
        break;

      // ------------------------------------------------------------------
      // تاكسي – أي سائق
      // ------------------------------------------------------------------
      case 'taxi_any':
        mandatory = _taxiAnyMandatory(input.passengers!);
        ratio = 0.025;
        minComprehensive = 1500;
        break;

      // ------------------------------------------------------------------
      // باصات خصوصية / سياحية
      // ------------------------------------------------------------------
      case 'bus_private':
        mandatory = _busPrivateMandatory(input.passengers!);
        ratio = 0.02;
        minComprehensive = 2000;
        break;

      // ------------------------------------------------------------------
      // باصات عمومية
      // ------------------------------------------------------------------
      case 'bus_public':
        mandatory = _busPublicMandatory(input.passengers!);
        ratio = 0.02;
        minComprehensive = 2000;
        break;

      // ------------------------------------------------------------------
      // الاتجار بالمركبات
      // ------------------------------------------------------------------
      case 'trading':
        mandatory = 2555;
        ratio = 0.0175;
        minComprehensive = 1000;
        break;

      // ------------------------------------------------------------------
      // الدراجات النارية
      // ------------------------------------------------------------------
      case 'motorcycle':
        mandatory = _motorcycleMandatory(input.engineCc!);
        ratio = 0.0175;
        minComprehensive = 1000;
        break;

      // ------------------------------------------------------------------
      // المجرورات
      // fixedOption: by_load / tanker / tipper / special / agriculture
      // ------------------------------------------------------------------
      case 'trailer':
        mandatory = _trailerMandatory(
          weight: input.weightTon,
          type: input.fixedOption,
        );
        ratio = 0.02;
        minComprehensive = 1500;
        break;

      // ------------------------------------------------------------------
      // آليات منوعة أخرى (fixedOption هنا نص عربي من القائمة)
      // ------------------------------------------------------------------
      case 'machinery':
        mandatory = _machineryMandatoryArabic(input.fixedOption!);
        ratio = 0.02;
        minComprehensive = 1500;
        break;

      default:
        throw Exception('Unsupported insurance category');
    }

    // حساب الشامل (إذا لم يكن ثابت)
    comprehensive = input.vehiclePrice * ratio;
    bool minApplied = false;

    if (comprehensive < minComprehensive) {
      comprehensive = minComprehensive;
      minApplied = true;
    }

    return _result(
      mandatory: mandatory,
      comprehensive: comprehensive,
      minApplied: minApplied,
    );
  }

  // ======================================================================
  // Helpers
  // ======================================================================

  InsuranceBreakdown _result({
    required double mandatory,
    required double comprehensive,
    required bool minApplied,
  }) {
    return InsuranceBreakdown(
      mandatory: mandatory,
      comprehensive: comprehensive,
      total: mandatory + comprehensive,
      minApplied: minApplied,
    );
  }

  // ------------------ Mandatory calculators -----------------------------

  double _privateMandatory(int engineBandValue) {
    // engineBandValue encoded as:
    // 1000 => 0-1000
    // 1500 => 1001-1500
    // 2000 => 1501-2000
    // 2001 => 2000+
    if (engineBandValue <= 1000) return 935;
    if (engineBandValue <= 1500) return 1035;
    if (engineBandValue <= 2000) return 1340;
    return 1690;
  }

  double _commercialMandatory({
    required double? weight,
    required String? type,
  }) {
    // type is one of:
    // by_weight, bus_small, truck_semi, tractor_head, tractor_head_semi, mixer
    switch (type) {
      case 'bus_small':
        return 3305;
      case 'truck_semi':
        return 1605;
      case 'tractor_head':
        return 2205;
      case 'tractor_head_semi':
        return 2905;
      case 'mixer':
        return 3255;
      case 'by_weight':
      case null:
      default:
        if (weight == null) {
          throw Exception('Commercial by weight requires weightTon');
        }
        // weight encoded as:
        // 1.0 => 0-1
        // 1.6 => 1-1.6
        // 4.0 => 1.6-4
        // 6.0 => 4-6
        // 6.1 => >6
        if (weight <= 1.0) return 1600;
        if (weight <= 1.6) return 2050;
        if (weight <= 4.0) return 2900;
        if (weight <= 6.0) return 2870;
        return 3055;
    }
  }

  double _rentalMandatory({
    required String? mode, // by_engine / by_weight
    required int? engineBandValue,
    required double? weightBandValue,
  }) {
    final m = mode ?? 'by_engine';

    if (m == 'by_weight') {
      if (weightBandValue == null) {
        throw Exception('Rental by weight requires weightTon');
      }
      // weight encoded as:
      // 1.6 => <=1.6
      // 2.0 => >1.6
      // 4.1 => >4
      if (weightBandValue > 4.0) return 4655; // أكثر من 4 طن
      if (weightBandValue > 1.6) return 4905; // أكثر من 1.6 طن
      return 4105; // حتى 1.6 طن
    }

    // by_engine
    if (engineBandValue == null) {
      throw Exception('Rental by engine requires engineCc');
    }
    // engine band encoded as:
    // 1000,1500,2000,2001
    if (engineBandValue <= 1000) return 2095;
    if (engineBandValue <= 1500) return 2345;
    if (engineBandValue <= 2000) return 2595;
    return 2945;
  }

  double _taxiSingleMandatory(int encodedChoice) {
    // encodedChoice: 6 => 4-6 ركاب, 7 => عمومي/خصوصي, 8 => كبير
    if (encodedChoice <= 6) return 1750;
    if (encodedChoice == 7) return 2450;
    return 2650;
  }

  double _taxiDoubleMandatory(int passengersBand) {
    // passengersBand: 6 => 4-6, 7 => 7, 8 => 8
    if (passengersBand <= 6) return 1905;
    if (passengersBand == 7) return 2655;
    return 2805;
  }

  double _taxiAnyMandatory(int passengersBand) {
    if (passengersBand <= 6) return 2020;
    if (passengersBand == 7) return 2830;
    return 2960;
  }

  double _busPrivateMandatory(int passengersBand) {
    if (passengersBand <= 21) return 2760;
    if (passengersBand <= 35) return 3760;
    return 5710;
  }

  double _busPublicMandatory(int passengersBand) {
    if (passengersBand <= 21) return 3960;
    if (passengersBand <= 35) return 4960;
    return 7460;
  }

  double _motorcycleMandatory(int engineBandValue) {
    // encoded: 50, 250, 251
    if (engineBandValue <= 50) return 1150;
    if (engineBandValue <= 250) return 1300;
    return 1400;
  }

  double _trailerMandatory({
    required double? weight,
    required String? type,
  }) {
    // type: by_load / tanker / tipper / special / agriculture
    switch (type) {
      case 'tanker':
        return 1805;
      case 'tipper':
        return 1505;
      case 'special':
        return 1805;
      case 'agriculture':
        return 1455;
      case 'by_load':
      case null:
      default:
        if (weight == null) {
          throw Exception('Trailer by load requires weightTon');
        }
        // weight encoded as:
        // 1.0,3.0,6.0,16.0,16.1
        if (weight <= 1.0) return 755;
        if (weight <= 3.0) return 1355;
        if (weight <= 6.0) return 1455;
        if (weight <= 16.0) return 1605;
        return 1905;
    }
  }

  double _machineryMandatoryArabic(String typeArabic) {
    // mapping مباشر من نص القائمة العربية إلى سعر الإلزامي
    const Map<String, double> map = {
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
      'دنبر / مكنسة': 1105,
      'فراشة اسفلت': 2855,
      'تراكتور زراعي': 1705,
      'جرافة': 1605,
      'مركبة صحية': 3255,
      'شاحنة تبديل صناديق': 4005,
      'شاحنة نفايات': 3255,
      'ونش عنكبوت': 3805,
      'حفار أقل من 19': 3505,
      'حفار أكثر من 19': 3805,
      'مركبة تخليص وجر': 4205,
      'مركبة جر ونقل': 4005,
      'نقل سيارات': 2555,
      'تراكتور مع وصلة': 2205,
      'ونش كهرباء': 3805,
      'شاحنة سيطرة نقل سيارات': 4005,
    };

    // fallback احتياطي
    return map[typeArabic] ?? 1605.0;
  }
}
