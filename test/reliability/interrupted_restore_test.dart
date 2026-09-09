import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/restore_file_journal.dart';

String dartExecutable() {
  var folder = Directory(p.dirname(Platform.resolvedExecutable));
  while (folder.parent.path != folder.path) {
    final executable = File(p.join(folder.path, 'dart-sdk', 'bin',
        Platform.isWindows ? 'dart.exe' : 'dart'));
    if (executable.existsSync()) return executable.path;
    folder = folder.parent;
  }
  throw StateError('Cannot locate Flutter bundled Dart SDK');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'killed restore process rolls back database, replaced and new attachments on startup',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('restore_kill_');
    final live = '${temp.path}/live.db';
    final candidate = '${temp.path}/candidate.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: live);
    await db.insert('clients', {'name': 'Original', 'type': 'individual'});
    await db.close();
    await File(live).copy(candidate);
    db = await databaseFactoryFfi.openDatabase(candidate);
    await db.update('clients', {'name': 'Restored'});
    await db.close();
    final media = File('${temp.path}/logo.png');
    await media.writeAsString('original');
    final replacement = File('${temp.path}/new.png');
    await replacement.writeAsString('replacement');
    Process? process;
    try {
      process = await Process.start(dartExecutable(), [
        '--packages=.dart_tool/package_config.json',
        'test/reliability/support/interrupted_restore.dart',
        live,
        candidate,
        media.path,
        replacement.path
      ]);
      final errors = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(errors.write);
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'READY')
          .timeout(const Duration(seconds: 30),
              onTimeout: () =>
                  throw StateError('Child did not start: $errors'));
      expect(process.kill(), isTrue);
      await process.exitCode;
      db = await DatabaseMigration.initDatabase(pathOverride: live);
      expect((await db.query('clients')).single['name'], 'Original');
      await db.close();
      expect(await media.readAsString(), 'original');
      expect(await File('${media.path}.new').exists(), isFalse);
      // A committed restore must remain installed on subsequent startup.
      final journal = await RestoreFileJournal.begin(live);
      await journal.replace(File(candidate), live);
      await journal.replace(replacement, media.path);
      await journal.commit();
      db = await DatabaseMigration.initDatabase(pathOverride: live);
      expect((await db.query('clients')).single['name'], 'Restored');
      expect(await media.readAsString(), 'replacement');
    } finally {
      process?.kill();
      if (db.isOpen) await db.close();
      await temp.delete(recursive: true);
    }
  });
}
