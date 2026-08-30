import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class PasswordVerification {
  final bool isValid;
  final bool needsUpgrade;

  const PasswordVerification({
    required this.isValid,
    required this.needsUpgrade,
  });
}

/// P1.002 canonical password/secret hashing.
///
/// New credentials use salted PBKDF2-HMAC-SHA256. Legacy unsalted SHA-256
/// values remain verifiable only so an existing customer is not locked out;
/// after a successful legacy login the password is immediately re-hashed.
class PasswordHasher {
  static const String scheme = 'pbkdf2_sha256';
  static const int iterations = 120000;
  static const int _saltBytes = 16;

  static String hash(String value) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => random.nextInt(256)),
    );
    final derived = _pbkdf2(value, salt, iterations);

    return [
      scheme,
      iterations.toString(),
      base64UrlEncode(salt),
      base64UrlEncode(derived),
    ].join(r'$');
  }

  static PasswordVerification verify(String value, String stored) {
    if (stored.startsWith('$scheme\$')) {
      final parts = stored.split(r'$');
      if (parts.length != 4) {
        return const PasswordVerification(
          isValid: false,
          needsUpgrade: false,
        );
      }

      final rounds = int.tryParse(parts[1]);
      if (rounds == null || rounds < 10000) {
        return const PasswordVerification(
          isValid: false,
          needsUpgrade: false,
        );
      }

      try {
        final salt = Uint8List.fromList(base64Url.decode(parts[2]));
        final expected = Uint8List.fromList(base64Url.decode(parts[3]));
        final actual = _pbkdf2(value, salt, rounds);

        return PasswordVerification(
          isValid: _constantTimeBytes(expected, actual),
          needsUpgrade: rounds < iterations,
        );
      } catch (_) {
        return const PasswordVerification(
          isValid: false,
          needsUpgrade: false,
        );
      }
    }

    if (isLegacySha256(stored)) {
      final actual = sha256.convert(utf8.encode(value)).toString();
      return PasswordVerification(
        isValid: _constantTimeText(stored.toLowerCase(), actual),
        needsUpgrade: true,
      );
    }

    return const PasswordVerification(
      isValid: false,
      needsUpgrade: false,
    );
  }

  static bool isLegacySha256(String stored) {
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(stored);
  }

  static String legacySha256ForTest(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static Uint8List _pbkdf2(
    String value,
    Uint8List salt,
    int rounds,
  ) {
    final mac = Hmac(sha256, utf8.encode(value));

    final firstBlock = Uint8List(salt.length + 4);
    firstBlock.setRange(0, salt.length, salt);
    firstBlock[salt.length] = 0;
    firstBlock[salt.length + 1] = 0;
    firstBlock[salt.length + 2] = 0;
    firstBlock[salt.length + 3] = 1;

    var u = Uint8List.fromList(mac.convert(firstBlock).bytes);
    final output = Uint8List.fromList(u);

    for (var round = 1; round < rounds; round++) {
      u = Uint8List.fromList(mac.convert(u).bytes);
      for (var i = 0; i < output.length; i++) {
        output[i] = output[i] ^ u[i];
      }
    }

    return output;
  }

  static bool _constantTimeBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static bool _constantTimeText(String a, String b) {
    return _constantTimeBytes(utf8.encode(a), utf8.encode(b));
  }
}
