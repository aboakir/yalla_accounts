// -----------------------------------------------------------------------------
// 📁 lib/core/licensing/license_manager.dart
// Central License Decision Manager
// -----------------------------------------------------------------------------

import 'trial_manager.dart';

enum LicenseStatus {
  trialValid,
  trialExpired,
  activated,
}

class LicenseManager {
  /// Main entry point
  static Future<LicenseStatus> checkStatus() async {
    // 🔓 لاحقًا: لو فيه تفعيل دائم
    final activated = await _isActivated();
    if (activated) {
      return LicenseStatus.activated;
    }

    // ⏱️ Trial logic
    await TrialManager.ensureInitialized();

    final expired = await TrialManager.isExpired();
    if (expired) {
      return LicenseStatus.trialExpired;
    }

    return LicenseStatus.trialValid;
  }

  // ---------------------------------------------------------------------------
  // Activation (placeholder for paid license)
  // ---------------------------------------------------------------------------

  static Future<bool> _isActivated() async {
    // جاهزة للمرحلة القادمة
    return false;
  }
}
