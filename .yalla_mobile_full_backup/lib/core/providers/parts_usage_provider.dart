// 📁 lib/core/providers/parts_usage_provider.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// استيراد نموذج البيانات فقط
import 'package:yalla_accounts/features/home/models/parts_usage_stats.dart';
// استيراد الخدمة مع إخفاء التعريف المكرر للنموذج
import 'package:yalla_accounts/features/home/services/parts_usage_service.dart'
    hide PartsUsageStats;

/// Provider لجلب بيانات استهلاك القطع من الخدمة
/// نتوقع هنا أن `getPartsUsageStats()` ترجع **مزامنًا** `PartsUsageStats`
/// لذلك نُغلفها في `Future.value(...)` لنحصل على `Future<PartsUsageStats>`
final partsUsageProvider = FutureProvider<PartsUsageStats>((ref) {
  final stats = PartsUsageService.getPartsUsageStats();
  return Future.value(stats as FutureOr<PartsUsageStats>?);
});
