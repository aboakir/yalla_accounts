// -----------------------------------------------------------------------------
// 📁 lib/core/licensing/license_storage.dart
// Central License Storage (Local & Persistent)
// -----------------------------------------------------------------------------

import 'package:shared_preferences/shared_preferences.dart';

class LicenseStorage {
  static const String _kDeviceId = 'license_device_id';
  static const String _kLicenseStatus = 'license_status';

  /// Save device fingerprint
  static Future<void> saveDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceId, deviceId);
  }

  /// Get stored device fingerprint
  static Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDeviceId);
  }

  /// Save license status (trial / expired / activated)
  static Future<void> saveLicenseStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLicenseStatus, status);
  }

  /// Get license status
  static Future<String?> getLicenseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLicenseStatus);
  }

  /// Clear all license data (NOT exposed to UI)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kLicenseStatus);
  }
}
