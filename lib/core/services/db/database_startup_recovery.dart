import 'dart:io';
import 'package:sqflite/sqflite.dart';

/// Allows SQLite to recover its own interrupted rollback journal before the
/// read-only version probe. Never deletes journals or replays financial SQL.
class DatabaseStartupRecovery {
  DatabaseStartupRecovery._();

  static Future<bool> recoverIfNeeded(
    String path, {
    required Future<Database> Function() openWithoutMigration,
  }) async {
    if (!await File(path).exists()) return false;
    final journal = File('$path-journal');
    if (!await journal.exists() || await journal.length() <= 512) return false;

    // Only SQLite decides whether a journal is hot and owns the locking,
    // rollback, synchronization and journal cleanup sequence.
    final db = await openWithoutMigration();
    try {
      final integrity = await db.rawQuery('PRAGMA quick_check');
      if (integrity.length != 1 ||
          integrity.single.values.single.toString().toLowerCase() != 'ok') {
        throw StateError('STARTUP_RECOVERY_INTEGRITY_FAILED');
      }
    } finally {
      if (db.isOpen) await db.close();
    }
    return true;
  }
}
