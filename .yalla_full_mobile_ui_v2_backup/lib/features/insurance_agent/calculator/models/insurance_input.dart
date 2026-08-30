// 📁 lib/features/insurance_agent/calculater/models/insurance_input.dart

import 'insurance_category.dart';

class InsuranceInput {
  /// الفئة المختارة
  final InsuranceCategory category;

  /// سعر المركبة (إجباري في كل الحالات)
  final double vehiclePrice;

  /// سعة المحرك (سي سي)
  final int? engineCc;

  /// الوزن بالطن
  final double? weightTon;

  /// عدد الركاب
  final int? passengers;

  /// خيار ثابت (نوع آلية، نوع تاكسي، نوع مجرور...)
  final String? fixedOption;

  const InsuranceInput({
    required this.category,
    required this.vehiclePrice,
    this.engineCc,
    this.weightTon,
    this.passengers,
    this.fixedOption,
  });

  /// نسخ مع تعديل (مهم مع Provider)
  InsuranceInput copyWith({
    InsuranceCategory? category,
    double? vehiclePrice,
    int? engineCc,
    double? weightTon,
    int? passengers,
    String? fixedOption,
  }) {
    return InsuranceInput(
      category: category ?? this.category,
      vehiclePrice: vehiclePrice ?? this.vehiclePrice,
      engineCc: engineCc ?? this.engineCc,
      weightTon: weightTon ?? this.weightTon,
      passengers: passengers ?? this.passengers,
      fixedOption: fixedOption ?? this.fixedOption,
    );
  }

  /// تحقق سريع من المدخلات المطلوبة حسب الفئة
  bool get isValid {
    for (final input in category.requiredInputs) {
      switch (input) {
        case InsuranceInputType.engineCc:
          if (engineCc == null) return false;
          break;
        case InsuranceInputType.weightTon:
          if (weightTon == null) return false;
          break;
        case InsuranceInputType.passengers:
          if (passengers == null) return false;
          break;
        case InsuranceInputType.fixedOption:
          if (vehiclePrice <= 0) return false;
          break;
      }
    }
    return true;
  }
}
