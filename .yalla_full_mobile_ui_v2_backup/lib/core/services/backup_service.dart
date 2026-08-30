// 📁 lib/core/services/backup_service.dart
//
// P1.001 — safe commercial backup / restore.
//
// - backup never deletes/resets the live DB;
// - WAL is checkpointed before copying;
// - restore validates the candidate before replacement;
// - a safety backup is created before restore;
// - failed restore rolls the original DB back.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static Future<String> currentDbPath() => DBService.dbFilePath();

  static Future<String> makeBackup({bool alsoShare = false}) async {
    final srcPath = await currentDbPath();
    final srcFile = File(srcPath);

    if (!await srcFile.exists()) {
      throw StateError('Database file not found at $srcPath');
    }

    final docs = await getApplicationDocumentsDirectory();
    final backupDir = Directory(
      p.join(docs.path, 'Yalla Accounts', 'Backups'),
    );
    await backupDir.create(recursive: true);

    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final dst = p.join(
      backupDir.path,
      'yalla_accounts_backup_v${DatabaseConstants.dbVersion}_$ts.db',
    );

    await DBService.closeDatabase(checkpoint: true);

    try {
      await srcFile.copy(dst);
    } finally {
      await DBService.reopenDatabase();
    }

    await _validateCandidate(dst);

    if (alsoShare) {
      await Share.shareXFiles(
        [XFile(dst)],
        text: 'Yalla Accounts Backup ($ts)',
      );
    }

    return dst;
  }

  static Future<void> shareLatestBackupIfAny() async {
    final docs = await getApplicationDocumentsDirectory();
    final backupDir = Directory(
      p.join(docs.path, 'Yalla Accounts', 'Backups'),
    );

    if (!await backupDir.exists()) {
      throw StateError('لا توجد نسخة احتياطية سابقة.');
    }

    final files = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.db'))
        .toList()
      ..sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

    if (files.isEmpty) {
      throw StateError('لا توجد نسخة احتياطية سابقة.');
    }

    await Share.shareXFiles(
      [XFile(files.first.path)],
      text: 'Latest Yalla Accounts Backup',
    );
  }

  static Future<String?> restoreFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      allowMultiple: false,
      withReadStream: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final pickedPath = result.files.single.path;
    if (pickedPath == null || pickedPath.trim().isEmpty) return null;

    return restoreFromPath(pickedPath);
  }

  static Future<String> restoreFromPath(String candidatePath) async {
    final candidate = File(candidatePath);
    if (!await candidate.exists()) {
      throw StateError('Backup file not found: $candidatePath');
    }

    await _validateCandidate(candidatePath);

    final safetyBackup = await makeBackup();
    final livePath = await currentDbPath();

    await DBService.closeDatabase(checkpoint: true);

    try {
      await _removeSidecars(livePath);
      await candidate.copy(livePath);

      // Normal production open performs any supported DB upgrade.
      await DBService.reopenDatabase();
      return livePath;
    } catch (restoreError) {
      await DBService.closeDatabase(checkpoint: false);

      try {
        await _removeSidecars(livePath);
        await File(safetyBackup).copy(livePath);
        await DBService.reopenDatabase();
      } catch (rollbackError) {
        throw StateError(
          'Restore failed ($restoreError) and rollback also failed '
          '($rollbackError). Safety backup: $safetyBackup',
        );
      }

      rethrow;
    }
  }

  static Future<void> _validateCandidate(String path) async {
    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw StateError('Backup integrity_check failed: $integrity');
      }

      final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeys.isNotEmpty) {
        throw StateError(
          'Backup contains foreign-key violations: $foreignKeys',
        );
      }

      final version = Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA user_version'),
          ) ??
          0;

      if (version <= 0 || version > DatabaseConstants.dbVersion) {
        throw StateError(
          'Unsupported backup DB version $version. '
          'Current supported version is ${DatabaseConstants.dbVersion}.',
        );
      }

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      for (final required in const [
        'users',
        'repairs',
        'accounts',
        'gl_entries',
        'gl_lines',
      ]) {
        if (!names.contains(required)) {
          throw StateError(
            'Backup is not a Yalla Accounts database: '
            'missing table $required.',
          );
        }
      }
    } finally {
      await db.close();
    }
  }

  static Future<void> _removeSidecars(String livePath) async {
    for (final suffix in const ['-wal', '-shm']) {
      final file = File('$livePath$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
