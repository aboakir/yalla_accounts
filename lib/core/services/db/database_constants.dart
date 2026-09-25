// 📁 lib/core/services/db/database_constants.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as paths;
import 'package:uuid/uuid.dart';

class DatabaseConstants {
  static const String dbName = 'yallah_accounts.db';
  static const List<String> _knownDbNames = <String>[
    dbName,
    'yalla_accounts.db',
  ];
  static const int dbVersion = 85;
  static const String supplierPidPrefix = 'S';

  static final Uuid _uuid = const Uuid();
  static String newUuid() => _uuid.v4();

  /// P1.001 — canonical commercial database-location policy.
  ///
  /// Existing installations that already use the historical
  /// D:/YallaAccounts/yalla_accounts.db keep using it, so an upgrade never
  /// "loses" a customer's live database.
  ///
  /// Fresh Windows installations prefer D:/Yallah Accounts. If D: is missing
  /// or not writable, the database is created under LOCALAPPDATA on C:.
  /// Nothing is copied or migrated between drives by this resolver.
  ///
  /// Mobile platforms keep their own sandboxed database policy.
  /// YALLA_ACCOUNTS_DB_DIR is an explicit support/testing override.
  static bool get isTestProcess =>
      !kIsWeb &&
      (Platform.environment['FLUTTER_TEST'] == 'true' ||
          Platform.environment['YALLAH_FINANCIAL_QA'] == '1');

  /// Fail before any file/database access to a live installation during tests.
  static void assertSafeTestPath(String value) {
    if (!isTestProcess) return;
    final normalized = paths.windows.normalize(value).toLowerCase();
    final roots = <String>[
      'D:/Yallah Accounts',
      'D:/YallaAccounts',
      for (final key in ['LOCALAPPDATA', 'APPDATA', 'USERPROFILE'])
        if (Platform.environment[key]?.isNotEmpty == true)
          '${Platform.environment[key]}/Yallah Accounts',
    ];
    for (final root in roots) {
      final blocked = paths.windows.normalize(root).toLowerCase();
      if (normalized == blocked || normalized.startsWith('$blocked\\')) {
        throw StateError(
            'TEST_DATABASE_SAFETY: live application data is forbidden.');
      }
    }
  }

  static Future<String> dbFilePath() async {
    if (kIsWeb) return dbName;

    final override = Platform.environment['YALLA_ACCOUNTS_DB_DIR']?.trim();
    if (isTestProcess && (override == null || override.isEmpty)) {
      throw StateError(
          'TEST_DATABASE_SAFETY: provide a temporary database directory.');
    }
    if (override != null && override.isNotEmpty) assertSafeTestPath(override);
    if (override != null && override.isNotEmpty) {
      return _existingOrCreate(override);
    }

    if (Platform.isWindows) {
      const preferred = 'D:/Yallah Accounts';
      const legacy = 'D:/YallaAccounts';

      final existing = _firstExistingDatabase(<String>[preferred, legacy]);
      if (existing != null) return existing;

      if (_canUseWindowsDirectory(preferred)) {
        return _existingOrCreate(preferred);
      }

      final base = _firstNonEmpty([
        Platform.environment['LOCALAPPDATA']?.trim(),
        Platform.environment['APPDATA']?.trim(),
        Platform.environment['USERPROFILE']?.trim(),
      ]);

      if (base == null) {
        throw StateError(
          'Cannot resolve a writable Windows application-data directory.',
        );
      }

      final localDir = '$base/Yallah Accounts';
      return _existingOrCreate(localDir);
    }

    // Mobile platforms run inside an application sandbox. Environment HOME is
    // not a reliable application-data location on iOS/Android.
    if (Platform.isIOS || Platform.isAndroid) {
      final appSupport = await getApplicationSupportDirectory();
      return _existingOrCreate('${appSupport.path}/data');
    }

    final home = Platform.environment['HOME']?.trim();
    if (home == null || home.isEmpty) {
      throw StateError('Cannot resolve the current user home directory.');
    }

    if (Platform.isMacOS) {
      return _existingOrCreate(
        '$home/Library/Application Support/Yallah Accounts/data',
      );
    }

    return _existingOrCreate('$home/.local/share/yallah_accounts');
  }

  static String? _firstExistingDatabase(List<String> directories) {
    for (final directoryPath in directories) {
      for (final name in _knownDbNames) {
        final file = File('$directoryPath/$name');
        if (file.existsSync()) {
          return file.path.replaceAll(r'\', '/');
        }
      }
    }
    return null;
  }

  static String _existingOrCreate(String directoryPath) {
    final existing = _firstExistingDatabase(<String>[directoryPath]);
    if (existing != null) return existing;

    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    return '${dir.path}/$dbName'.replaceAll(r'\', '/');
  }

  static bool _canUseWindowsDirectory(String directoryPath) {
    try {
      final root = Directory('D:/');
      if (!root.existsSync()) return false;

      final dir = Directory(directoryPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final probe = File(
        '${dir.path}/.yallah_accounts_write_probe_${pid}_${DateTime.now().microsecondsSinceEpoch}',
      );
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static Map<String, String> get columnTypes => {
        'text': 'TEXT',
        'integer': 'INTEGER',
        'real': 'REAL',
        'blob': 'BLOB',
      };

  static List<String> get coreTables => [
        'organizations',
        'organization_identity',
        'installation_identity',
        'license_activation_state',
        'license_runtime_state',
        'license_validation_state',
        'owner_bootstrap_state',
        'auth_roles',
        'auth_permissions',
        'auth_role_permissions',
        'users',
        'workshop_settings',
        'clients',
        'vehicles',
        'repairs',
        'invoices',
        'accounts',
        'gl_entries',
        'gl_lines',
        'parties',
        'party_roles',
        'accounting_audit_events',
        'payments',
        'vouchers',
        'suppliers',
        'purchase_invoices',
        'purchase_invoice_lines',
        'purchase_payments',
        'insurance_invoices',
        'cheques',
        'raw_materials',
        'auth_sessions',
        'password_reset_grants',
        'document_sequences',
      ];
}
