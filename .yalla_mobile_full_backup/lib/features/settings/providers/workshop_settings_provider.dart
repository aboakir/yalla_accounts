// 📁 lib/features/settings/providers/workshop_settings_provider.dart
//
// مزوّد Riverpod لإعدادات الورشة.
// - يوفر WorkshopSettings جاهز بالاستخدام مع افتراضات عند عدم وجود بيانات.
// - يعرض AsyncValue<WorkshopSettings> للاستهلاك في الشاشات والخدمات.
//
// الاستخدام:
// final ws = ref.watch(workshopSettingsProvider).value;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

final workshopSettingsProvider = FutureProvider<WorkshopSettings>((ref) async {
  // نجلب الإعدادات أو الافتراضات الآمنة لو الجدول فارغ
  final settings = await WorkshopSettingsService.instance.getOrDefaults();
  return settings;
});

/// مزوّد يُحدّث الإعدادات ويُعيد التحميل بعد الحفظ.
final workshopSettingsWriteProvider =
    Provider<Future<void> Function(WorkshopSettings)>((ref) {
  return (WorkshopSettings s) async {
    await WorkshopSettingsService.instance.saveSettings(s);
    // نعمل refresh للـ provider حتى تنعكس التغييرات فورًا
    ref.invalidate(workshopSettingsProvider);
  };
});
