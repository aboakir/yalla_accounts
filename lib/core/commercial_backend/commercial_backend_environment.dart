import 'package:flutter/foundation.dart';

class CommercialBackendEnvironment {
  const CommercialBackendEnvironment._();

  static const _rawCommercialBaseUrl =
      String.fromEnvironment('YALLAH_COMMERCIAL_BACKEND_URL');
  static const _rawLicensingBaseUrl =
      String.fromEnvironment('YALLA_LICENSING_BASE_URL');

  static Uri? get baseUri {
    final commercial = _rawCommercialBaseUrl.trim();
    final raw =
        commercial.isNotEmpty ? commercial : _rawLicensingBaseUrl.trim();
    return raw.isEmpty ? null : Uri.tryParse(raw);
  }

  static bool get enabled => baseUri != null;

  static bool get allowInsecureLoopback =>
      kDebugMode && const bool.fromEnvironment('YALLA_ALLOW_INSECURE_LOOPBACK');
}
