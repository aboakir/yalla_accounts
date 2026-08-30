// -----------------------------------------------------------------------------
// 📁 lib/core/services/license_service.dart
// نظام التفعيل + التجربة + ربط جهازين + منع التلاعب
// -----------------------------------------------------------------------------

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  // ---------------------------------------------------------------------------
  // CONSTANTS
  // ---------------------------------------------------------------------------

  static const int trialDays = 12;
  static const String keyDeviceId = "yalla_device_id";
  static const String keyTrialStart = "yalla_trial_start";
  static const String keyTrialEnd = "yalla_trial_end";
  static const String keyLastRun = "yalla_last_run";
  static const String keyActivated = "yalla_is_activated";
  static const String keyActivatedCode = "yalla_activation_code";
  static const String keyActivationExpiry = "yalla_activation_expiry";

  static const String keyDevice1 = "yalla_act_device_1";
  static const String keyDevice2 = "yalla_act_device_2";

  // ---------------------------------------------------------------------------
  // DEVICE FINGERPRINT (UUID لكل جهاز)
  // ---------------------------------------------------------------------------
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(keyDeviceId);

    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(keyDeviceId, id);
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // فحص التلاعب بالتاريخ
  // ---------------------------------------------------------------------------
  Future<bool> _detectTimeTampering() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getInt(keyLastRun);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lastRun != null && now < lastRun) {
      return true; // تم إرجاع الوقت للخلف
    }

    await prefs.setInt(keyLastRun, now);
    return false;
  }

  // ---------------------------------------------------------------------------
  // بدء التجربة لأول مرة
  // ---------------------------------------------------------------------------
  Future<void> startTrialIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final start = prefs.getString(keyTrialStart);

    if (start != null) return; // التجربة بدأت مسبقاً

    final now = DateTime.now();
    final end = now.add(const Duration(days: trialDays));

    await prefs.setString(keyTrialStart, now.toIso8601String());
    await prefs.setString(keyTrialEnd, end.toIso8601String());
  }

  // ---------------------------------------------------------------------------
  // هل التجربة منتهية؟
  // ---------------------------------------------------------------------------
  Future<bool> isTrialExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final endStr = prefs.getString(keyTrialEnd);

    if (endStr == null) return true; // بسبب التلاعب أو المسح

    final end = DateTime.parse(endStr);
    final now = DateTime.now();

    return now.isAfter(end);
  }

  // ---------------------------------------------------------------------------
  // تفعيل التطبيق بكود تفعيل
  // ---------------------------------------------------------------------------
  Future<String?> activateWithCode(String code, DateTime expiryDate) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _getDeviceId();

    // قراءة الأجهزة المرتبطة سابقاً
    String? d1 = prefs.getString(keyDevice1);
    String? d2 = prefs.getString(keyDevice2);

    // جهاز أول
    if (d1 == null) {
      await prefs.setString(keyDevice1, deviceId);
    }
    // جهاز ثاني
    else if (d2 == null && d1 != deviceId) {
      await prefs.setString(keyDevice2, deviceId);
    }
    // جهاز ثالث؟ مرفوض
    else if (d1 != deviceId && d2 != deviceId) {
      return "تم استخدام هذا الكود على جهازين. لا يمكن تفعيل جهاز ثالث.";
    }

    // حفظ بيانات التفعيل
    await prefs.setBool(keyActivated, true);
    await prefs.setString(keyActivatedCode, code);
    await prefs.setString(keyActivationExpiry, expiryDate.toIso8601String());

    return null; // null → يعني نجاح التفعيل
  }

  // ---------------------------------------------------------------------------
  // هل التطبيق مفعّل؟
  // ---------------------------------------------------------------------------
  Future<bool> isActivated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyActivated) ?? false;
  }

  // ---------------------------------------------------------------------------
  // هل انتهى الاشتراك؟
  // ---------------------------------------------------------------------------
  Future<bool> isActivationExpired() async {
    final prefs = await SharedPreferences.getInstance();

    final expiryStr = prefs.getString(keyActivationExpiry);
    if (expiryStr == null) return true;

    final expiry = DateTime.parse(expiryStr);
    final now = DateTime.now();

    return now.isAfter(expiry);
  }

  // ---------------------------------------------------------------------------
  // الحالة النهائية لتشغيل التطبيق
  // ---------------------------------------------------------------------------
  Future<LicenseState> getAppState() async {
    // اكتشاف التلاعب بالوقت
    if (await _detectTimeTampering()) {
      return LicenseState.trialExpired;
    }

    // بدء التجربة إذا أول مرة
    await startTrialIfNeeded();

    // إذا مفعّل
    if (await isActivated()) {
      if (await isActivationExpired()) {
        return LicenseState.activationExpired;
      }
      return LicenseState.activated;
    }

    // إذا غير مفعّل → نرجع trial
    if (await isTrialExpired()) {
      return LicenseState.trialExpired;
    }

    return LicenseState.trial;
  }
}

// -----------------------------------------------------------------------------
// ENUM لحالة التطبيق
// -----------------------------------------------------------------------------
enum LicenseState {
  trial, // فترة تجريبية
  trialExpired, // انتهت التجربة
  activated, // مفعّل
  activationExpired, // انتهى الاشتراك
}
