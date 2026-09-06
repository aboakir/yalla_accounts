import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/yalla_backup_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P16 encrypted backup codec round-trips multi-chunk data', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p16_codec_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final random = Random(160926);
    final bytes = List<int>.generate(
      YallaBackupCodec.chunkSize + 77777,
      (_) => random.nextInt(256),
    );
    final plain = File('${temp.path}/plain.bin');
    final encrypted = File('${temp.path}/backup.yallabackup');
    final restored = File('${temp.path}/restored.bin');
    await plain.writeAsBytes(bytes, flush: true);

    await YallaBackupCodec.encryptFile(
      input: plain,
      output: encrypted,
      password: 'Yalla-P16-Recovery-Password',
    );
    expect(await encrypted.readAsBytes(), isNot(equals(bytes)));

    await YallaBackupCodec.decryptFile(
      input: encrypted,
      output: restored,
      password: 'Yalla-P16-Recovery-Password',
    );
    expect(await restored.readAsBytes(), bytes);
  });

  test('P16 encrypted backup rejects a wrong recovery password', () async {
    final temp = await Directory.systemTemp.createTemp('yalla_p16_wrong_pw_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final plain = File('${temp.path}/plain.txt')
      ..writeAsStringSync('Yalla Accounts P16');
    final encrypted = File('${temp.path}/backup.yallabackup');
    final restored = File('${temp.path}/restored.txt');

    await YallaBackupCodec.encryptFile(
      input: plain,
      output: encrypted,
      password: 'Correct-P16-Password',
    );

    expect(
      () => YallaBackupCodec.decryptFile(
        input: encrypted,
        output: restored,
        password: 'Wrong-P16-Password!',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
