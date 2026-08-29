// -----------------------------------------------------------------------------
// 📁 lib/core/licensing/device_fingerprint.dart
// Device Fingerprint — Stable Local Machine Identifier (Windows-friendly)
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class DeviceFingerprint {
  static const String _fingerprintFile = '.yalla_device_id';

  /// Returns stable device fingerprint (hashed)
  static Future<String> getFingerprint() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_fingerprintFile');

    if (await file.exists()) {
      return await file.readAsString();
    }

    final raw = await _collectRawData();
    final hash = sha256.convert(utf8.encode(raw)).toString();

    await file.create(recursive: true);
    await file.writeAsString(hash, flush: true);

    return hash;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Future<String> _collectRawData() async {
    final buffer = StringBuffer();

    buffer.write(Platform.operatingSystem);
    buffer.write('|');
    buffer.write(Platform.numberOfProcessors);
    buffer.write('|');
    buffer.write(Platform.version);
    buffer.write('|');
    buffer.write(Platform.localHostname);

    return buffer.toString();
  }
}
