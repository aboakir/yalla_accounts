import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'database_encryption_key_store.dart';

/// P04.1 — mobile SQLCipher boundary.
///
/// iOS/Android canonical databases are encrypted at rest. Desktop keeps the
/// established sqflite_common_ffi lifecycle in P04.1 so existing Windows data
/// and the commercial desktop runtime are not migrated by a mobile phase.
class DatabaseEncryptionService {
  DatabaseEncryptionService._();

  static const String _tempSuffix = '.p04_encrypting';
  static const String _plaintextBackupSuffix = '.p04_plaintext_backup';

  static bool get mobileEncryptionEnabled =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Future<DatabaseEncryptionPreparation?> prepareCanonical(
    String livePath,
  ) async {
    if (!mobileEncryptionEnabled) return null;

    final password = await DatabaseEncryptionKeyStore.readOrCreate();
    final live = File(livePath);
    final temp = File('$livePath$_tempSuffix');
    final plaintextBackup = File('$livePath$_plaintextBackupSuffix');

    if (!await live.exists() && await plaintextBackup.exists()) {
      await plaintextBackup.rename(livePath);
    }

    if (await live.exists()) {
      final encrypted = await _canOpenEncrypted(livePath, password);
      if (encrypted) {
        if (await plaintextBackup.exists()) {
          await plaintextBackup.delete();
        }
        if (await temp.exists()) {
          await temp.delete();
        }
        await _removeSidecars(plaintextBackup.path);
        return DatabaseEncryptionPreparation._(
          livePath: livePath,
          password: password,
        );
      }

      final plaintext = await _canOpenPlaintext(livePath);
      if (!plaintext) {
        throw StateError(
          'The local database cannot be opened with the installation key '
          'or as legacy plaintext. Yalla Accounts will not reset it.',
        );
      }

      if (await plaintextBackup.exists()) {
        throw StateError(
          'Ambiguous database encryption recovery state. '
          'The plaintext database was left untouched.',
        );
      }

      if (await temp.exists()) {
        await temp.delete();
      }
      await _removeSidecars(temp.path);

      final expectedCounts = await _exportPlaintextToEncrypted(
        sourcePath: livePath,
        targetPath: temp.path,
        password: password,
      );

      await _validateEncryptedCopy(
        path: temp.path,
        password: password,
        expectedCounts: expectedCounts,
      );

      await _removeSidecars(livePath);

      await live.rename(plaintextBackup.path);
      try {
        await temp.rename(livePath);
      } catch (_) {
        if (!await live.exists() && await plaintextBackup.exists()) {
          await plaintextBackup.rename(livePath);
        }
        rethrow;
      }

      return DatabaseEncryptionPreparation._(
        livePath: livePath,
        password: password,
        plaintextBackupPath: plaintextBackup.path,
      );
    }

    if (await temp.exists()) {
      await temp.delete();
    }

    return DatabaseEncryptionPreparation._(
      livePath: livePath,
      password: password,
    );
  }

  static Future<Database> openReadOnlyCandidate(String path) async {
    if (!mobileEncryptionEnabled) {
      return openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );
    }

    final password = await DatabaseEncryptionKeyStore.readExisting();
    if (password != null) {
      try {
        return await sqlcipher.openDatabase(
          path,
          password: password,
          readOnly: true,
          singleInstance: false,
        );
      } catch (_) {
        // Fall through to legacy plaintext validation.
      }
    }

    try {
      return await sqlcipher.openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );
    } catch (_) {
      throw StateError(
        'Backup is neither valid legacy plaintext nor encrypted with '
        'this installation key.',
      );
    }
  }

  static Future<bool> _canOpenEncrypted(String path, String password) async {
    Database? db;
    try {
      db = await sqlcipher.openDatabase(
        path,
        password: password,
        readOnly: true,
        singleInstance: false,
      );
      final cipherVersion = await db.rawQuery('PRAGMA cipher_version');
      if (cipherVersion.isEmpty ||
          cipherVersion.first.values.first.toString().trim().isEmpty) {
        return false;
      }
      await db.rawQuery('SELECT COUNT(*) FROM sqlite_master');
      return true;
    } catch (_) {
      return false;
    } finally {
      if (db != null && db.isOpen) await db.close();
    }
  }

  static Future<bool> _canOpenPlaintext(String path) async {
    Database? db;
    try {
      db = await sqlcipher.openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      return integrity.isNotEmpty &&
          integrity.first.values.first.toString().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    } finally {
      if (db != null && db.isOpen) await db.close();
    }
  }

  static Future<Map<String, int>> _exportPlaintextToEncrypted({
    required String sourcePath,
    required String targetPath,
    required String password,
  }) async {
    Database? source;
    var attached = false;

    try {
      source = await sqlcipher.openDatabase(
        sourcePath,
        singleInstance: false,
      );

      final expectedCounts = await _tableCounts(source);
      final version = Sqflite.firstIntValue(
            await source.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      final autoVacuum = Sqflite.firstIntValue(
            await source.rawQuery('PRAGMA auto_vacuum'),
          ) ??
          0;

      final quotedTarget = _sqlLiteral(targetPath);
      final quotedPassword = _sqlLiteral(password);

      await source.execute(
        "ATTACH DATABASE '$quotedTarget' AS encrypted KEY '$quotedPassword'",
      );
      attached = true;

      await source.execute('PRAGMA encrypted.auto_vacuum = $autoVacuum');
      await source.rawQuery("SELECT sqlcipher_export('encrypted')");
      await source.execute('PRAGMA encrypted.user_version = $version');
      await source.execute('DETACH DATABASE encrypted');
      attached = false;

      return expectedCounts;
    } finally {
      if (source != null && source.isOpen) {
        if (attached) {
          try {
            await source.execute('DETACH DATABASE encrypted');
          } catch (_) {
            // The connection close below is the final cleanup boundary.
          }
        }
        await source.close();
      }
    }
  }

  static Future<void> _validateEncryptedCopy({
    required String path,
    required String password,
    required Map<String, int> expectedCounts,
  }) async {
    Database? db;
    try {
      db = await sqlcipher.openDatabase(
        path,
        password: password,
        readOnly: true,
        singleInstance: false,
      );

      final cipherVersion = await db.rawQuery('PRAGMA cipher_version');
      if (cipherVersion.isEmpty ||
          cipherVersion.first.values.first.toString().trim().isEmpty) {
        throw StateError('SQLCipher runtime was not detected.');
      }

      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw StateError('Encrypted database integrity_check failed.');
      }

      final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeys.isNotEmpty) {
        throw StateError('Encrypted database contains foreign-key violations.');
      }

      final actualCounts = await _tableCounts(db);
      if (actualCounts.length != expectedCounts.length) {
        throw StateError(
          'Encrypted migration table count does not match plaintext source.',
        );
      }

      for (final entry in expectedCounts.entries) {
        if (actualCounts[entry.key] != entry.value) {
          throw StateError(
            'Encrypted migration row count mismatch for ${entry.key}.',
          );
        }
      }
    } finally {
      if (db != null && db.isOpen) await db.close();
    }
  }

  static Future<Map<String, int>> _tableCounts(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
      'ORDER BY name',
    );

    final result = <String, int>{};
    for (final row in rows) {
      final name = row['name']?.toString();
      if (name == null || name.isEmpty) continue;

      final quoted = _sqlIdentifier(name);
      final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $quoted'),
          ) ??
          -1;
      result[name] = count;
    }
    return result;
  }

  static Future<void> _removeSidecars(String path) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  static String _sqlLiteral(String value) => value.replaceAll("'", "''");

  static String _sqlIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';
}

class DatabaseEncryptionPreparation {
  DatabaseEncryptionPreparation._({
    required this.livePath,
    required this.password,
    this.plaintextBackupPath,
  });

  final String livePath;
  final String password;
  final String? plaintextBackupPath;

  Future<Database> open({
    required int version,
    required Future<void> Function(Database db) onConfigure,
    required Future<void> Function(Database db, int version) onCreate,
    required Future<void> Function(
      Database db,
      int oldVersion,
      int newVersion,
    ) onUpgrade,
    required bool singleInstance,
  }) {
    return sqlcipher.openDatabase(
      livePath,
      password: password,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      singleInstance: singleInstance,
    );
  }

  Future<void> commit() async {
    final backup = plaintextBackupPath;
    if (backup == null) return;

    final file = File(backup);
    if (await file.exists()) await file.delete();
    await DatabaseEncryptionService._removeSidecars(backup);
  }

  Future<void> rollback() async {
    final backup = plaintextBackupPath;
    if (backup == null) return;

    final live = File(livePath);
    final plaintext = File(backup);
    if (!await plaintext.exists()) return;

    if (await live.exists()) await live.delete();
    await DatabaseEncryptionService._removeSidecars(livePath);
    await plaintext.rename(livePath);
  }
}
