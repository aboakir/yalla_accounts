// -----------------------------------------------------------------------------
// lib/core/services/db/tables/cheque_tables.dart
// P0.008 — canonical cheque schema / lifecycle support
// -----------------------------------------------------------------------------

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class ChequeTables {
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createChequeTable(db);
    await ensureChequesSchema(db);
  }

  static Future<void> _createChequeTable(DatabaseExecutor db) async {
    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheques (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT,
        cheque_no TEXT,
        cheque_type TEXT NOT NULL DEFAULT 'incoming',
        status TEXT NOT NULL DEFAULT 'pending',
        drawer_name TEXT,
        bank_name TEXT,
        bank_branch TEXT,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'ILS',
        issue_date TEXT,
        due_date TEXT,
        source_type TEXT,
        source_id TEXT,
        supplier_pid TEXT,
        client_id INTEGER,
        recipient_type TEXT,
        recipient_id TEXT,
        recipient_name TEXT,
        linked_payment_ids TEXT,
        linked_repair_ids TEXT,
        gl_entry_id INTEGER,
        notes TEXT,
        origin_cheque_id TEXT,
        is_endorsed INTEGER NOT NULL DEFAULT 0,
        endorsed_at TEXT,
        last_endorser_name TEXT,
        auto_return_date TEXT,
        return_reason TEXT,
        is_legacy_incomplete INTEGER NOT NULL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,

        -- Compatibility aliases for old code/data.
        supplier_id INTEGER,
        payment_id TEXT,
        date TEXT,
        bank TEXT,
        number TEXT
      )
    ''');
  }

  static Future<void> ensureChequesSchema(DatabaseExecutor db) async {
    await _createChequeTable(db);

    final columns = <String, String>{
      'uuid': 'TEXT',
      'cheque_no': 'TEXT',
      'cheque_type': "TEXT NOT NULL DEFAULT 'incoming'",
      'status': "TEXT NOT NULL DEFAULT 'pending'",
      'drawer_name': 'TEXT',
      'bank_name': 'TEXT',
      'bank_branch': 'TEXT',
      'currency': "TEXT NOT NULL DEFAULT 'ILS'",
      'issue_date': 'TEXT',
      'due_date': 'TEXT',
      'source_type': 'TEXT',
      'source_id': 'TEXT',
      'supplier_pid': 'TEXT',
      'client_id': 'INTEGER',
      'recipient_type': 'TEXT',
      'recipient_id': 'TEXT',
      'recipient_name': 'TEXT',
      'linked_payment_ids': 'TEXT',
      'linked_repair_ids': 'TEXT',
      'gl_entry_id': 'INTEGER',
      'notes': 'TEXT',
      'origin_cheque_id': 'TEXT',
      'is_endorsed': 'INTEGER NOT NULL DEFAULT 0',
      'endorsed_at': 'TEXT',
      'last_endorser_name': 'TEXT',
      'auto_return_date': 'TEXT',
      'return_reason': 'TEXT',
      'is_legacy_incomplete': 'INTEGER NOT NULL DEFAULT 0',
      'created_at': 'TEXT',
      'updated_at': 'TEXT',
      'supplier_id': 'INTEGER',
      'payment_id': 'TEXT',
      'date': 'TEXT',
      'bank': 'TEXT',
      'number': 'TEXT',
    };

    for (final entry in columns.entries) {
      await _ensureColumn(db, 'cheques', entry.key, entry.value);
    }

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS cheque_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cheque_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        from_status TEXT,
        to_status TEXT,
        event_date TEXT NOT NULL,
        gl_entry_id INTEGER,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Normalize legacy aliases. Never invent missing cheque metadata.
    await db.execute(r'''
      UPDATE cheques
      SET uuid = COALESCE(NULLIF(uuid,''), 'legacy-cheque-' || id),
          cheque_no = COALESCE(NULLIF(cheque_no,''), number, ''),
          bank_name = COALESCE(NULLIF(bank_name,''), bank, ''),
          issue_date = COALESCE(NULLIF(issue_date,''), date, due_date),
          supplier_pid = COALESCE(
            NULLIF(supplier_pid,''),
            CASE WHEN supplier_id IS NULL THEN NULL
                 ELSE CAST(supplier_id AS TEXT) END
          ),
          source_type = COALESCE(
            NULLIF(source_type,''),
            CASE WHEN payment_id IS NULL OR TRIM(payment_id)=''
                 THEN NULL ELSE 'PAYMENT' END
          ),
          source_id = COALESCE(NULLIF(source_id,''), payment_id),
          cheque_type = CASE
            WHEN supplier_id IS NOT NULL THEN 'outgoing'
            WHEN cheque_type IS NULL OR TRIM(cheque_type)='' THEN 'incoming'
            ELSE cheque_type
          END,
          currency = COALESCE(NULLIF(currency,''), 'ILS'),
          is_legacy_incomplete = CASE
            WHEN COALESCE(NULLIF(cheque_no,''), NULLIF(number,''), '')=''
              OR COALESCE(NULLIF(bank_name,''), NULLIF(bank,''), '')=''
              OR COALESCE(NULLIF(drawer_name,''), '')=''
            THEN 1 ELSE COALESCE(is_legacy_incomplete,0)
          END,
          created_at = COALESCE(created_at, datetime('now')),
          updated_at = COALESCE(updated_at, datetime('now'))
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_status ON cheques(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_due_date ON cheques(due_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_client ON cheques(client_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_supplier_pid '
      'ON cheques(supplier_pid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheques_source '
      'ON cheques(source_type, source_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cheque_events_cheque '
      'ON cheque_events(cheque_id, id)',
    );
    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_cheques_uuid
      ON cheques(uuid)
      WHERE uuid IS NOT NULL AND TRIM(uuid) <> ''
    ''');
    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_cheques_source
      ON cheques(source_type, source_id)
      WHERE source_type IS NOT NULL
        AND TRIM(source_type) <> ''
        AND source_id IS NOT NULL
        AND TRIM(source_id) <> ''
    ''');

    await _ensureChequeAccounts(db);
  }

  static Future<void> _ensureChequeAccounts(DatabaseExecutor db) async {
    await _ensureAccount(
      db,
      code: '1020',
      name: 'شيكات واردة',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
    await _ensureAccount(
      db,
      code: '1030',
      name: 'شيكات صادرة / أوراق دفع',
      type: 'LIABILITY',
      normalBalance: 'CREDIT',
    );
  }

  static Future<int> _ensureAccount(
    DatabaseExecutor db, {
    required String code,
    required String name,
    required String type,
    required String normalBalance,
  }) async {
    final existing = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final value = existing.first['id'];
      return value is int ? value : int.parse(value.toString());
    }

    return db.insert(
      'accounts',
      {
        'code': code,
        'name': name,
        'type': type,
        'normal_balance': normalBalance,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String col,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (!info.any((row) => row['name'] == col)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $col $type');
    }
  }

  static Future<int> createCheque(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) async {
    await ensureChequesSchema(db);
    return db.insert(
      'cheques',
      data,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<void> updateChequeStatus(
    DatabaseExecutor db,
    int chequeId,
    String status,
  ) async {
    await db.update(
      'cheques',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );
  }

  static Future<void> linkChequeToPayment(
    DatabaseExecutor db,
    int chequeId,
    String paymentId,
  ) async {
    await db.update(
      'cheques',
      {
        'payment_id': paymentId,
        'source_type': 'PAYMENT',
        'source_id': paymentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );
  }

  static Future<void> addLinkedPayment(
    DatabaseExecutor db,
    int chequeId,
    String paymentId,
  ) async {
    final rows = await db.query(
      'cheques',
      columns: ['linked_payment_ids'],
      where: 'id=?',
      whereArgs: [chequeId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final ids = <String>[];
    final raw = rows.first['linked_payment_ids']?.toString() ?? '';
    if (raw.trim().isNotEmpty) {
      try {
        ids.addAll(List<String>.from(jsonDecode(raw)));
      } catch (_) {}
    }
    if (!ids.contains(paymentId)) ids.add(paymentId);

    await db.update(
      'cheques',
      {
        'linked_payment_ids': jsonEncode(ids),
        'payment_id': paymentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingCheques(
    DatabaseExecutor db,
  ) async {
    await ensureChequesSchema(db);
    return db.query(
      'cheques',
      where: 'status=?',
      whereArgs: ['pending'],
      orderBy: 'due_date ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getChequesByClient(
    DatabaseExecutor db,
    int clientId,
  ) async {
    await ensureChequesSchema(db);
    return db.query(
      'cheques',
      where: 'client_id=?',
      whereArgs: [clientId],
      orderBy: 'issue_date DESC',
    );
  }

  // P0.008: maturity is NOT a returned/bounced event.
  // A due cheque remains pending until a user records an actual lifecycle event.
  static Future<void> checkAutoChequeReturns() async {
    final db = await DBService.database;
    await ensureChequesSchema(db);
  }

  static Future<int> createVoucher(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) {
    return db.insert('vouchers', data);
  }
}
