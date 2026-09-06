import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_encryption_service.dart';
import 'package:yalla_accounts/core/services/db/tables/p16_security_tables.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/settings/services/backup_key_store.dart';

class WindowsMigrationService {
  WindowsMigrationService._();

  static Future<String?> importDatabaseFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['db'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return null;
    return importDatabaseFromPath(path);
  }

  static Future<String?> importFolderFromPicker() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد Yalla Accounts القديم من Windows',
    );
    if (folder == null || folder.trim().isEmpty) return null;
    final root = Directory(folder);
    if (!await root.exists()) throw StateError('المجلد المحدد غير موجود.');

    File? candidate;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).toLowerCase() ==
              DatabaseConstants.dbName.toLowerCase()) {
        candidate = entity;
        break;
      }
    }
    if (candidate == null) {
      throw StateError(
          'لم يتم العثور على ${DatabaseConstants.dbName} داخل المجلد.');
    }

    final recoveryPassword = await BackupKeyStore.readPassword();
    if (recoveryPassword == null) {
      throw StateError(
        'عيّن كلمة حماية النسخ الاحتياطية أولًا قبل استيراد مجلد Windows.',
      );
    }
    final fullSafety = await BackupService.createEncryptedBackup(
      password: recoveryPassword,
      kind: 'pre_windows_folder_import',
    );
    try {
      final live = await importDatabaseFromPath(candidate.path);
      final storageRoot = await YallaStorageService.rootDirectory();
      await _copyKnownMedia(root, storageRoot, candidate.path);
      return live;
    } catch (_) {
      await BackupService.restoreEncryptedFromPath(
        fullSafety.path,
        password: recoveryPassword,
      );
      rethrow;
    }
  }

  static Future<String> importDatabaseFromPath(String sourcePath) async {
    final actor =
        await AuthorizationGuard.require(PermissionKeys.windowsImport);
    final source = File(sourcePath);
    if (!await source.exists())
      throw StateError('قاعدة Windows المحددة غير موجودة.');
    final livePath = await BackupService.currentDbPath();
    if (p.equals(p.absolute(source.path), p.absolute(livePath))) {
      throw StateError(
          'اختر قاعدة Windows قديمة، وليس قاعدة البيانات الحالية.');
    }

    await BackupService.validateDatabaseCandidate(source.path);
    final sourceVersion = await _readDbVersion(source.path);
    final safety = await BackupService.makeBackup();
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final runId = await db.insert('windows_import_runs', {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source_path': source.path,
      'source_db_version': sourceVersion,
      'safety_backup_path': safety,
      'status': 'STARTED',
      'note': 'Full database replacement; no blind merge.',
    });

    try {
      final restored = await BackupService.restoreFromPath(source.path);
      final reopened = await DBService.database;
      await P16SecurityTables.ensure(reopened);
      await reopened.update(
        'windows_import_runs',
        {'status': 'PASS'},
        where: 'id = ?',
        whereArgs: [runId],
      );
      await AuditTrailService.log(
        actorUserId: actor?.id,
        actorRole: actor?.role,
        action: 'WINDOWS_DATA_IMPORTED',
        entityType: 'DATABASE',
        entityId: p.basename(source.path),
        after: {'source_db_version': sourceVersion, 'safety_backup': safety},
      );
      return restored;
    } catch (e) {
      try {
        final reopened = await DBService.database;
        await P16SecurityTables.ensure(reopened);
        await reopened.update(
          'windows_import_runs',
          {'status': 'FAILED', 'note': e.toString()},
          where: 'id = ?',
          whereArgs: [runId],
        );
      } catch (_) {}
      rethrow;
    }
  }

  static Future<int> _readDbVersion(String path) async {
    final db = await DatabaseEncryptionService.openReadOnlyCandidate(path);
    try {
      return Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ??
          0;
    } finally {
      await db.close();
    }
  }

  static Future<void> _copyKnownMedia(
    Directory sourceRoot,
    Directory storageRoot,
    String databasePath,
  ) async {
    const knownTop = <String>{
      'repairs',
      'insurance',
      'documents',
      'employee_images',
      'repair_intake_photos',
      'repair_signatures',
    };
    await for (final entity
        in sourceRoot.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.equals(p.absolute(entity.path), p.absolute(databasePath))) continue;
      final rel = p.relative(entity.path, from: sourceRoot.path);
      final first = rel.split(Platform.pathSeparator).first.toLowerCase();
      if (!knownTop.contains(first)) continue;
      final out = File(p.join(storageRoot.path, rel));
      await out.parent.create(recursive: true);
      await entity.copy(out.path);
    }
  }
}
