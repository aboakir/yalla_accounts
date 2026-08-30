// 📁 lib/features/insurance_agent/calculater/models/insurance_breakdown.dart

class InsuranceBreakdown {
  /// التأمين الإلزامي
  final double mandatory;

  /// التأمين الشامل
  final double comprehensive;

  /// المجموع النهائي
  final double total;

  /// هل تم تطبيق الحد الأدنى للتكميلي؟
  final bool minApplied;

  /// ملاحظات توضيحية (اختياري)
  final String? note;

  const InsuranceBreakdown({
    required this.mandatory,
    required this.comprehensive,
    required this.total,
    this.minApplied = false,
    this.note,
  });

  /// حالة فارغة (قبل الحساب)
  factory InsuranceBreakdown.empty() {
    return const InsuranceBreakdown(
      mandatory: 0,
      comprehensive: 0,
      total: 0,
    );
  }

  bool get hasResult => total > 0;
}
