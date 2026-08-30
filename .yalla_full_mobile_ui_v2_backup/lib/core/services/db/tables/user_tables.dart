// 📁 lib/core/services/db/tables/user_tables.dart
import 'package:sqflite/sqflite.dart';

class UserTables {
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createUsersTable(db);
    await ensureAuthSecuritySchema(db);
    await _createWorkshopSettingsTable(db);
    await _createClientsTable(db);
    await _ensureClientsAccountCol(db);
  }

  static Future<void> _createUsersTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        email TEXT,
        password TEXT NOT NULL,
        role TEXT,
        status TEXT,
        created_at TEXT,

        is_owner INTEGER DEFAULT 0,
        must_change_password INTEGER NOT NULL DEFAULT 0,
        failed_login_count INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        last_login_at TEXT,
        password_changed_at TEXT,

        security_question TEXT,
        security_answer_hash TEXT,

        recovery_code_hash TEXT,
        recovery_code_used INTEGER DEFAULT 0,

        free_trial_start TEXT,
        free_trial_end TEXT,
        subscription_date TEXT,
        subscription_end_date TEXT,
        subscription_amount REAL,
        payment_status TEXT,
        payment_method TEXT,
        payment_receipt_path TEXT,

        workshop_logo_path TEXT,
        workshop_address TEXT,
        country TEXT,
        province TEXT,
        city TEXT,
        street TEXT,
        workshop_phone TEXT,
        phone_numbers TEXT
      )
    ''');
  }

  static Future<void> ensureAuthSecuritySchema(
    DatabaseExecutor db,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info(users)');
    bool hasCol(String name) => cols.any((c) => c['name']?.toString() == name);

    Future<void> addIfMissing(String name, String sql) async {
      if (!hasCol(name)) {
        await db.execute(sql);
      }
    }

    await addIfMissing(
      'is_owner',
      'ALTER TABLE users ADD COLUMN is_owner INTEGER DEFAULT 0;',
    );
    await addIfMissing(
      'must_change_password',
      'ALTER TABLE users ADD COLUMN '
          'must_change_password INTEGER NOT NULL DEFAULT 0;',
    );
    await addIfMissing(
      'failed_login_count',
      'ALTER TABLE users ADD COLUMN '
          'failed_login_count INTEGER NOT NULL DEFAULT 0;',
    );
    await addIfMissing(
      'locked_until',
      'ALTER TABLE users ADD COLUMN locked_until TEXT;',
    );
    await addIfMissing(
      'last_login_at',
      'ALTER TABLE users ADD COLUMN last_login_at TEXT;',
    );
    await addIfMissing(
      'password_changed_at',
      'ALTER TABLE users ADD COLUMN password_changed_at TEXT;',
    );
    await addIfMissing(
      'security_question',
      'ALTER TABLE users ADD COLUMN security_question TEXT;',
    );
    await addIfMissing(
      'security_answer_hash',
      'ALTER TABLE users ADD COLUMN security_answer_hash TEXT;',
    );
    await addIfMissing(
      'recovery_code_hash',
      'ALTER TABLE users ADD COLUMN recovery_code_hash TEXT;',
    );
    await addIfMissing(
      'recovery_code_used',
      'ALTER TABLE users ADD COLUMN '
          'recovery_code_used INTEGER DEFAULT 0;',
    );

    final duplicateNames = await db.rawQuery('''
      SELECT LOWER(name) AS normalized_name, COUNT(*) AS c
      FROM users
      GROUP BY LOWER(name)
      HAVING COUNT(*) > 1
    ''');

    if (duplicateNames.isNotEmpty) {
      throw StateError(
        'Cannot enforce case-insensitive username uniqueness: '
        '$duplicateNames',
      );
    }

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_users_name_nocase
      ON users(name COLLATE NOCASE);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        last_seen_at TEXT,
        revoked_at TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auth_sessions_user
      ON auth_sessions(user_id, revoked_at);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_auth_sessions_expiry
      ON auth_sessions(expires_at);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS password_reset_grants (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        used_at TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_password_reset_grants_user
      ON password_reset_grants(user_id, used_at);
    ''');
  }

  static Future<void> _createWorkshopSettingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workshop_settings(
        id INTEGER PRIMARY KEY,
        workshopName TEXT,
        logoPath TEXT,
        workStart TEXT,
        workEnd TEXT,
        dailyHours REAL,
        breakMinutes INTEGER,
        weekWorkdays TEXT,
        latePenalty REAL,
        earlyLeavePenalty REAL,
        overtimeRate REAL,
        hourlyRate REAL,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ws_work_time
      ON workshop_settings(workStart, workEnd);
    ''');

    await _migrateWorkshopSettingsSnakeToCamel(db);
  }

  static Future<void> _migrateWorkshopSettingsSnakeToCamel(
    DatabaseExecutor db,
  ) async {
    // Legacy compatibility hook intentionally retained.
  }

  static Future<void> _createClientsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        account_id INTEGER
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clients_name '
      'ON clients(LOWER(name));',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clients_account '
      'ON clients(account_id);',
    );
  }

  static Future<void> _ensureClientsAccountCol(
    DatabaseExecutor db,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info(clients)');
    final has = cols.any((c) => c['name']?.toString() == 'account_id');

    if (!has) {
      await db.execute(
        'ALTER TABLE clients ADD COLUMN account_id INTEGER;',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_account '
        'ON clients(account_id);',
      );
    }
  }

  static Future<void> onUpgrade(
    Database db,
    int oldV,
    int newV,
  ) async {
    if (oldV < 31) {
      await _createWorkshopSettingsTable(db);
    }
    if (oldV < 38) {
      await _createClientsTable(db);
      await _ensureClientsAccountCol(db);
    }
    await ensureAuthSecuritySchema(db);
  }

  static Future<Map<String, dynamic>> getUserById(
    DatabaseExecutor db,
    String id,
  ) async {
    final r = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isNotEmpty ? Map<String, dynamic>.from(r.first) : {};
  }

  static Future<int> updateWorkshopSettings(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) async {
    return db.update(
      'workshop_settings',
      data,
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  static Future<Map<String, dynamic>> getWorkshopSettings(
    DatabaseExecutor db,
  ) async {
    final r = await db.query(
      'workshop_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    return r.isNotEmpty ? Map<String, dynamic>.from(r.first) : {};
  }

  static Future<List<Map<String, dynamic>>> getAllClients(
    DatabaseExecutor db,
  ) async {
    return db.query('clients', orderBy: 'LOWER(name) ASC');
  }

  static Future<Map<String, dynamic>?> getClientById(
    DatabaseExecutor db,
    int id,
  ) async {
    final r = await db.query(
      'clients',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isNotEmpty ? r.first : null;
  }

  static Future<int> insertClient(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) async {
    return db.insert(
      'clients',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<int> updateClient(
    DatabaseExecutor db,
    int id,
    Map<String, dynamic> data,
  ) async {
    return db.update(
      'clients',
      data,
      where: 'id=?',
      whereArgs: [id],
    );
  }

  static Future<int> deleteClient(
    DatabaseExecutor db,
    int id,
  ) async {
    return db.delete(
      'clients',
      where: 'id=?',
      whereArgs: [id],
    );
  }

  static Future<void> createActivationCodesTable(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activation_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_name TEXT NOT NULL,
        activation_code TEXT NOT NULL UNIQUE,
        is_used INTEGER DEFAULT 0,
        used_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activation_user '
      'ON activation_codes(user_name);',
    );
  }
}
