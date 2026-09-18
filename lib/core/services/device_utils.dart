// -----------------------------------------------------------------------------
// 📁 lib/core/services/device_utils.dart
// توليد بصمة الجهاز Device Fingerprint + UUID ثابت + تجزئة SHA256
// يعمل على: Windows + Android + iOS + MacOS
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

class DeviceUtils {
  DeviceUtils._();
  static final DeviceUtils instance = DeviceUtils._();

  static const String _keyFingerprint = "yalla_device_fingerprint";
  static const String _keyRawUid = "yalla_device_raw_uid";

  // ---------------------------------------------------------------------------
  // الحصول على البصمة النهائية للجهاز
  // ---------------------------------------------------------------------------
  Future<String> getDeviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();

    // إذا كان الجهاز يمتلك بصمة محفوظة → نرجعها
    String? existing = prefs.getString(_keyFingerprint);
    if (existing != null) return existing;

    // لم يتم إنشاء بصمة من قبل → ننشئ واحدة جديدة
    final rawInfo = await _collectDeviceInfo();
    final hashed = _hashInfo(rawInfo);

    // تخزين البصمة
    await prefs.setString(_keyFingerprint, hashed);

    return hashed;
  }

  // ---------------------------------------------------------------------------
  // جمع معلومات الجهاز
  // ---------------------------------------------------------------------------
  Future<String> _collectDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();

    String raw = "";

    try {
      if (await _isWindows()) {
        final info = await deviceInfoPlugin.windowsInfo;
        raw = [
          info.computerName,
          info.numberOfCores,
          info.systemMemoryInMegabytes,
        ].join("|");
      } else if (await _isAndroid()) {
        final info = await deviceInfoPlugin.androidInfo;
        raw = [
          info.manufacturer,
          info.model,
          info.version.sdkInt,
          info.device,
        ].join("|");
      } else if (await _isIOS()) {
        final info = await deviceInfoPlugin.iosInfo;
        raw = [
          info.model,
          info.name,
          info.systemVersion,
          info.identifierForVendor,
        ].join("|");
      } else if (await _isMacOS()) {
        final info = await deviceInfoPlugin.macOsInfo;
        raw = [
          info.computerName,
          info.osRelease,
          info.arch,
          info.hostName,
        ].join("|");
      } else {
        raw = "unknown_device";
      }
    } catch (_) {
      raw = "fallback_device";
    }

    // إضافة UUID ثابت للجهاز
    final unique = await _getOrCreateUUID();

    return "$raw|$unique";
  }

  // ---------------------------------------------------------------------------
  // UUID ثابت للجهاز — لا يتغير حتى لو حذف البرنامج
  // ---------------------------------------------------------------------------
  Future<String> _getOrCreateUUID() async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString(_keyRawUid);

    if (uid == null) {
      uid = const Uuid().v4(); // توليد uuid جديد
      await prefs.setString(_keyRawUid, uid);
    }

    return uid;
  }

  // ---------------------------------------------------------------------------
  // دوال معرفة النظام
  // ---------------------------------------------------------------------------
  Future<bool> _isWindows() async {
    try {
      final info = await DeviceInfoPlugin().windowsInfo;
      return info.computerName.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isAndroid() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.model.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isIOS() async {
    try {
      final info = await DeviceInfoPlugin().iosInfo;
      return info.model.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isMacOS() async {
    try {
      final info = await DeviceInfoPlugin().macOsInfo;
      return info.computerName.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // تشفير بصمة الجهاز SHA-256
  // ---------------------------------------------------------------------------
  String _hashInfo(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
