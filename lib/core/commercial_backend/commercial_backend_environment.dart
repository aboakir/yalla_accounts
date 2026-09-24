import 'package:flutter/foundation.dart';

class CommercialBackendEnvironment {
  const CommercialBackendEnvironment._();

  static const _rawBaseUrl =
      String.fromEnvironment('YALLAH_COMMERCIAL_BACKEND_URL');

  static Uri? get baseUri {
    final raw = _rawBaseUrl.trim();
    return raw.isEmpty ? null : Uri.tryParse(raw);
  }

  static bool get enabled => baseUri != null;

  static bool get allowInsecureLoopback =>
      kDebugMode && const bool.fromEnvironment('YALLA_ALLOW_INSECURE_LOOPBACK');
}
