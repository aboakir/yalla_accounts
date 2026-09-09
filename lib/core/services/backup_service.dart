import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'restore_file_journal.dart';
// lib/core/services/backup_service.dart
// P16 — full encrypted offline-first backup / disaster recovery.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
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

  static String backupFileName(DateTime createdAt) =>
      'yalla_backup_${DateFormat('yyyy_MM_dd').format(createdAt.toLocal())}.yab';

  static bool isEncryptedBackupPath(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.yab' || extension == '.yallabackup';
  }

  static Future<DateTime?> lastRestoreAt() async {
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final rows = await db.query('app_audit_events',
        columns: const ['created_at'],
        where: 'action = ?',
        whereArgs: const ['BACKUP_RESTORED'],
        orderBy: 'created_at DESC, id DESC',
        limit: 1);
    return rows.isEmpty
        ? null
        : DateTime.tryParse(rows.single['created_at'].toString());
  }

  static Future<String> Function()? _testDbPath;
  static Future<void> Function(bool checkpoint)? _testClose;
  static Future<void> Function()? _testReopen;

  /// Only redirects filesystem/database lifecycle for isolated acceptance tests.
  /// Authorization, archive validation and journal rollback remain production code.
  @visibleForTesting
  static void configureTestDatabase({
    Future<String> Function()? path,
    Future<void> Function(bool checkpoint)? close,
    Future<void> Function()? reopen,
  }) {
    if (!kDebugMode) {
      throw StateError('Test database hooks require debug mode.');
    }
    final configured = [path != null, close != null, reopen != null];
    if (configured.any((value) => value) && configured.any((value) => !value)) {
      throw ArgumentError('All test database lifecycle hooks are required.');
    }
    _testDbPath = path;
    _testClose = close;
    _testReopen = reopen;
  }

  static Future<String> currentDbPath() =>
      _testDbPath?.call() ?? DBService.dbFilePath();

  static Future<void> _closeDatabase({bool checkpoint = true}) async {
    if (_testClose != null) {
      await _testClose!(checkpoint);
    } else {
      await DBService.closeDatabase(checkpoint: checkpoint);
    }
  }

  static Future<void> _reopenDatabase() async {
    if (_testReopen != null) {
      await _testReopen!();
    } else {
      await DBService.reopenDatabase();
    }
  }

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

    await _closeDatabase(checkpoint: true);
    try {
      await srcFile.copy(dst);
    } finally {
      await _reopenDatabase();
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
    if (!await backupDir.exists()) {
      throw StateError('لا توجد نسخة احتياطية سابقة.');
    }
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
        'database_encoding': 'portable_sqlite',
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
      final stamp = createdAt.microsecondsSinceEpoch;
      final safeKind = _safeName(kind.toLowerCase());
      // A separate run directory preserves the portable filename and prevents
      // a second backup on the same day from overwriting the first.
      final runDir =
          await Directory(p.join(backupDir.path, '${safeKind}_$stamp'))
              .create();
      final out = File(p.join(runDir.path, backupFileName(createdAt)));
      final encryptedCandidate = File(p.join(temp.path, 'candidate.yab'));
      await YallaBackupCodec.encryptFile(
        input: File(zipPath),
        output: encryptedCandidate,
        password: password,
      );

      final validation = await validateEncryptedBackup(
        encryptedCandidate.path,
        password: password,
        fullChecksumValidation: true,
      );
      final partial = File('${out.path}.partial');
      try {
        await encryptedCandidate.copy(partial.path);
        await partial.rename(out.path);
      } finally {
        if (await partial.exists()) await partial.delete();
      }
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
        // A failed reopen must never fall through to a different canonical DB.
        // Failure logging is best effort against the last verified open handle.
        if (!db.isOpen) rethrow;
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
    if (!await file.exists()) {
      throw StateError('ملف النسخة الاحتياطية غير موجود.');
    }
    final size = await file.length();
    final email =
        size <= emailAttachmentAdvisoryBytes ? targetEmail?.trim() : null;
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
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => isEncryptedBackupPath(f.path))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (files.isEmpty) return null;
    final f = files.first;
    return EncryptedBackupResult(
      path: f.path,
      sizeBytes: await f.length(),
      sha256Hex: await _sha256File(f),
      createdAt: await f.lastModified(),
      kind: p.basename(f.path).contains('_weekly_') ||
              p.basename(f.parent.path).startsWith('weekly_')
          ? 'weekly'
          : 'manual',
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
      await _extractBackup(zip, extract);
      final manifest = await _loadManifest(extract);
      await _validateManifestAndExtractedFiles(
        manifest,
        extract,
        fullChecksumValidation: fullChecksumValidation,
      );
      final dbPath = p.join(extract.path, 'database', DatabaseConstants.dbName);
      final actualVersion = await validateDatabaseCandidate(dbPath);
      if (actualVersion != manifest.dbVersion) {
        throw StateError('إصدار قاعدة البيانات لا يطابق بيان النسخة.');
      }
      return manifest;
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  static Future<String?> restoreEncryptedFromPicker({
    required String password,
  }) async {
    final path = await pickEncryptedBackup();
    if (path == null) return null;
    return restoreEncryptedFromPath(path, password: password);
  }

  static Future<String?> pickEncryptedBackup() async {
    await AuthorizationGuard.require(PermissionKeys.backupRestore);
    final result = await FilePicker.platform.pickFiles(
      // iOS cannot reliably resolve a custom extension without a registered UTI.
      // The encrypted archive is validated by the restore service before use.
      type: Platform.isIOS ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isIOS ? null : const ['yab', 'yallabackup'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    return path == null || path.trim().isEmpty ? null : path;
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
      await _extractBackup(zip, extract);
      final manifest = await _loadManifest(extract);
      await _validateManifestAndExtractedFiles(manifest, extract,
          fullChecksumValidation: true);
      final candidateDb =
          p.join(extract.path, 'database', DatabaseConstants.dbName);
      final actualVersion = await validateDatabaseCandidate(candidateDb);
      if (actualVersion != manifest.dbVersion) {
        throw StateError('إصدار قاعدة البيانات لا يطابق بيان النسخة.');
      }

      // P16 disaster recovery: a restore is never allowed to destroy the
      // current device state. Capture a fully validated encrypted snapshot of
      // DB + media before touching the live database or files.
      safetyBackup = await createEncryptedBackup(
        password: password,
        kind: 'pre_restore',
      );
      final livePath = await currentDbPath();
      await _closeDatabase(checkpoint: true);
      final journal = await RestoreFileJournal.begin(livePath);
      try {
        await _removeSidecars(livePath);
        await journal.replace(File(candidateDb), livePath);
        await _restoreMedia(extract, manifest, journal: journal);
        await _reopenDatabase(); // normal migration path
        await _rewriteRestoredPaths(manifest);
        await _validateLiveDatabase();
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
        await AuthSessionService().invalidateAfterRestore();
        await journal.commit();
      } catch (restoreError) {
        await _closeDatabase(checkpoint: false);
        try {
          await journal.rollback();
          await _reopenDatabase();
        } catch (rollbackError) {
          throw StateError(
            'Restore failed ($restoreError) and full safety rollback also failed '
            '($rollbackError). Safety bundle: ${safetyBackup.path}',
          );
        }
        rethrow;
      }

      return livePath;
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
    if (!await candidate.exists()) {
      throw StateError('Backup file not found: $candidatePath');
    }
    await validateDatabaseCandidate(candidatePath);
    await makeBackup();
    final livePath = await currentDbPath();
    await _closeDatabase(checkpoint: true);
    final journal = await RestoreFileJournal.begin(livePath);
    try {
      await _removeSidecars(livePath);
      await journal.replace(candidate, livePath);
      await _reopenDatabase();
      await AuthSessionService().invalidateAfterRestore();
      await journal.commit();
      return livePath;
    } catch (_) {
      await _closeDatabase(checkpoint: false);
      await journal.rollback();
      await _reopenDatabase();
      rethrow;
    }
  }

  static Future<int> validateDatabaseCandidate(String path) async {
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
      return version;
    } finally {
      await db.close();
    }
  }

  // -----------------------------------------------------------------------
  // Bundle internals.
  // -----------------------------------------------------------------------
  static Future<void> _copyLiveDatabaseTo(String destination) async {
    if (DatabaseEncryptionService.mobileEncryptionEnabled) {
      // A raw SQLCipher copy depends on this installation's secure key. Export
      // a consistent SQLite snapshot only into temporary staging; the encrypted
      // archive is the sole published file. Destination startup encrypts SQLite
      // with its own installation key through prepareCanonical.
      final db = await DBService.database;
      final quoted = destination.replaceAll("'", "''");
      var attached = false;
      try {
        await db
            .execute("ATTACH DATABASE '$quoted' AS yalla_backup_plain KEY ''");
        attached = true;
        await db.transaction((tx) async {
          final version = Sqflite.firstIntValue(
                  await tx.rawQuery('PRAGMA main.user_version')) ??
              0;
          await tx.rawQuery("SELECT sqlcipher_export('yalla_backup_plain')");
          await tx.execute('PRAGMA yalla_backup_plain.user_version = $version');
        }, exclusive: false);
      } finally {
        if (attached) await db.execute('DETACH DATABASE yalla_backup_plain');
      }
      return;
    }
    final source = File(await currentDbPath());
    if (!await source.exists()) {
      throw StateError('قاعدة البيانات الحالية غير موجودة.');
    }
    await _closeDatabase(checkpoint: true);
    try {
      await source.copy(destination);
    } finally {
      await _reopenDatabase();
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
      if (rel.split('/').any((part) => part
          .toLowerCase()
          .startsWith(DatabaseConstants.dbName.toLowerCase()))) {
        continue;
      }
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
            for (final v in decoded) {
              add(v);
            }
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
          for (final col in columns) {
            add(row[col]);
          }
        }
      } catch (_) {}
    }

    await collect('repairs',
        const ['imagePaths', 'thumbnail_path', 'customer_signature_path']);
    await collect('repairs', const ['transferImagePath']);
    await collect('repairs_images', const ['path']);
    await collect('insurance_policies', const ['vehicle_images']);
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
    if (!await file.exists()) {
      throw StateError('النسخة لا تحتوي manifest.json.');
    }
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

  static String _safeArchivePath(String value) {
    final parts = value.split('/');
    if (value.isEmpty ||
        value.contains('\\') ||
        value.contains(':') ||
        value.contains('\u0000') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw StateError('مسار غير آمن داخل النسخة الاحتياطية.');
    }
    return value;
  }

  static Future<void> _extractBackup(File zip, Directory extract) async {
    // Inspect the directory before extraction: archive's extractor silently skips
    // unsafe entries; backup acceptance must reject them instead.
    final stream = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeBuffer(stream);
      final paths = <String>{};
      for (final entry in archive) {
        final path = entry.isFile
            ? entry.name
            : entry.name.replaceFirst(RegExp(r'/$'), '');
        _safeArchivePath(path);
        if (entry.isSymbolicLink || !paths.add(path.toLowerCase())) {
          throw StateError('النسخة تحتوي رابطًا أو مسارًا مكررًا غير صالح.');
        }
      }
    } finally {
      await stream.close();
    }
    await extractFileToDisk(zip.path, extract.path);
  }

  static Future<void> _validateManifestAndExtractedFiles(
    BackupManifest manifest,
    Directory extract, {
    required bool fullChecksumValidation,
  }) async {
    if (manifest.map['format'] != 'YALLA_BACKUP' || manifest.files.isEmpty) {
      throw StateError('بيان محتويات النسخة الاحتياطية غير صالح.');
    }
    final declared = <String>{};
    for (final item in manifest.files) {
      if (item is! Map || item['path'] is! String) {
        throw StateError('بيان ملفات النسخة الاحتياطية غير صالح.');
      }
      final pathValue = _safeArchivePath(item['path'] as String);
      if (!declared.add(pathValue.toLowerCase())) {
        throw StateError('مسار مكرر داخل النسخة الاحتياطية.');
      }
      final file = File(p.joinAll([extract.path, ...pathValue.split('/')]));
      if (!await file.exists()) {
        throw StateError('ملف ناقص في النسخة: $pathValue');
      }
      final expectedSize = item['size'];
      if (expectedSize is! int ||
          expectedSize < 0 ||
          await file.length() != expectedSize) {
        throw StateError('حجم ملف غير مطابق في النسخة: $pathValue');
      }
      final expected = item['sha256'];
      if (expected is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
        throw StateError('بصمة ملف ناقصة أو غير صالحة: $pathValue');
      }
      if (fullChecksumValidation && await _sha256File(file) != expected) {
        throw StateError('Checksum غير مطابق: $pathValue');
      }
    }
    if (!declared
        .contains('database/${DatabaseConstants.dbName}'.toLowerCase())) {
      throw StateError('قاعدة البيانات غير مدرجة في بيان النسخة.');
    }
    await for (final entity
        in extract.list(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw StateError('روابط الملفات غير مسموحة في النسخة.');
      }
      if (entity is! File) continue;
      final relative =
          p.relative(entity.path, from: extract.path).replaceAll('\\', '/');
      if (relative != 'manifest.json' &&
          !declared.contains(relative.toLowerCase())) {
        throw StateError('ملف غير مدرج في بيان النسخة: $relative');
      }
    }
    for (final item in manifest.externalReferences) {
      if (item is! Map ||
          item['archive_path'] is! String ||
          item['original_path'] is! String ||
          !declared.contains(
              _safeArchivePath(item['archive_path'] as String).toLowerCase()) ||
          !(item['archive_path'] as String).startsWith('external_media/')) {
        throw StateError('مرجع مرفق غير صالح في النسخة.');
      }
    }
  }

  static Future<void> _restoreMedia(Directory extract, BackupManifest manifest,
      {RestoreFileJournal? journal}) async {
    final storageRoot = await YallaStorageService.rootDirectory();
    final appDocs = await getApplicationDocumentsDirectory();
    await _copyTree(Directory(p.join(extract.path, 'storage')), storageRoot,
        journal: journal);
    await _copyTree(Directory(p.join(extract.path, 'app_documents')), appDocs,
        journal: journal);

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
      final destination = p.join(recovered.path, name);
      if (journal != null) {
        await journal.replace(source, destination);
      } else {
        await source.copy(destination);
      }
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
      await _rewriteSimpleColumn(
          tx, 'repairs', 'id', 'transferImagePath', rewrite);
      await _rewriteSimpleColumn(tx, 'repairs_images', 'id', 'path', rewrite);
      await _rewriteSimpleColumn(
          tx, 'insurance_policies', 'id', 'vehicle_images', rewrite,
          replaceInsideText: true);
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

  static Future<void> _copyTree(Directory source, Directory destination,
      {RestoreFileJournal? journal}) async {
    if (!await source.exists()) return;
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: source.path);
      if (p.split(rel).any((part) => part
          .toLowerCase()
          .startsWith(DatabaseConstants.dbName.toLowerCase()))) {
        continue;
      }
      final out = File(p.join(destination.path, rel));
      await out.parent.create(recursive: true);
      if (journal != null) {
        await journal.replace(entity, out.path);
      } else {
        await entity.copy(out.path);
      }
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
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) =>
            (p.basename(f.path).contains('_weekly_') ||
                p.basename(f.parent.path).startsWith('weekly_')) &&
            isEncryptedBackupPath(f.path))
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
