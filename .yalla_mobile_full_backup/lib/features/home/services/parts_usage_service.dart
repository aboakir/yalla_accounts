// 📁 lib/features/home/services/parts_usage_service.dart

import 'dart:convert';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

/// يمثل استهلاك جزء معين في مجموعة الإصلاحات
class PartConsumption {
  final String partId;
  final String partName;
  final int usedQuantity;

  PartConsumption({
    required this.partId,
    required this.partName,
    required this.usedQuantity,
  });
}

/// نتيجة إحصاءات استهلاك القطع
class PartsUsageStats {
  final List<PartConsumption> consumptions;

  PartsUsageStats({required this.consumptions});
}

/// خدمة لجلب إحصاءات استهلاك قطع الغيار بناءً على سجلات الإصلاح
class PartsUsageService {
  /// يحسب إجمالي استهلاك كل جزء عبر جميع الإصلاحات
  static Future<PartsUsageStats> getPartsUsageStats() async {
    // جلب كل الإصلاحات من قاعدة البيانات
    final repairs = await RepairDatabaseService.getAllRepairs();

    // خريطة لتجميع الكميات المستهلكة لكل جزء
    final Map<String, int> quantityMap = {};
    final Map<String, String> nameMap = {};

    for (final repair in repairs) {
      // الحقل parts في نموذج Repair مفكوك كـ JSON string أو List<Map>
      final partsField = repair.parts;
      List partsList;
      if (partsField is String) {
        partsList = jsonDecode(partsField as String) as List<dynamic>;
      } else {
        partsList = partsField;
      }

      for (final part in partsList) {
        final String id = part['id'] as String? ?? part['partId'] as String;
        final String name =
            part['name'] as String? ?? part['partName'] as String;
        final int qty = (part['quantity'] as num?)?.toInt() ?? 1;

        nameMap[id] = name;
        quantityMap[id] = (quantityMap[id] ?? 0) + qty;
      }
    }

    // تحويل الخريطة إلى قائمة PartConsumption
    final consumptions = quantityMap.entries.map((entry) {
      final id = entry.key;
      return PartConsumption(
        partId: id,
        partName: nameMap[id] ?? '—',
        usedQuantity: entry.value,
      );
    }).toList();

    // يمكن ترتيب القائمة نزوليًا حسب الكمية
    consumptions.sort((a, b) => b.usedQuantity.compareTo(a.usedQuantity));

    return PartsUsageStats(consumptions: consumptions);
  }
}
