// 📁 lib/core/providers/forecast_stats_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// نموذج بيانات لإحصائيات التوقعات
class ForecastStats {
  /// قائمة بالإيرادات الشهرية التاريخية
  final List<MonthlyRevenue> history;

  /// توقع الإيراد للشهر القادم
  final double forecastNextMonth;

  ForecastStats({
    required this.history,
    required this.forecastNextMonth,
  });
}

/// نموذج بيانات لإيراد شهري
class MonthlyRevenue {
  final DateTime month;
  final double value;

  MonthlyRevenue({
    required this.month,
    required this.value,
  });
}

/// Provider لجلب إحصائيات التوقعات من الخدمة
final forecastStatsProvider = FutureProvider<ForecastStats>((ref) async {
  final service = ForecastService();
  return await service.getForecastStats();
});

ForecastService() {}
