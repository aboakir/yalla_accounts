import 'package:sqflite/sqflite.dart';
import '../database_constants.dart';

/// Person identity is independent of workshop membership and ledger accounts.
/// Existing people are never merged by matching names or email addresses.
class IdentityAccountTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS identity_accounts (
        id TEXT PRIMARY KEY NOT NULL,
        origin_user_id TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        email TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info(users)');
    if (!columns.any((row) => row['name'] == 'identity_account_id')) {
      await db.execute('ALTER TABLE users ADD COLUMN identity_account_id TEXT '
          'REFERENCES identity_accounts(id) ON DELETE RESTRICT');
    }
    final unlinked =
        await db.query('users', where: 'identity_account_id IS NULL');
    for (final user in unlinked) {
      await db.insert(
          'identity_accounts',
          {
            'id': DatabaseConstants.newUuid(),
            'origin_user_id': user['id'],
            'display_name': user['name'] ?? '',
            'email': user['email'],
            'created_at':
                user['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.execute(
          'UPDATE users SET identity_account_id = '
          '(SELECT id FROM identity_accounts WHERE origin_user_id = users.id) '
          'WHERE id = ? AND identity_account_id IS NULL',
          [user['id']]);
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_users_identity_account '
        'ON users(identity_account_id)');
    // The trigger covers every existing user-creation path atomically,
    // including first-owner bootstrap. UUIDs are generated once, not on reads.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_users_identity_create
      AFTER INSERT ON users WHEN NEW.identity_account_id IS NULL
      BEGIN
        INSERT OR IGNORE INTO identity_accounts
          (id, origin_user_id, display_name, email, created_at)
        VALUES (
          lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) ||
          '-4' || substr(lower(hex(randomblob(2))), 2) || '-' ||
          substr('89ab', 1 + (random() & 3), 1) ||
          substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
          NEW.id, COALESCE(NEW.name, ''), NEW.email,
          COALESCE(NEW.created_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        );
        UPDATE users SET identity_account_id =
          (SELECT id FROM identity_accounts WHERE origin_user_id = NEW.id)
          WHERE id = NEW.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_users_identity_immutable
      BEFORE UPDATE OF identity_account_id ON users
      WHEN OLD.identity_account_id IS NOT NULL
        AND NEW.identity_account_id IS NOT OLD.identity_account_id
      BEGIN
        SELECT RAISE(ABORT, 'Person identity cannot be reassigned silently');
      END
    ''');
    await validate(db);
  }

  static Future<void> validate(DatabaseExecutor db) async {
    final invalid = await db.rawQuery('''
      SELECT u.id FROM users u LEFT JOIN identity_accounts a
        ON a.id = u.identity_account_id WHERE a.id IS NULL LIMIT 1
    ''');
    if (invalid.isNotEmpty) throw StateError('User person identity is missing');
  }
}
