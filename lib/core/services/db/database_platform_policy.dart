// Central cross-platform SQLite runtime policy for Yallah Accounts.
//
// This is the ONLY owner of runtime tuning PRAGMAs.
// iOS/SqfliteDarwin receives correctness-critical foreign_keys only.
// Windows/Android/other supported non-iOS platforms preserve the effective
// existing policy: WAL + synchronous NORMAL + busy_timeout 8000.
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class DatabasePlatformPolicy {
  DatabasePlatformPolicy._();

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');

    // Browser SQLite runs behind the sqflite web worker/IndexedDB VFS.
    // Do not force WAL/checkpoint tuning that assumes a filesystem-backed DB.
    if (kIsWeb) return;

    // SqfliteDarwin can surface Code=0 "not an error" for runtime tuning
    // PRAGMAs during database open. Do not force those PRAGMAs on iOS.
    if (isIOS) return;

    await db.rawQuery('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA synchronous = NORMAL;');

    // main.dart historically applied 8000 after DatabaseMigration's 5000,
    // so 8000 is the effective Desktop/Android behavior being preserved.
    await db.rawQuery('PRAGMA busy_timeout = 8000;');
  }

  static Future<void> checkpoint(
    Database db, {
    String mode = 'TRUNCATE',
  }) async {
    if (kIsWeb || isIOS) return;

    final normalized = mode.toUpperCase();
    const allowed = {'PASSIVE', 'FULL', 'RESTART', 'TRUNCATE'};
    if (!allowed.contains(normalized)) {
      throw ArgumentError.value(
          mode, 'mode', 'Unsupported WAL checkpoint mode');
    }

    await db.rawQuery('PRAGMA wal_checkpoint($normalized)');
  }
}
