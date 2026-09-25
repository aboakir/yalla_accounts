import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceFingerprintSnapshot {
  const DeviceFingerprintSnapshot({
    required this.sha256Hex,
    required this.platform,
    required this.appVersion,
    this.platformVersion,
  });

  final String sha256Hex;
  final String platform;
  final String? platformVersion;
  final String appVersion;
}

abstract class DeviceFingerprintProvider {
  Future<DeviceFingerprintSnapshot> collect();
}

class DefaultDeviceFingerprintProvider implements DeviceFingerprintProvider {
  DefaultDeviceFingerprintProvider({
    DeviceInfoPlugin? deviceInfo,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  static const _preferredStableKeys = <String>{
    'deviceId',
    'id',
    'identifierForVendor',
    'machine',
    'model',
    'manufacturer',
    'productName',
    'board',
    'hardware',
    'host',
    'computerName',
  };

  @override
  Future<DeviceFingerprintSnapshot> collect() async {
    final info = await _deviceInfo.deviceInfo;
    final selected = <String, String>{};

    for (final entry in info.data.entries) {
      if (!_preferredStableKeys.contains(entry.key)) continue;
      final value = _clean(entry.value);
      if (value != null) selected[entry.key] = value;
    }

    // Best-effort fallback only. The fingerprint is a risk signal, not the
    // cryptographic device identity and never authorizes a license by itself.
    if (kIsWeb) {
      for (final key in const [
        'browserName',
        'platform',
        'userAgent',
        'vendor'
      ]) {
        final value = _clean(info.data[key]);
        if (value != null) selected['web_$key'] = value;
      }
      if (selected.isEmpty) selected['web_runtime'] = 'browser';
    } else if (selected.isEmpty) {
      selected['os'] = Platform.operatingSystem;
      selected['computer'] =
          Platform.environment['COMPUTERNAME']?.trim() ?? 'unknown';
      selected['processor'] =
          Platform.environment['PROCESSOR_IDENTIFIER']?.trim() ?? 'unknown';
      selected['arch'] =
          Platform.environment['PROCESSOR_ARCHITECTURE']?.trim() ?? 'unknown';
    }

    final keys = selected.keys.toList()..sort();
    final canonical = keys.map((k) => '$k=${selected[k]}').join('\n');
    final digest = sha256.convert(utf8.encode(canonical)).toString();

    final package = await PackageInfo.fromPlatform();
    final build = package.buildNumber.trim();
    final appVersion = build.isEmpty
        ? package.version.trim()
        : '${package.version.trim()}+$build';

    return DeviceFingerprintSnapshot(
      sha256Hex: digest,
      platform: kIsWeb ? 'web' : Platform.operatingSystem,
      platformVersion: kIsWeb
          ? _clean(info.data['userAgent'])
          : Platform.operatingSystemVersion.trim(),
      appVersion: appVersion,
    );
  }

  static String? _clean(Object? value) {
    if (value == null || value is Map || value is Iterable) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.length > 256) return null;
    return text;
  }
}
