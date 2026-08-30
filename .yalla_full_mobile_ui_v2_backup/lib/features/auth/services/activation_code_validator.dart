class ActivationCodeData {
  final DateTime expiry;
  final int maxDevices;
  final String code;
  final String hash;

  ActivationCodeData({
    required this.expiry,
    required this.maxDevices,
    required this.code,
    required this.hash,
  });
}

/// P1.002: the legacy offline activation format is non-authoritative.
///
/// It embedded a signing secret inside the customer application. Commercial
/// licensing will use a separate signed/server-verified design in a later P1
/// task. Authentication and access to existing financial data never depend on
/// this legacy validator.
class ActivationCodeValidator {
  static ActivationCodeData? decode(String code) {
    final parts = code.split(':');
    if (parts.length != 4) return null;

    final expiry = DateTime.tryParse(parts[1]);
    if (expiry == null) return null;

    return ActivationCodeData(
      expiry: expiry,
      maxDevices: int.tryParse(parts[2]) ?? 1,
      code: parts[0],
      hash: parts[3],
    );
  }

  static String generateHash({
    required String code,
    required DateTime expiry,
    required int maxDevices,
  }) {
    throw UnsupportedError(
      'Legacy client-side activation signing is disabled.',
    );
  }

  static bool verifyHash(ActivationCodeData data) => false;

  static String? validateActivationCode(String inputCode) {
    return 'نظام التفعيل المحلي القديم متوقف. '
        'لا يؤثر ذلك على الوصول إلى بياناتك المحاسبية.';
  }
}
