// 📁 lib/core/services/db/database_constants.dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class DatabaseConstants {
  static const String dbName = 'yalla_accounts.db';
  static const int dbVersion = 76;
  static const String supplierPidPrefix = 'S';

  static final Uuid _uuid = const Uuid();
  static String newUuid() => _uuid.v4();

  /// P1.001 — canonical commercial database-location policy.
  ///
  /// Existing installations that already use the historical
  /// D:/YallaAccounts/yalla_accounts.db keep using it, so an upgrade never
  /// "loses" a customer's live database.
  ///
  /// Fresh Windows installations use LOCALAPPDATA and do not require a D:
  /// drive. Other desktop platforms use the current user's app-data area.
  ///
  /// YALLA_ACCOUNTS_DB_DIR is an explicit support/testing override.
  static Future<String> dbFilePath() async {
    final override = Platform.environment['YALLA_ACCOUNTS_DB_DIR']?.trim();
    if (override != null && override.isNotEmpty) {
      return _ensureDatabaseDirectory(override);
    }

    if (Platform.isWindows) {
      final legacy = File('D:/YallaAccounts/$dbName');
      if (legacy.existsSync()) {
        return legacy.path.replaceAll(r'\', '/');
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

      return _ensureDatabaseDirectory('$base/Yalla Accounts/data');
    }

    // Mobile platforms run inside an application sandbox. Environment HOME is
    // not a reliable application-data location on iOS/Android.
    if (Platform.isIOS || Platform.isAndroid) {
      final appSupport = await getApplicationSupportDirectory();
      return _ensureDatabaseDirectory('${appSupport.path}/data');
    }

    final home = Platform.environment['HOME']?.trim();
    if (home == null || home.isEmpty) {
      throw StateError('Cannot resolve the current user home directory.');
    }

    if (Platform.isMacOS) {
      return _ensureDatabaseDirectory(
        '$home/Library/Application Support/Yalla Accounts/data',
      );
    }

    return _ensureDatabaseDirectory('$home/.local/share/yalla_accounts');
  }

  static String _ensureDatabaseDirectory(String directoryPath) {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    return '${dir.path}/$dbName'.replaceAll(r'\', '/');
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
        'cheques',
        'raw_materials',
        'auth_sessions',
        'password_reset_grants',
        'document_sequences',
      ];
}
