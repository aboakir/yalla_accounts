import 'package:sqflite/sqflite.dart';

/// SEC.007 - one-time First Owner bootstrap state.
class OwnerBootstrapTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS owner_bootstrap_state (
        singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
        organization_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        owner_user_id TEXT,
        activation_id TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(organization_id) REFERENCES organizations(id)
          ON DELETE RESTRICT,
        FOREIGN KEY(owner_user_id) REFERENCES users(id)
          ON DELETE RESTRICT,
        CHECK(status IN ('PENDING','COMPLETED')),
        CHECK(
          status <> 'COMPLETED' OR (
            owner_user_id IS NOT NULL AND
            completed_at IS NOT NULL
          )
        )
      );
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_users_one_owner_per_org
      ON users(organization_id)
      WHERE is_owner = 1;
    ''');

    final identity = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (identity.length != 1) {
      throw StateError('SEC.007 requires the SEC.001 organization identity.');
    }
    final organizationId = identity.single['organization_id']!.toString();

    final owners = await db.query(
      'users',
      columns: ['id'],
      where: 'organization_id = ? AND is_owner = 1',
      whereArgs: [organizationId],
      limit: 2,
    );
    if (owners.length > 1) {
      throw StateError('SEC.007 found more than one workshop owner.');
    }

    final userCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM users WHERE organization_id = ?',
            [organizationId],
          ),
        ) ??
        0;
    final now = DateTime.now().toUtc().toIso8601String();

    if (owners.length == 1) {
      await db.insert(
        'owner_bootstrap_state',
        {
          'singleton_id': 1,
          'organization_id': organizationId,
          'status': 'COMPLETED',
          'owner_user_id': owners.single['id']!.toString(),
          'activation_id': null,
          'created_at': now,
          'completed_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.update(
        'owner_bootstrap_state',
        {
          'status': 'COMPLETED',
          'owner_user_id': owners.single['id']!.toString(),
          'completed_at': now,
          'updated_at': now,
        },
        where: 'singleton_id = 1 AND status = ?',
        whereArgs: ['PENDING'],
      );
      return;
    }

    if (userCount != 0) {
      throw StateError(
        'SEC.007 cannot bootstrap: users exist without a unique owner.',
      );
    }

    await db.insert(
      'owner_bootstrap_state',
      {
        'singleton_id': 1,
        'organization_id': organizationId,
        'status': 'PENDING',
        'owner_user_id': null,
        'activation_id': null,
        'created_at': now,
        'completed_at': null,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final rows = await db.query('owner_bootstrap_state', limit: 2);
    if (rows.length != 1) {
      throw StateError('SEC.007 requires exactly one bootstrap state row.');
    }
    final row = rows.single;
    final identity = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (identity.length != 1 ||
        row['organization_id']?.toString() !=
            identity.single['organization_id']?.toString()) {
      throw StateError('SEC.007 bootstrap organization mismatch.');
    }

    final owners = await db.query(
      'users',
      columns: ['id'],
      where: 'organization_id = ? AND is_owner = 1',
      whereArgs: [row['organization_id']],
      limit: 2,
    );
    final status = row['status']?.toString();
    if (status == 'PENDING') {
      if (owners.isNotEmpty) {
        throw StateError('SEC.007 PENDING state cannot already have an owner.');
      }
      final userCount = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM users WHERE organization_id = ?',
              [row['organization_id']],
            ),
          ) ??
          0;
      if (userCount != 0) {
        throw StateError(
          'SEC.007 PENDING state cannot contain pre-bootstrap users.',
        );
      }
      return;
    }
    if (status != 'COMPLETED' || owners.length != 1) {
      throw StateError('SEC.007 completed bootstrap requires one owner.');
    }
    if (row['owner_user_id']?.toString() != owners.single['id']?.toString()) {
      throw StateError('SEC.007 bootstrap owner linkage mismatch.');
    }
  }
}
