import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// P16 encrypted backup container.
///
/// Format (big endian):
/// magic[8] | salt[16] | iterations(u32) | chunkSize(u32)
/// repeated: plainLen(u32) | nonce[12] | cipherLen(u32) | cipher | mac[16]
///
/// Every chunk is independently authenticated by AES-256-GCM. The password is
/// converted to a 256-bit key using PBKDF2-HMAC-SHA256.
class YallaBackupCodec {
  YallaBackupCodec._();

  static const String magic = 'YALLABK1';
  static const int iterations = 120000;
  static const int chunkSize = 4 * 1024 * 1024;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static Future<void> encryptFile({
    required File input,
    required File output,
    required String password,
  }) async {
    if (password.trim().length < 10) {
      throw ArgumentError('Backup password must be at least 10 characters.');
    }
    final salt = _randomBytes(_saltLength);
    final secretKey = await _deriveKey(password, salt);
    final aes = AesGcm.with256bits();

    final reader = await input.open();
    final writer = await output.open(mode: FileMode.write);
    try {
      await writer.writeFrom(utf8.encode(magic));
      await writer.writeFrom(salt);
      await writer.writeFrom(_u32(iterations));
      await writer.writeFrom(_u32(chunkSize));

      while (true) {
        final plain = await reader.read(chunkSize);
        if (plain.isEmpty) break;
        final nonce = _randomBytes(_nonceLength);
        final box = await aes.encrypt(
          plain,
          secretKey: secretKey,
          nonce: nonce,
        );
        await writer.writeFrom(_u32(plain.length));
        await writer.writeFrom(nonce);
        await writer.writeFrom(_u32(box.cipherText.length));
        await writer.writeFrom(box.cipherText);
        await writer.writeFrom(box.mac.bytes);
      }
      await writer.flush();
    } finally {
      await reader.close();
      await writer.close();
    }
  }

  static Future<void> decryptFile({
    required File input,
    required File output,
    required String password,
  }) async {
    final reader = await input.open();
    final writer = await output.open(mode: FileMode.write);
    try {
      final readMagic = utf8.decode(await _readExact(reader, 8));
      if (readMagic != magic) {
        throw StateError('هذا الملف ليس نسخة Yalla Backup مدعومة.');
      }
      final salt = await _readExact(reader, _saltLength);
      final rounds = _fromU32(await _readExact(reader, 4));
      final encodedChunkSize = _fromU32(await _readExact(reader, 4));
      if (rounds < 100000 || encodedChunkSize <= 0) {
        throw StateError('ترويسة النسخة الاحتياطية غير صالحة.');
      }
      final secretKey = await _deriveKey(password, salt, rounds: rounds);
      final aes = AesGcm.with256bits();
      final total = await input.length();

      while (await reader.position() < total) {
        final plainLen = _fromU32(await _readExact(reader, 4));
        if (plainLen <= 0 || plainLen > encodedChunkSize) {
          throw StateError('حجم كتلة النسخة الاحتياطية غير صالح.');
        }
        final nonce = await _readExact(reader, _nonceLength);
        final cipherLen = _fromU32(await _readExact(reader, 4));
        if (cipherLen <= 0 || cipherLen > encodedChunkSize + 64) {
          throw StateError('بيانات النسخة الاحتياطية تالفة.');
        }
        final cipher = await _readExact(reader, cipherLen);
        final mac = await _readExact(reader, _macLength);
        try {
          final plain = await aes.decrypt(
            SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
            secretKey: secretKey,
          );
          if (plain.length != plainLen) {
            throw StateError('طول كتلة النسخة الاحتياطية غير متطابق.');
          }
          await writer.writeFrom(plain);
        } on SecretBoxAuthenticationError {
          throw StateError(
            'تعذر فك النسخة: كلمة الحماية خاطئة أو الملف تعرض للتلف.',
          );
        }
      }
      await writer.flush();
    } finally {
      await reader.close();
      await writer.close();
    }
  }

  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int rounds = iterations,
  }) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: rounds,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static int _fromU32(List<int> bytes) =>
      ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0, Endian.big);

  static Future<Uint8List> _readExact(RandomAccessFile file, int count) async {
    final bytes = await file.read(count);
    if (bytes.length != count) {
      throw StateError('ملف النسخة الاحتياطية مبتور أو تالف.');
    }
    return Uint8List.fromList(bytes);
  }
}
