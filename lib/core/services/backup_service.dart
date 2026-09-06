// lib/core/services/backup_service.dart
// P16 — full encrypted offline-first backup / disaster recovery.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_encryption_service.dart';
import 'package:yalla_accounts/core/services/db/tables/p16_security_tables.dart';
import 'package:yalla_accounts/core/services/yalla_backup_codec.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';

class EncryptedBackupResult {
  const EncryptedBackupResult({
    required this.path,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.createdAt,
    required this.kind,
    required this.fileCount,
  });

  final String path;
  final int sizeBytes;
  final String sha256Hex;
  final DateTime createdAt;
  final String kind;
  final int fileCount;

  double get sizeMb => sizeBytes / (1024 * 1024);
}

class BackupManifest {
  const BackupManifest({required this.map});
  final Map<String, dynamic> map;

  int get formatVersion => (map['format_version'] as num?)?.toInt() ?? 0;
  int get dbVersion => (map['db_version'] as num?)?.toInt() ?? 0;
  String get oldStorageRoot => map['storage_root']?.toString() ?? '';
  String get oldAppDocumentsRoot => map['app_documents_root']?.toString() ?? '';
  List<dynamic> get files => (map['files'] as List?) ?? const [];
  List<dynamic> get externalReferences =>
      (map['external_references'] as List?) ?? const [];
}

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const int backupFormatVersion = 1;
  static const int weeklyRetention = 4;
  static const int emailAttachmentAdvisoryBytes = 20 * 1024 * 1024;

  static Future<String> currentDbPath() => DBService.dbFilePath();

  // -----------------------------------------------------------------------
  // Legacy DB-only methods kept for old maintenance screens and internal
  // safety snapshots. P16 commercial recovery uses .yallabackup below.
  // -----------------------------------------------------------------------
  static Future<String> makeBackup({bool alsoShare = false}) async {
    await AuthorizationGuard.require(PermissionKeys.backupCreate);
    final srcPath = await currentDbPath();
    final srcFile = File(srcPath);
    if (!await srcFile.exists()) {
      throw StateError('Database file not found at $srcPath');
    }

    final docs = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docs.path, 'Yalla Accounts', 'Backups'));
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
    await validateDatabaseCandidate(dst);

    if (alsoShare) {
      await Share.shareXFiles([XFile(dst)], text: 'Yalla Accounts DB Backup');
    }
    return dst;
  }

  static Future<void> shareLatestBackupIfAny() async {
    await AuthorizationGuard.require(PermissionKeys.backupExport);
    final latest = await latestEncryptedBackup();
    if (latest != null) {
      await shareEncryptedBackup(latest.path);
      return;
    }

    final docs = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docs.path, 'Yalla Accounts', 'Backups'));
    if (!await backupDir.exists())
      throw StateError('لا توجد نسخة احتياطية سابقة.');
    final files = backupDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.db'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (files.isEmpty) throw StateError('لا توجد نسخة احتياطية سابقة.');
    await Share.shareXFiles([XFile(files.first.path)],
        text: 'Yalla Accounts Backup');
  }

  // -----------------------------------------------------------------------
  // P16 complete encrypted backup.
  // -----------------------------------------------------------------------
  static Future<EncryptedBackupResult> createEncryptedBackup({
    required String password,
    String kind = 'manual',
    String? targetEmail,
    bool shareAfterCreate = false,
  }) async {
    final actor = await AuthorizationGuard.require(PermissionKeys.backupCreate);
    var db = await DBService.database;
    await P16SecurityTables.ensure(db);

    final createdAt = DateTime.now().toUtc();
    final tempRoot = await getTemporaryDirectory();
    final temp = await Directory(
      p.join(tempRoot.path, 'yalla_backup_${createdAt.microsecondsSinceEpoch}'),
    ).create(recursive: true);
    final staging = await Directory(p.join(temp.path, 'staging')).create();
    final zipPath = p.join(temp.path, 'payload.zip');

    try {
      final dbSnapshot = File(p.join(staging.path, DatabaseConstants.dbName));
      await _copyLiveDatabaseTo(dbSnapshot.path);
      await validateDatabaseCandidate(dbSnapshot.path);

      // _copyLiveDatabaseTo checkpoints/closes/reopens SQLite. Never retain the
      // old Database handle across that boundary.
      db = await DBService.database;
      await P16SecurityTables.ensure(db);

      final storageRoot = await YallaStorageService.rootDirectory();
      final appDocs = await getApplicationDocumentsDirectory();
      final files = <Map<String, Object?>>[];
      final externalRefs = <Map<String, Object?>>[];
      final zipInputs = <_ZipInput>[];

      await _addFile(
          zipInputs, files, dbSnapshot, 'database/${DatabaseConstants.dbName}');

      await _collectDirectory(
        storageRoot,
        prefix: 'storage',
        excludeTopLevel: const {'backups'},
        zipInputs: zipInputs,
        manifestFiles: files,
      );

      const legacyAppDocFolders = <String>{
        'repair_intake_photos',
        'repair_signatures',
        'employee_images',
      };
      for (final legacy in legacyAppDocFolders) {
        final dir = Directory(p.join(appDocs.path, legacy));
        if (await dir.exists()) {
          await _collectDirectory(
            dir,
            prefix: 'app_documents/$legacy',
            zipInputs: zipInputs,
            manifestFiles: files,
          );
        }
      }

      final referenced = await _collectReferencedMedia(db);
      var externalIndex = 0;
      for (final originalPath in referenced) {
        final resolved =
            await YallaStorageService.resolveExistingPath(originalPath) ??
                (await File(originalPath).exists() ? originalPath : null);
        if (resolved == null) continue;
        if (_isWithinOrEqual(storageRoot.path, resolved)) {
          continue;
        }
        final alreadyCollectedFromAppDocs = legacyAppDocFolders.any(
          (folder) => _isWithinOrEqual(p.join(appDocs.path, folder), resolved),
        );
        if (alreadyCollectedFromAppDocs) continue;
        final file = File(resolved);
        final archivePath =
            'external_media/${externalIndex++}_${_safeName(p.basename(resolved))}';
        await _addFile(zipInputs, files, file, archivePath);
        externalRefs.add({
          'original_path': originalPath,
          'archive_path': archivePath,
        });
      }

      final manifest = <String, Object?>{
        'product': 'Yalla Accounts',
        'format': 'YALLA_BACKUP',
        'format_version': backupFormatVersion,
        'created_at': createdAt.toIso8601String(),
        'db_version': DatabaseConstants.dbVersion,
        'storage_root': storageRoot.path,
        'app_documents_root': appDocs.path,
        'includes_media': true,
        'files': files,
        'external_references': externalRefs,
      };
      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );
      await _addFile(
          zipInputs, <Map<String, Object?>>[], manifestFile, 'manifest.json');

      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      try {
        for (final input in zipInputs) {
          await encoder.addFile(input.file, input.archivePath);
        }
      } finally {
        await encoder.close();
      }

      final backupDir = Directory(p.join(storageRoot.path, 'backups'));
      await backupDir.create(recursive: true);
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(createdAt.toLocal());
      final safeKind = _safeName(kind.toLowerCase());
      final out = File(p.join(
          backupDir.path, 'Yalla_Backup_${safeKind}_$stamp.yallabackup'));
      await YallaBackupCodec.encryptFile(
        input: File(zipPath),
        output: out,
        password: password,
      );

      final validation = await validateEncryptedBackup(
        out.path,
        password: password,
        fullChecksumValidation: true,
      );
      final hash = await _sha256File(out);
      final size = await out.length();

      await db.insert('backup_runs', {
        'created_at': createdAt.toIso8601String(),
        'kind': kind,
        'local_path': out.path,
        'status': 'VALIDATED',
        'size_bytes': size,
        'db_version': validation.dbVersion,
        'file_sha256': hash,
        'includes_media': 1,
        'manifest_json': jsonEncode(validation.map),
      });

      await AuditTrailService.log(
        actorUserId: actor?.id,
        actorRole: actor?.role,
        action: 'BACKUP_CREATED',
        entityType: 'BACKUP',
        entityId: p.basename(out.path),
        after: {'kind': kind, 'size_bytes': size, 'sha256': hash},
      );

      if (kind == 'weekly') await _applyWeeklyRetention(backupDir);

      if (shareAfterCreate) {
        await shareEncryptedBackup(out.path, targetEmail: targetEmail);
      }

      return EncryptedBackupResult(
        path: out.path,
        sizeBytes: size,
        sha256Hex: hash,
        createdAt: createdAt,
        kind: kind,
        fileCount: files.length,
      );
    } catch (e) {
      try {
        db = await DBService.database;
        await P16SecurityTables.ensure(db);
        await db.insert('backup_runs', {
          'created_at': createdAt.toIso8601String(),
          'kind': kind,
          'local_path': '',
          'status': 'FAILED',
          'size_bytes': 0,
          'includes_media': 1,
          'error_text': e.toString(),
        });
      } catch (_) {}
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  static Future<void> shareEncryptedBackup(
    String backupPath, {
    String? targetEmail,
  }) async {
    final actor = await AuthorizationGuard.require(PermissionKeys.backupExport);
    final file = File(backupPath);
    if (!await file.exists())
      throw StateError('ملف النسخة الاحتياطية غير موجود.');
    final size = await file.length();
    final email = targetEmail?.trim();
    final sizeNote = size > emailAttachmentAdvisoryBytes
        ? '\nحجم النسخة كبير (${(size / 1024 / 1024).toStringAsFixed(1)} MB). '
            'إذا رفض البريد المرفق، اختر Drive/OneDrive/iCloud من نافذة المشاركة.'
        : '';
    final shareResult = await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Yalla Accounts — نسخة احتياطية مشفرة',
      text: 'نسخة Yalla Accounts مشفرة بالكامل.'
          '${email == null || email.isEmpty ? '' : '\nالبريد المستهدف: $email'}'
          '$sizeNote\nاحتفظ بكلمة حماية النسخ في مكان منفصل.',
    );
    if (shareResult.status == ShareResultStatus.dismissed) {
      throw StateError(
        'تم إلغاء المشاركة؛ النسخة المحلية محفوظة لكن الدورة الأسبوعية لم تكتمل خارج الجهاز.',
      );
    }

    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'backup_runs',
      {
        'external_handoff_at': now,
        'external_target': shareResult.status == ShareResultStatus.success
            ? (email == null || email.isEmpty ? 'SHARE_SHEET' : email)
            : (email == null || email.isEmpty
                ? 'SHARE_SHEET_UNVERIFIED'
                : '$email (unverified)'),
      },
      where: 'local_path = ?',
      whereArgs: [backupPath],
    );
    final nextDue =
        DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String();
    await db.update(
      'backup_guardian_settings',
      {
        'last_external_handoff_at': now,
        'next_due_at': nextDue,
        'snoozed_until': null,
        'updated_at': now,
      },
      where: 'id = 1',
    );
    await AuditTrailService.log(
      actorUserId: actor?.id,
      actorRole: actor?.role,
      action: 'BACKUP_EXTERNAL_HANDOFF',
      entityType: 'BACKUP',
      entityId: p.basename(backupPath),
      after: {
        'target': email ?? 'SHARE_SHEET',
        'size_bytes': size,
        'share_status': shareResult.status.name,
      },
    );
  }

  static Future<EncryptedBackupResult?> latestEncryptedBackup() async {
    final root = await YallaStorageService.rootDirectory();
    final dir = Directory(p.join(root.path, 'backups'));
    if (!await dir.exists()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.yallabackup'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (files.isEmpty) return null;
    final f = files.first;
    return EncryptedBackupResult(
      path: f.path,
      sizeBytes: await f.length(),
      sha256Hex: await _sha256File(f),
      createdAt: await f.lastModified(),
      kind: p.basename(f.path).contains('_weekly_') ? 'weekly' : 'manual',
      fileCount: 0,
    );
  }

  static Future<BackupManifest> validateEncryptedBackup(
    String backupPath, {
    required String password,
    bool fullChecksumValidation = true,
  }) async {
    final input = File(backupPath);
    if (!await input.exists()) throw StateError('ملف النسخة غير موجود.');
    final tempRoot = await getTemporaryDirectory();
    final temp = await Directory(
      p.join(tempRoot.path,
          'yalla_validate_${DateTime.now().microsecondsSinceEpoch}'),
    ).create(recursive: true);
    final zip = File(p.join(temp.path, 'payload.zip'));
    final extract = Directory(p.join(temp.path, 'extract'));
    await extract.create();
    try {
      await YallaBackupCodec.decryptFile(
          input: input, output: zip, password: password);
      await extractFileToDisk(zip.path, extract.path);
      final manifest = await _loadManifest(extract);
      await _validateManifestAndExtractedFiles(
        manifest,
        extract,
        fullChecksumValidation: fullChecksumValidation,
      );
      final dbPath = p.join(extract.path, 'database', DatabaseConstants.dbName);
      await validateDatabaseCandidate(dbPath);
      return manifest;
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  static Future<String?> restoreEncryptedFromPicker({
    required String password,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['yallabackup'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return null;
    return restoreEncryptedFromPath(path, password: password);
  }

  static Future<String> restoreEncryptedFromPath(
    String backupPath, {
    required String password,
  }) async {
    final actor =
        await AuthorizationGuard.require(PermissionKeys.backupRestore);
    final input = File(backupPath);
    if (!await input.exists()) throw StateError('ملف النسخة غير موجود.');

    final tempRoot = await getTemporaryDirectory();
    final temp = await Directory(
      p.join(tempRoot.path,
          'yalla_restore_${DateTime.now().microsecondsSinceEpoch}'),
    ).create(recursive: true);
    final zip = File(p.join(temp.path, 'payload.zip'));
    final extract = Directory(p.join(temp.path, 'extract'));
    await extract.create();

    EncryptedBackupResult? safetyBackup;
    try {
      await YallaBackupCodec.decryptFile(
          input: input, output: zip, password: password);
      await extractFileToDisk(zip.path, extract.path);
      final manifest = await _loadManifest(extract);
      await _validateManifestAndExtractedFiles(manifest, extract,
          fullChecksumValidation: true);
      final candidateDb =
          p.join(extract.path, 'database', DatabaseConstants.dbName);
      await validateDatabaseCandidate(candidateDb);

      // P16 disaster recovery: a restore is never allowed to destroy the
      // current device state. Capture a fully validated encrypted snapshot of
      // DB + media before touching the live database or files.
      safetyBackup = await createEncryptedBackup(
        password: password,
        kind: 'pre_restore',
      );
      final livePath = await currentDbPath();
      await DBService.closeDatabase(checkpoint: true);
      try {
        await _removeSidecars(livePath);
        await File(candidateDb).copy(livePath);
        await _restoreMedia(extract, manifest);
        await DBService.reopenDatabase(); // normal migration path
        await _rewriteRestoredPaths(manifest);
        await _validateLiveDatabase();
      } catch (restoreError) {
        await DBService.closeDatabase(checkpoint: false);
        try {
          if (safetyBackup == null) {
            throw StateError('Safety backup was not created.');
          }
          await _restoreSafetyBundle(
            safetyBackup.path,
            password: password,
            livePath: livePath,
          );
        } catch (rollbackError) {
          throw StateError(
            'Restore failed ($restoreError) and full safety rollback also failed '
            '($rollbackError). Safety bundle: ${safetyBackup?.path}',
          );
        }
        rethrow;
      }

      await AuditTrailService.log(
        actorUserId: actor?.id,
        actorRole: actor?.role,
        action: 'BACKUP_RESTORED',
        entityType: 'BACKUP',
        entityId: p.basename(backupPath),
        after: {
          'format_version': manifest.formatVersion,
          'db_version': manifest.dbVersion
        },
      );
      return livePath;
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  static Future<void> _restoreSafetyBundle(
    String safetyPath, {
    required String password,
    required String livePath,
  }) async {
    final tempRoot = await getTemporaryDirectory();
    final temp = await Directory(
      p.join(tempRoot.path,
          'yalla_safety_rollback_${DateTime.now().microsecondsSinceEpoch}'),
    ).create(recursive: true);
    final zip = File(p.join(temp.path, 'payload.zip'));
    final extract = Directory(p.join(temp.path, 'extract'));
    await extract.create();
    try {
      await YallaBackupCodec.decryptFile(
        input: File(safetyPath),
        output: zip,
        password: password,
      );
      await extractFileToDisk(zip.path, extract.path);
      final manifest = await _loadManifest(extract);
      await _validateManifestAndExtractedFiles(
        manifest,
        extract,
        fullChecksumValidation: true,
      );
      final safetyDb =
          p.join(extract.path, 'database', DatabaseConstants.dbName);
      await validateDatabaseCandidate(safetyDb);
      await _removeSidecars(livePath);
      await File(safetyDb).copy(livePath);
      await _restoreMedia(extract, manifest);
      await DBService.reopenDatabase();
      await _rewriteRestoredPaths(manifest);
      await _validateLiveDatabase();
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  // -----------------------------------------------------------------------
  // Legacy database restore / Windows migration foundation.
  // -----------------------------------------------------------------------
  static Future<String?> restoreFromPicker() async {
    await AuthorizationGuard.require(PermissionKeys.backupRestore);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['db'],
      allowMultiple: false,
    );
    final picked = result?.files.single.path;
    if (picked == null || picked.trim().isEmpty) return null;
    return restoreFromPath(picked);
  }

  static Future<String> restoreFromPath(String candidatePath) async {
    await AuthorizationGuard.require(PermissionKeys.backupRestore);
    final candidate = File(candidatePath);
    if (!await candidate.exists())
      throw StateError('Backup file not found: $candidatePath');
    await validateDatabaseCandidate(candidatePath);
    final safetyBackup = await makeBackup();
    final livePath = await currentDbPath();
    await DBService.closeDatabase(checkpoint: true);
    try {
      await _removeSidecars(livePath);
      await candidate.copy(livePath);
      await DBService.reopenDatabase();
      return livePath;
    } catch (_) {
      await DBService.closeDatabase(checkpoint: false);
      await _removeSidecars(livePath);
      await File(safetyBackup).copy(livePath);
      await DBService.reopenDatabase();
      rethrow;
    }
  }

  static Future<void> validateDatabaseCandidate(String path) async {
    final db = await DatabaseEncryptionService.openReadOnlyCandidate(path);
    try {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw StateError('Backup integrity_check failed: $integrity');
      }
      final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeys.isNotEmpty) {
        throw StateError(
            'Backup contains foreign-key violations: $foreignKeys');
      }
      final version =
          Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
      if (version <= 0 || version > DatabaseConstants.dbVersion) {
        throw StateError(
          'Unsupported backup DB version $version. Current supported version is ${DatabaseConstants.dbVersion}.',
        );
      }
      final tables = await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final names =
          tables.map((r) => r['name']?.toString()).whereType<String>().toSet();
      for (final required in const [
        'users',
        'repairs',
        'accounts',
        'gl_entries',
        'gl_lines'
      ]) {
        if (!names.contains(required)) {
          throw StateError(
              'Backup is not a Yalla Accounts database: missing table $required.');
        }
      }
    } finally {
      await db.close();
    }
  }

  // -----------------------------------------------------------------------
  // Bundle internals.
  // -----------------------------------------------------------------------
  static Future<void> _copyLiveDatabaseTo(String destination) async {
    final source = File(await currentDbPath());
    if (!await source.exists())
      throw StateError('قاعدة البيانات الحالية غير موجودة.');
    await DBService.closeDatabase(checkpoint: true);
    try {
      await source.copy(destination);
    } finally {
      await DBService.reopenDatabase();
    }
  }

  static Future<void> _addFile(
    List<_ZipInput> zipInputs,
    List<Map<String, Object?>> manifestFiles,
    File file,
    String archivePath,
  ) async {
    if (!await file.exists()) return;
    final normalized = archivePath.replaceAll('\\', '/');
    zipInputs.add(_ZipInput(file, normalized));
    if (manifestFiles.isNotEmpty || normalized != 'manifest.json') {
      manifestFiles.add({
        'path': normalized,
        'size': await file.length(),
        'sha256': await _sha256File(file),
      });
    }
  }

  static Future<void> _collectDirectory(
    Directory root, {
    required String prefix,
    Set<String> excludeTopLevel = const {},
    required List<_ZipInput> zipInputs,
    required List<Map<String, Object?>> manifestFiles,
  }) async {
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel =
          p.relative(entity.path, from: root.path).replaceAll('\\', '/');
      final first = rel.split('/').first;
      if (excludeTopLevel.contains(first)) continue;
      await _addFile(zipInputs, manifestFiles, entity, '$prefix/$rel');
    }
  }

  static Future<Set<String>> _collectReferencedMedia(Database db) async {
    final out = <String>{};
    void add(Object? value) {
      final raw = value?.toString().trim();
      if (raw == null || raw.isEmpty) return;
      if (raw.startsWith('[')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final v in decoded) add(v);
            return;
          }
        } catch (_) {}
      }
      out.add(raw);
    }

    Future<void> collect(String table, List<String> columns) async {
      try {
        final rows = await db.query(table, columns: columns);
        for (final row in rows) {
          for (final col in columns) add(row[col]);
        }
      } catch (_) {}
    }

    await collect('repairs',
        const ['imagePaths', 'thumbnail_path', 'customer_signature_path']);
    await collect('repair_workflow', const ['handover_signature_path']);
    await collect('employees', const ['photo_url']);
    await collect('workshop_settings', const ['logoPath']);
    await collect(
        'users', const ['workshop_logo_path', 'payment_receipt_path']);
    await collect('payments', const ['attachments']);
    await collect('vouchers', const ['attachments']);
    return out;
  }

  static Future<BackupManifest> _loadManifest(Directory extract) async {
    final file = File(p.join(extract.path, 'manifest.json'));
    if (!await file.exists())
      throw StateError('النسخة لا تحتوي manifest.json.');
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw StateError('Manifest النسخة غير صالح.');
    final manifest = BackupManifest(map: Map<String, dynamic>.from(decoded));
    if (manifest.formatVersion != backupFormatVersion) {
      throw StateError(
          'نسخة Backup format ${manifest.formatVersion} غير مدعومة.');
    }
    if (manifest.dbVersion <= 0 ||
        manifest.dbVersion > DatabaseConstants.dbVersion) {
      throw StateError('نسخة قاعدة البيانات ${manifest.dbVersion} غير مدعومة.');
    }
    return manifest;
  }

  static Future<void> _validateManifestAndExtractedFiles(
    BackupManifest manifest,
    Directory extract, {
    required bool fullChecksumValidation,
  }) async {
    for (final item in manifest.files) {
      if (item is! Map) continue;
      final pathValue = item['path']?.toString() ?? '';
      if (pathValue.isEmpty || pathValue.contains('..')) {
        throw StateError('مسار غير آمن داخل النسخة الاحتياطية.');
      }
      final file = File(p.joinAll([extract.path, ...pathValue.split('/')]));
      if (!await file.exists())
        throw StateError('ملف ناقص في النسخة: $pathValue');
      final expectedSize = (item['size'] as num?)?.toInt();
      if (expectedSize != null && await file.length() != expectedSize) {
        throw StateError('حجم ملف غير مطابق في النسخة: $pathValue');
      }
      if (fullChecksumValidation) {
        final expected = item['sha256']?.toString();
        if (expected != null &&
            expected.isNotEmpty &&
            await _sha256File(file) != expected) {
          throw StateError('Checksum غير مطابق: $pathValue');
        }
      }
    }
  }

  static Future<void> _restoreMedia(
      Directory extract, BackupManifest manifest) async {
    final storageRoot = await YallaStorageService.rootDirectory();
    final appDocs = await getApplicationDocumentsDirectory();
    await _copyTree(Directory(p.join(extract.path, 'storage')), storageRoot);
    await _copyTree(Directory(p.join(extract.path, 'app_documents')), appDocs);

    final recovered =
        Directory(p.join(storageRoot.path, 'documents', 'restored'));
    await recovered.create(recursive: true);
    for (final item in manifest.externalReferences) {
      if (item is! Map) continue;
      final archivePath = item['archive_path']?.toString() ?? '';
      if (archivePath.isEmpty) continue;
      final source = File(p.joinAll([extract.path, ...archivePath.split('/')]));
      if (!await source.exists()) continue;
      final name =
          '${sha256.convert(utf8.encode(item['original_path']?.toString() ?? archivePath)).toString().substring(0, 12)}_${_safeName(p.basename(archivePath))}';
      await source.copy(p.join(recovered.path, name));
      item['restored_path'] = 'documents/restored/$name';
    }
  }

  static Future<void> _rewriteRestoredPaths(BackupManifest manifest) async {
    final db = await DBService.database;
    final currentDocs = await getApplicationDocumentsDirectory();
    final oldDocs = manifest.oldAppDocumentsRoot
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/$'), '');
    final oldStorage = manifest.oldStorageRoot
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/$'), '');

    String rewrite(String value) {
      var normalized = value.replaceAll('\\', '/');
      if (oldStorage.isNotEmpty && normalized.startsWith('$oldStorage/')) {
        return normalized.substring(oldStorage.length + 1);
      }
      if (oldDocs.isNotEmpty && normalized.startsWith('$oldDocs/')) {
        final suffix = normalized.substring(oldDocs.length + 1);
        return p.joinAll([currentDocs.path, ...suffix.split('/')]);
      }
      for (final item in manifest.externalReferences) {
        if (item is! Map) continue;
        final old = item['original_path']?.toString();
        final restored = item['restored_path']?.toString();
        if (old != null && restored != null && value == old) return restored;
      }
      return value;
    }

    await db.transaction((tx) async {
      try {
        final repairs = await tx.query('repairs', columns: const [
          'id',
          'imagePaths',
          'thumbnail_path',
          'customer_signature_path'
        ]);
        for (final row in repairs) {
          final update = <String, Object?>{};
          final rawImages = row['imagePaths']?.toString();
          if (rawImages != null && rawImages.isNotEmpty) {
            try {
              final decoded = jsonDecode(rawImages);
              if (decoded is List) {
                update['imagePaths'] = jsonEncode(
                    decoded.map((e) => rewrite(e.toString())).toList());
              }
            } catch (_) {}
          }
          for (final col in const [
            'thumbnail_path',
            'customer_signature_path'
          ]) {
            final v = row[col]?.toString();
            if (v != null && v.isNotEmpty) update[col] = rewrite(v);
          }
          if (update.isNotEmpty) {
            await tx.update('repairs', update,
                where: 'id = ?', whereArgs: [row['id']]);
          }
        }
      } catch (_) {}

      await _rewriteSimpleColumn(tx, 'repair_workflow', 'repair_id',
          'handover_signature_path', rewrite);
      await _rewriteSimpleColumn(tx, 'employees', 'id', 'photo_url', rewrite);
      await _rewriteSimpleColumn(
          tx, 'workshop_settings', 'id', 'logoPath', rewrite);
      await _rewriteSimpleColumn(
          tx, 'users', 'id', 'workshop_logo_path', rewrite);
      await _rewriteSimpleColumn(
          tx, 'users', 'id', 'payment_receipt_path', rewrite);
      await _rewriteSimpleColumn(tx, 'payments', 'id', 'attachments', rewrite,
          replaceInsideText: true);
      await _rewriteSimpleColumn(tx, 'vouchers', 'id', 'attachments', rewrite,
          replaceInsideText: true);
    });
  }

  static Future<void> _rewriteSimpleColumn(
    DatabaseExecutor tx,
    String table,
    String idColumn,
    String column,
    String Function(String) rewrite, {
    bool replaceInsideText = false,
  }) async {
    try {
      final rows = await tx.query(table, columns: [idColumn, column]);
      for (final row in rows) {
        final old = row[column]?.toString();
        if (old == null || old.isEmpty) continue;
        var next = rewrite(old);
        if (replaceInsideText) {
          try {
            final decoded = jsonDecode(old);
            if (decoded is List) {
              next = jsonEncode(
                decoded.map((value) => rewrite(value.toString())).toList(),
              );
            }
          } catch (_) {
            // Non-JSON legacy attachment values are handled by rewrite(old).
          }
        }
        if (next != old) {
          await tx.update(table, {column: next},
              where: '$idColumn = ?', whereArgs: [row[idColumn]]);
        }
      }
    } catch (_) {}
  }

  static Future<void> _copyTree(Directory source, Directory destination) async {
    if (!await source.exists()) return;
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: source.path);
      final out = File(p.join(destination.path, rel));
      await out.parent.create(recursive: true);
      await entity.copy(out.path);
    }
  }

  static Future<void> _validateLiveDatabase() async {
    final db = await DBService.database;
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty ||
        integrity.first.values.first.toString().toLowerCase() != 'ok') {
      throw StateError('قاعدة البيانات المستعادة لم تجتز integrity_check.');
    }
  }

  static Future<void> _applyWeeklyRetention(Directory dir) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).contains('_weekly_') &&
            f.path.endsWith('.yallabackup'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final old in files.skip(weeklyRetention)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  static Future<String> _sha256File(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static bool _isWithinOrEqual(String root, String file) {
    try {
      final rootAbs = p.absolute(root);
      final fileAbs = p.absolute(file);
      return rootAbs == fileAbs || p.isWithin(rootAbs, fileAbs);
    } catch (_) {
      return false;
    }
  }

  static String _safeName(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  static Future<void> _removeSidecars(String livePath) async {
    for (final suffix in const ['-wal', '-shm']) {
      final file = File('$livePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}

class _ZipInput {
  const _ZipInput(this.file, this.archivePath);
  final File file;
  final String archivePath;
}
