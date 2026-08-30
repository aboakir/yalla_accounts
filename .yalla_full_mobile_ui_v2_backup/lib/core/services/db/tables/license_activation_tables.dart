import 'package:sqflite/sqflite.dart';

class FirstOwnerActivationRequired implements Exception {
  const FirstOwnerActivationRequired([
    this.message = 'Online activation is required before creating First Owner.',
  ]);

  final String message;

  @override
  String toString() => 'FirstOwnerActivationRequired: $message';
}

/// SEC.006 - local public activation receipt.
///
/// The activation code and all private keys are intentionally excluded. The
/// signed license envelope is public authorization material and is safe to
/// persist locally because it is verified cryptographically before commit.
class LicenseActivationTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS license_activation_state (
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        organization_id TEXT NOT NULL,
        installation_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'UNACTIVATED',
        activation_id TEXT,
        license_id TEXT,
        subscription_id TEXT,
        license_expires_at TEXT,
        entitlement_revision INTEGER,
        signed_license_envelope_json TEXT,
        verification_keyset_json TEXT,
        activated_at TEXT,
        last_online_validation_at TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(organization_id) REFERENCES organizations(id)
          ON DELETE RESTRICT,
        CHECK(status IN ('UNACTIVATED','ACTIVE','REVOKED')),
        CHECK(entitlement_revision IS NULL OR entitlement_revision >= 0),
        CHECK(
          status <> 'ACTIVE' OR (
            activation_id IS NOT NULL AND
            license_id IS NOT NULL AND
            subscription_id IS NOT NULL AND
            license_expires_at IS NOT NULL AND
            entitlement_revision IS NOT NULL AND
            signed_license_envelope_json IS NOT NULL AND
            verification_keyset_json IS NOT NULL AND
            activated_at IS NOT NULL AND
            last_online_validation_at IS NOT NULL
          )
        )
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_license_activation_identity
      ON license_activation_state(organization_id, installation_id, device_id);
    ''');
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final rows = await db.query('license_activation_state', limit: 2);
    if (rows.length > 1) {
      throw StateError('SEC.006 allows at most one local activation state.');
    }
    if (rows.isEmpty) return;

    final row = rows.single;
    final identities = await db.query(
      'installation_identity',
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (identities.length != 1) {
      throw StateError('SEC.006 activation exists without device identity.');
    }
    final identity = identities.single;
    for (final key in ['organization_id', 'installation_id', 'device_id']) {
      if (row[key]?.toString() != identity[key]?.toString()) {
        throw StateError('SEC.006 activation/device identity mismatch: $key.');
      }
    }

    if ((row['status']?.toString() ?? '') == 'ACTIVE') {
      for (final key in [
        'activation_id',
        'license_id',
        'subscription_id',
        'license_expires_at',
        'signed_license_envelope_json',
        'verification_keyset_json',
      ]) {
        if ((row[key]?.toString() ?? '').isEmpty) {
          throw StateError('SEC.006 ACTIVE activation is missing $key.');
        }
      }
    }
  }

  static Future<void> requireActiveForFirstOwner(DatabaseExecutor db) async {
    final identities = await db.query(
      'installation_identity',
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (identities.length != 1) {
      throw const FirstOwnerActivationRequired();
    }
    final identity = identities.single;
    final rows = await db.query(
      'license_activation_state',
      where: 'singleton_id = 1 AND status = ? AND organization_id = ? '
          'AND installation_id = ? AND device_id = ?',
      whereArgs: [
        'ACTIVE',
        identity['organization_id'],
        identity['installation_id'],
        identity['device_id'],
      ],
      limit: 1,
    );
    if (rows.length != 1) {
      throw const FirstOwnerActivationRequired();
    }

    final expiry = DateTime.tryParse(
      rows.single['license_expires_at']?.toString() ?? '',
    );
    if (expiry == null || !expiry.isAfter(DateTime.now().toUtc())) {
      throw const FirstOwnerActivationRequired(
        'The activation receipt is missing or already expired.',
      );
    }
  }
}
