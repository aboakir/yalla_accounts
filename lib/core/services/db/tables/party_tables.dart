import 'package:sqflite/sqflite.dart';

/// Stage 1 — unified Party registry.
///
/// Existing customer/supplier/employee tables remain intact for a safe v69
/// migration. `party_roles` maps those legacy identities to one Party, which
/// lets one real-world entity be both CUSTOMER and SUPPLIER without rewriting
/// immutable historical GL rows.
class PartyTables {
  PartyTables._();

  static const supportedRoles = <String>{
    'CUSTOMER',
    'SUPPLIER',
    'EMPLOYEE',
  };

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static String canonicalRole(Object? raw) {
    final role = raw?.toString().trim().toUpperCase() ?? '';
    if (role == 'CLIENT') return 'CUSTOMER';
    return role;
  }

  static String canonicalLegacyId(String role, Object? raw) {
    var value = raw?.toString().trim() ?? '';
    final canonical = canonicalRole(role);
    if (canonical == 'CUSTOMER') {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed.toString();
    }
    if (canonical == 'SUPPLIER') {
      final upper = value.toUpperCase();
      if (upper.startsWith('S')) value = upper.substring(1);
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed.toString();
    }
    return value;
  }

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parties(
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        merged_into_id TEXT REFERENCES parties(id),
        created_at TEXT NOT NULL,
        updated_at TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS party_roles(
        party_id TEXT NOT NULL REFERENCES parties(id),
        role TEXT NOT NULL CHECK(role IN ('CUSTOMER','SUPPLIER','EMPLOYEE')),
        legacy_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY(role, legacy_id),
        UNIQUE(party_id, role)
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_party_roles_party ON party_roles(party_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_parties_active ON parties(is_active);',
    );

    await _backfillCustomers(db);
    await _backfillSuppliers(db);
    await _backfillEmployees(db);
    await _installMasterDataTriggers(db);
    await _createViews(db);
  }

  static Future<void> _backfillCustomers(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'clients')) return;
    await db.execute('''
      INSERT OR IGNORE INTO parties(id, display_name, created_at)
      SELECT 'CUSTOMER:' || CAST(id AS TEXT), name, datetime('now')
      FROM clients;
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO party_roles(party_id, role, legacy_id, created_at)
      SELECT 'CUSTOMER:' || CAST(id AS TEXT), 'CUSTOMER', CAST(id AS TEXT), datetime('now')
      FROM clients;
    ''');
  }

  static Future<void> _backfillSuppliers(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'suppliers')) return;
    await db.execute('''
      INSERT OR IGNORE INTO parties(id, display_name, created_at)
      SELECT 'SUPPLIER:' || CAST(id AS TEXT), name, datetime('now')
      FROM suppliers;
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO party_roles(party_id, role, legacy_id, created_at)
      SELECT 'SUPPLIER:' || CAST(id AS TEXT), 'SUPPLIER', CAST(id AS TEXT), datetime('now')
      FROM suppliers;
    ''');
  }

  static Future<void> _backfillEmployees(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'employees')) return;
    await db.execute('''
      INSERT OR IGNORE INTO parties(id, display_name, created_at)
      SELECT 'EMPLOYEE:' || id, full_name, datetime('now')
      FROM employees;
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO party_roles(party_id, role, legacy_id, created_at)
      SELECT 'EMPLOYEE:' || id, 'EMPLOYEE', id, datetime('now')
      FROM employees;
    ''');
  }

  static Future<void> _installMasterDataTriggers(DatabaseExecutor db) async {
    for (final entry
        in {'clients': 'CUSTOMER', 'suppliers': 'SUPPLIER'}.entries) {
      if (!await _tableExists(db, entry.key)) continue;
      await db
          .execute("""CREATE TRIGGER IF NOT EXISTS trg_party_${entry.key}_rename
        AFTER UPDATE OF name ON ${entry.key}
        BEGIN
          UPDATE parties SET display_name=NEW.name,updated_at=datetime('now')
          WHERE display_name=OLD.name AND id IN
            (SELECT party_id FROM party_roles WHERE role='${entry.value}' AND legacy_id=CAST(NEW.id AS TEXT));
        END;""");
      await db
          .execute("""CREATE TRIGGER IF NOT EXISTS trg_party_${entry.key}_delete
        AFTER DELETE ON ${entry.key}
        BEGIN
          DELETE FROM party_roles WHERE role='${entry.value}' AND legacy_id=CAST(OLD.id AS TEXT);
        END;""");
    }

    if (await _tableExists(db, 'clients')) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_party_customer_insert
        AFTER INSERT ON clients
        BEGIN
          INSERT OR IGNORE INTO parties(id, display_name, created_at)
          VALUES('CUSTOMER:' || CAST(NEW.id AS TEXT), NEW.name, datetime('now'));
          INSERT OR IGNORE INTO party_roles(party_id, role, legacy_id, created_at)
          VALUES('CUSTOMER:' || CAST(NEW.id AS TEXT), 'CUSTOMER', CAST(NEW.id AS TEXT), datetime('now'));
        END;
      ''');
    }

    if (await _tableExists(db, 'suppliers')) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_party_supplier_insert
        AFTER INSERT ON suppliers
        BEGIN
          INSERT OR IGNORE INTO parties(id, display_name, created_at)
          VALUES('SUPPLIER:' || CAST(NEW.id AS TEXT), NEW.name, datetime('now'));
          INSERT OR IGNORE INTO party_roles(party_id, role, legacy_id, created_at)
          VALUES('SUPPLIER:' || CAST(NEW.id AS TEXT), 'SUPPLIER', CAST(NEW.id AS TEXT), datetime('now'));
        END;
      ''');
    }

    if (await _tableExists(db, 'employees')) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_party_employee_insert
        AFTER INSERT ON employees
        BEGIN
          INSERT OR IGNORE INTO parties(id, display_name, created_at)
          VALUES('EMPLOYEE:' || NEW.id, NEW.full_name, datetime('now'));
          INSERT OR IGNORE INTO party_roles(party_id, role, legacy_id, created_at)
          VALUES('EMPLOYEE:' || NEW.id, 'EMPLOYEE', NEW.id, datetime('now'));
        END;
      ''');
    }
  }

  static Future<void> _createViews(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'gl_lines')) return;

    await db.execute('DROP VIEW IF EXISTS v_party_balances;');
    await db.execute('DROP VIEW IF EXISTS v_party_gl_lines;');

    await db.execute('''
      CREATE VIEW v_party_gl_lines AS
      SELECT
        l.id AS gl_line_id,
        l.entry_id,
        l.account_id,
        l.debit,
        l.credit,
        CASE
          WHEN UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER') THEN 'CUSTOMER'
          WHEN UPPER(COALESCE(l.party_type,''))='SUPPLIER' THEN 'SUPPLIER'
          WHEN UPPER(COALESCE(l.party_type,''))='EMPLOYEE' THEN 'EMPLOYEE'
          ELSE UPPER(COALESCE(l.party_type,''))
        END AS party_role,
        l.party_id AS legacy_party_id,
        pr.party_id AS canonical_party_id,
        l.invoice_id,
        l.repair_id,
        l.cheque_id
      FROM gl_lines l
      LEFT JOIN party_roles pr
        ON pr.role = CASE
          WHEN UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER') THEN 'CUSTOMER'
          WHEN UPPER(COALESCE(l.party_type,''))='SUPPLIER' THEN 'SUPPLIER'
          WHEN UPPER(COALESCE(l.party_type,''))='EMPLOYEE' THEN 'EMPLOYEE'
          ELSE UPPER(COALESCE(l.party_type,''))
        END
       AND pr.legacy_id = CASE
          WHEN UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
            THEN CAST(CAST(l.party_id AS INTEGER) AS TEXT)
          WHEN UPPER(COALESCE(l.party_type,''))='SUPPLIER'
            THEN CAST(CAST(
              CASE WHEN UPPER(COALESCE(l.party_id,'')) LIKE 'S%'
                   THEN SUBSTR(UPPER(l.party_id),2)
                   ELSE l.party_id END AS INTEGER) AS TEXT)
          ELSE l.party_id
        END;
    ''');

    await db.execute('''
      CREATE VIEW v_party_balances AS
      SELECT
        p.id AS party_id,
        p.display_name,
        COALESCE(SUM(CASE WHEN v.party_role='CUSTOMER' THEN v.debit-v.credit ELSE 0 END),0) AS receivable_balance,
        COALESCE(SUM(CASE WHEN v.party_role='SUPPLIER' THEN v.credit-v.debit ELSE 0 END),0) AS payable_balance,
        COALESCE(SUM(v.debit-v.credit),0) AS net_position
      FROM parties p
      LEFT JOIN v_party_gl_lines v ON v.canonical_party_id=p.id
      WHERE p.merged_into_id IS NULL
      GROUP BY p.id, p.display_name;
    ''');
  }

  static Future<String?> resolvePartyId(
    DatabaseExecutor db, {
    required String role,
    required Object legacyId,
  }) async {
    final canonical = canonicalRole(role);
    final id = canonicalLegacyId(canonical, legacyId);
    final rows = await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: [canonical, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['party_id']?.toString();
  }

  /// Reassigns a legacy CUSTOMER/SUPPLIER/EMPLOYEE role to an existing Party.
  /// Historical GL rows are not mutated; the Party views resolve them through
  /// this mapping, preserving ledger immutability.
  static Future<void> attachRoleToParty(
    DatabaseExecutor db, {
    required String targetPartyId,
    required String role,
    required Object legacyId,
  }) async {
    final canonical = canonicalRole(role);
    if (!supportedRoles.contains(canonical)) {
      throw ArgumentError('Unsupported Party role: $role');
    }
    final id = canonicalLegacyId(canonical, legacyId);
    final target = await db.query(
      'parties',
      columns: const ['id'],
      where: 'id=? AND merged_into_id IS NULL',
      whereArgs: [targetPartyId],
      limit: 1,
    );
    if (target.isEmpty) {
      throw StateError('Target Party does not exist: $targetPartyId');
    }

    final conflict = await db.query(
      'party_roles',
      where: 'party_id=? AND role=? AND legacy_id<>?',
      whereArgs: [targetPartyId, canonical, id],
      limit: 1,
    );
    if (conflict.isNotEmpty) {
      throw StateError(
        'Party $targetPartyId already owns another $canonical role.',
      );
    }

    final current = await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: [canonical, id],
      limit: 1,
    );
    if (current.isEmpty) {
      throw StateError('Legacy Party role not found: $canonical:$id');
    }

    final oldPartyId = current.first['party_id']!.toString();
    if (oldPartyId == targetPartyId) return;

    await db.update(
      'party_roles',
      {'party_id': targetPartyId},
      where: 'role=? AND legacy_id=?',
      whereArgs: [canonical, id],
    );

    final remaining = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM party_roles WHERE party_id=?',
      [oldPartyId],
    );
    final count = (remaining.first['c'] as num?)?.toInt() ?? 0;
    if (count == 0) {
      await db.update(
        'parties',
        {
          'is_active': 0,
          'merged_into_id': targetPartyId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [oldPartyId],
      );
    }
  }
}
