import 'package:sqflite/sqflite.dart';

/// SEC.005 - local installation/device identity metadata.
///
/// The private Ed25519 seed is NEVER stored in SQLite. SQLite contains only
/// public metadata required to bind the future server-side device record.
class DeviceIdentityTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installation_identity (
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        organization_id TEXT NOT NULL,
        installation_id TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL UNIQUE,
        key_algorithm TEXT NOT NULL DEFAULT 'ED25519',
        public_key_b64url TEXT NOT NULL,
        public_key_sha256 TEXT NOT NULL,
        fingerprint_sha256 TEXT NOT NULL,
        platform TEXT NOT NULL,
        platform_version TEXT,
        app_version TEXT NOT NULL,
        identity_generation INTEGER NOT NULL DEFAULT 1,
        binding_state TEXT NOT NULL DEFAULT 'UNBOUND',
        bound_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(organization_id) REFERENCES organizations(id)
          ON DELETE RESTRICT,
        CHECK(key_algorithm = 'ED25519'),
        CHECK(length(public_key_sha256) = 64),
        CHECK(length(fingerprint_sha256) = 64),
        CHECK(identity_generation >= 1),
        CHECK(binding_state IN ('UNBOUND', 'BOUND', 'REVOKED'))
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_installation_identity_org
      ON installation_identity(organization_id);
    ''');
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final rows = await db.query('installation_identity', limit: 2);
    if (rows.length > 1) {
      throw StateError(
          'SEC.005 allows at most one local installation identity.');
    }
    if (rows.isEmpty) return;

    final row = rows.single;
    final currentOrg = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (currentOrg.length != 1 ||
        row['organization_id']?.toString() !=
            currentOrg.single['organization_id']?.toString()) {
      throw StateError('SEC.005 device identity organization mismatch.');
    }

    for (final key in ['installation_id', 'device_id']) {
      if (!_looksLikeUuid(row[key]?.toString() ?? '')) {
        throw StateError('SEC.005 invalid $key.');
      }
    }
    for (final key in ['public_key_sha256', 'fingerprint_sha256']) {
      if (!_looksLikeSha256(row[key]?.toString() ?? '')) {
        throw StateError('SEC.005 invalid $key.');
      }
    }
    if ((row['key_algorithm']?.toString() ?? '') != 'ED25519') {
      throw StateError('SEC.005 unsupported device key algorithm.');
    }
  }

  static bool _looksLikeUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
        r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  static bool _looksLikeSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}
