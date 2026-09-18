import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Durable undo journal for a closed database and its restored attachments.
/// Recovery is repeatable if the process also stops during rollback.
class RestoreFileJournal {
  RestoreFileJournal._(this.livePath);
  final String livePath;
  Directory get directory => Directory('$livePath.restore-journal');
  static final Set<String> _active = {};
  int _sequence = 0;

  static Future<RestoreFileJournal> begin(String livePath) async {
    if (_active.contains(livePath)) throw StateError('Restore already running');
    await recover(livePath);
    final journal = RestoreFileJournal._(livePath);
    await journal.directory.create(recursive: true);
    _active.add(livePath);
    return journal;
  }

  Future<void> replace(File source, String destination) async {
    final target = File(destination);
    await target.parent.create(recursive: true);
    final index = _sequence++;
    final backup = File(p.join(directory.path, '$index.old'));
    final existed = await target.exists();
    if (existed) await _copyFlushed(target, backup);
    final staged = File('$destination.restore-next');
    await _copyFlushed(source, staged);
    // Record and flush the undo operation before modifying the destination.
    await File(p.join(directory.path, 'undo.jsonl')).writeAsString(
        '${jsonEncode({
              'target': destination,
              'backup': backup.path,
              'existed': existed
            })}\n',
        mode: FileMode.append,
        flush: true);
    if (await target.exists()) await target.delete();
    await staged.rename(destination);
  }

  static Future<void> _copyFlushed(File source, File target) async {
    final output = target.openWrite();
    try {
      await output.addStream(source.openRead());
      await output.flush();
    } finally {
      await output.close();
    }
  }

  static Future<void> _restoreAtomically(File backup, File target) async {
    if (!await backup.exists()) {
      throw StateError('Restore journal backup is missing: ${backup.path}');
    }

    await target.parent.create(recursive: true);
    final staged = File('${target.path}.restore-recover');
    if (await staged.exists()) await staged.delete();

    await _copyFlushed(backup, staged);

    if (await target.exists()) await target.delete();
    await staged.rename(target.path);
  }

  Future<void> commit() async {
    await File(p.join(directory.path, 'committed'))
        .writeAsString('ok', flush: true);
    _active.remove(livePath);
    await recover(livePath);
  }

  Future<void> rollback() async {
    _active.remove(livePath);
    await recover(livePath);
  }

  static Future<void> recover(String livePath) async {
    if (_active.contains(livePath)) return;
    final journal = RestoreFileJournal._(livePath);
    if (!await journal.directory.exists()) return;
    if (!await File(p.join(journal.directory.path, 'committed')).exists()) {
      final log = File(p.join(journal.directory.path, 'undo.jsonl'));
      if (await log.exists()) {
        final records = <Map<String, dynamic>>[];
        for (final line in (await log.readAsString()).split('\n')) {
          if (line.isEmpty) continue;
          try {
            records.add(jsonDecode(line) as Map<String, dynamic>);
          } on FormatException {
            break;
          } // Incomplete final record was never applied.
        }
        for (final row in records.reversed) {
          final target = File(row['target'] as String);
          if (row['existed'] == true) {
            await _restoreAtomically(
              File(row['backup'] as String),
              target,
            );
          } else if (await target.exists()) {
            await target.delete();
          }
          final staged = File('${target.path}.restore-next');
          if (await staged.exists()) await staged.delete();
          final recoveryStage = File('${target.path}.restore-recover');
          if (await recoveryStage.exists()) await recoveryStage.delete();
        }
        // WAL of the interrupted replacement must never be replayed on the old DB.
        for (final suffix in ['-wal', '-shm', '-journal']) {
          final sidecar = File('$livePath$suffix');
          if (await sidecar.exists()) await sidecar.delete();
        }
      }
    }
    await journal.directory.delete(recursive: true);
  }
}
