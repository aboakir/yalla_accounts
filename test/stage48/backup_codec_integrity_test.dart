import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/yalla_backup_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final rounds in [0, 0xffffffff]) {
    test('corrupt work-factor $rounds is rejected before key derivation',
        () async {
      final dir = await Directory.systemTemp.createTemp('stage48_codec_');
      try {
        final header = ByteData(8)
          ..setUint32(0, rounds)
          ..setUint32(4, YallaBackupCodec.chunkSize);
        final input = await File('${dir.path}/bad.yab').writeAsBytes([
          ...utf8.encode(YallaBackupCodec.magic),
          ...List.filled(16, 0),
          ...header.buffer.asUint8List()
        ]);
        await expectLater(
            YallaBackupCodec.decryptFile(
                input: input,
                output: File('${dir.path}/output'),
                password: 'irrelevant password'),
            throwsStateError);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }
  test('truncated encrypted stream is rejected', () async {
    final dir = await Directory.systemTemp.createTemp('stage48_codec_');
    try {
      final input = await File('${dir.path}/truncated.yab')
          .writeAsString(YallaBackupCodec.magic);
      await expectLater(
          YallaBackupCodec.decryptFile(
              input: input,
              output: File('${dir.path}/output'),
              password: 'irrelevant password'),
          throwsStateError);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
