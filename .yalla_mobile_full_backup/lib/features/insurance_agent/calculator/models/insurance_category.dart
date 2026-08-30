// 📁 lib/features/insurance_agent/calculater/models/insurance_category.dart

enum InsuranceInputType {
  engineCc, // سعة المحرك
  weightTon, // الوزن بالطن
  passengers, // عدد الركاب
  fixedOption, // اختيار ثابت (قيمة/فئة/سعر...)
}

class InsuranceCategory {
  final String key;
  final String title;
  final String description;

  /// ✅ خيارات ثابتة تُستخدم عندما يوجد InsuranceInputType.fixedOption
  /// IMPORTANT: لو تركتها فاضية، لازم الواجهة تتعامل معها.
  final List<String> fixedOptions;

  final List<InsuranceInputType> requiredInputs;

  const InsuranceCategory({
    required this.key,
    required this.title,
    required this.description,
    this.fixedOptions = const [], // ✅ يمنع الكراش
    required this.requiredInputs,
  });
}

/// جميع فئات حاسبة التأمين المعتمدة
class InsuranceCategories {
  // ملاحظة: الخيارات الثابتة أدناه "فارغة" لتجنب بيانات وهمية داخل النظام.
  // إذا بدك نضيف خيارات حقيقية (مثل شرائح سعر المركبة/فئات معتمدة)، زودني بالقائمة الرسمية.

  static const privateCars = InsuranceCategory(
    key: 'private',
    title: 'المركبات الخصوصية',
    description: 'تأمين مركبات خاصة حسب سعة المحرك وسعر/فئة المركبة.',
    requiredInputs: [
      InsuranceInputType.engineCc,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [], // ضع هنا خيارات حقيقية عند توفرها
  );

  static const commercialCars = InsuranceCategory(
    key: 'commercial',
    title: 'المركبات التجارية',
    description:
        'مركبات تجارية تعتمد على الوزن + خيار ثابت (حسب تسعير الشركة).',
    requiredInputs: [
      InsuranceInputType.weightTon,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const rentalCars = InsuranceCategory(
    key: 'rental',
    title: 'سيارات التأجير',
    description: 'سيارات تأجير (محرك + وزن) مع خيار ثابت حسب الجدول.',
    requiredInputs: [
      InsuranceInputType.engineCc,
      InsuranceInputType.weightTon,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const taxiSingleDriver = InsuranceCategory(
    key: 'taxi_single',
    title: 'تاكسي – سائق واحد',
    description: 'تاكسي بسائق واحد حسب عدد الركاب + خيار ثابت.',
    requiredInputs: [
      InsuranceInputType.passengers,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const taxiTwoDrivers = InsuranceCategory(
    key: 'taxi_double',
    title: 'تاكسي – سائقين',
    description: 'تاكسي بسائقين حسب عدد الركاب + خيار ثابت.',
    requiredInputs: [
      InsuranceInputType.passengers,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const taxiAnyDriver = InsuranceCategory(
    key: 'taxi_any',
    title: 'تاكسي – أي سائق',
    description: 'تاكسي لأي سائق حسب عدد الركاب + خيار ثابت.',
    requiredInputs: [
      InsuranceInputType.passengers,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const privateBuses = InsuranceCategory(
    key: 'bus_private',
    title: 'باصات خصوصية / سياحية',
    description: 'باصات خصوصي/سياحي حسب عدد الركاب + خيار ثابت.',
    requiredInputs: [
      InsuranceInputType.passengers,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const publicBuses = InsuranceCategory(
    key: 'bus_public',
    title: 'باصات عمومية',
    description: 'باصات عمومية حسب عدد الركاب + خيار ثابت.',
    requiredInputs: [
      InsuranceInputType.passengers,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const vehicleTrading = InsuranceCategory(
    key: 'trading',
    title: 'الاتجار بالمركبات',
    description: 'الاتجار بالمركبات (خيار ثابت فقط).',
    requiredInputs: [
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const motorcycles = InsuranceCategory(
    key: 'motorcycle',
    title: 'الدراجات النارية',
    description: 'دراجات نارية حسب سعة المحرك + خيار ثابت.',
    requiredInputs: [
      InsuranceInputType.engineCc,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  static const trailers = InsuranceCategory(
    key: 'trailer',
    title: 'المجرورات',
    description: 'مجرورات حسب الوزن + خيار ثابت.',
    requiredInputs: [
      InsuranceInputType.weightTon,
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: const [],
  );

  // ✅ UPDATED: آليات منوعة أخرى (القائمة المنسدلة ستظهر الآن)
  static const specialMachinery = InsuranceCategory(
    key: 'machinery',
    title: 'آليات منوعة أخرى',
    description: 'آليات خاصة (اختر نوع الآلية من القائمة).',
    requiredInputs: [
      InsuranceInputType.fixedOption,
    ],
    fixedOptions: [
      'إسعاف',
      'عيادة متنقلة',
      'مركبة إطفاء',
      'توزيع غاز',
      'نقل موتى',
      'آلة تسوية (جريدر)',
      'جرافة عجل (كباش)',
      'جرافة عجل صغيرة',
      'مركبة إطفاء مع سلم',
      'حفار آبار مياه',
      'حامل تلسكوبي',
      'ماكينة دهان طرق',
      'جرافة جنزير',
      'تراكتور جنزير',
      'حفار جنزير (باقر)',
      'مدحلة',
      'دنبر / مزليك / مكنسة آلية',
      'فراشة الأسفلت (فنشر)',
      'تراكتور زراعي',
      'جرافة',
      'مركبة صحية لغاية 29 طن',
      'شاحنة تبديل صناديق',
      'شاحنة ضاغطة للنفايات',
      'ونش العنكبوت لغاية 15 طن',
      'مركبة قدح (حفار) أقل من 19 طن',
      'مركبة قدح (حفار) أكثر من 19 طن',
      'مركبة تخليص وجر لغاية 19 طن',
      'مركبة للجر مع سيطرة ونقل',
      'شاحنة نقل سيارات لغاية 15 طن',
      'تراكتور مع وصلة جر',
      'ونش كهرباء لغاية 5 طن',
      'شاحنة سيطرة نقل سيارات',
    ],
  );

  /// قائمة جاهزة للاستخدام في Dropdown
  static const List<InsuranceCategory> all = [
    privateCars,
    commercialCars,
    rentalCars,
    taxiSingleDriver,
    taxiTwoDrivers,
    taxiAnyDriver,
    privateBuses,
    publicBuses,
    vehicleTrading,
    motorcycles,
    trailers,
    specialMachinery,
  ];
}
