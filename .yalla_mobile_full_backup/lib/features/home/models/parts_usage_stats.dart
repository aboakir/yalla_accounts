// 📁 lib/features/home/models/parts_usage_stats.dart

/// يمثل استهلاك جزء معين في مجموعة الإصلاحات
class PartConsumption {
  /// معرف الجزء
  final String partId;

  /// اسم الجزء
  final String partName;

  /// الكمية المستهلكة منه
  final int usedQuantity;

  PartConsumption({
    required this.partId,
    required this.partName,
    required this.usedQuantity,
  });
}

/// يحتوي على قائمة باستهلاك جميع الأجزاء
class PartsUsageStats {
  /// قائمة باستهلاك كل جزء
  final List<PartConsumption> consumptions;

  PartsUsageStats({
    required this.consumptions,
  });
}
