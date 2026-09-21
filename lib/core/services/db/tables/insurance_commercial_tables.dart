import 'package:sqflite/sqflite.dart';

/// DB v85 — commercial insurance foundation.
///
/// Additive/idempotent schema only. Historical insurance rows are preserved.
/// Accounting remains in the canonical GL/receipt/voucher/cheque cores.
class InsuranceCommercialTables {
  InsuranceCommercialTables._();

  static const _insuranceRoles = <String>[
    'CUSTOMER',
    'SUPPLIER',
    'EMPLOYEE',
    'INSURED',
    'INSURANCE_COMPANY',
    'PRODUCER',
    'PROSPECT',
  ];

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _columnExists(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    if (!await _tableExists(db, table)) return false;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name']?.toString() == column);
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    if (!await _columnExists(db, table, column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  static Future<void> ensure(DatabaseExecutor db) async {
    await _expandPartyRoles(db);
    await _extendPolicyAggregate(db);
    await _createMasterData(db);
    await backfillLegacyCompanyParties(db);
    await _createCrm(db);
    await _createQuotes(db);
    await _createPolicyHistory(db);
    await _createClaimsAndRenewals(db);
    await _createSettlementsAndFinancialLinks(db);
    await _createIndexes(db);
  }

  static Future<void> _expandPartyRoles(DatabaseExecutor db) async {
    final exists = await _tableExists(db, 'party_roles');
    if (!exists) return;

    final row = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='party_roles'",
    );
    final sql = row.isEmpty ? '' : (row.first['sql'] ?? '').toString();
    if (sql.contains('INSURANCE_COMPANY') && sql.contains('PROSPECT')) return;

    for (final trigger in <String>[
      'trg_party_roles_projection_insert',
      'trg_party_roles_projection_update',
      'trg_party_roles_projection_delete',
      'trg_party_clients_rename',
      'trg_party_clients_delete',
      'trg_party_suppliers_rename',
      'trg_party_suppliers_delete',
      'trg_party_customer_insert',
      'trg_party_supplier_insert',
      'trg_party_employee_insert',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }

    // Views reference party_roles by name. Rename-first would make SQLite
    // rewrite those view definitions to the temporary table name, leaving an
    // invalid schema after the old table is dropped. Copy/swap avoids that.
    await db.execute('DROP VIEW IF EXISTS v_party_balances');
    await db.execute('DROP VIEW IF EXISTS v_party_gl_lines');
    await db.execute('DROP TABLE IF EXISTS party_roles_v85');
    final allowed = _insuranceRoles.map((r) => "'$r'").join(',');
    await db.execute('''
      CREATE TABLE party_roles_v85(
        party_id TEXT NOT NULL REFERENCES parties(id),
        role TEXT NOT NULL CHECK(role IN ($allowed)),
        legacy_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY(role, legacy_id),
        UNIQUE(party_id, role)
      )
    ''');
    await db.execute('''
      INSERT INTO party_roles_v85(party_id,role,legacy_id,created_at)
      SELECT party_id,role,legacy_id,created_at FROM party_roles
    ''');
    await db.execute('DROP TABLE party_roles');
    await db.execute('ALTER TABLE party_roles_v85 RENAME TO party_roles');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_party_roles_party ON party_roles(party_id)',
    );
  }

  static Future<void> _extendPolicyAggregate(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'insurance_policies')) return;

    final columns = <String, String>{
      'operation_id': 'TEXT',
      'policy_number': 'TEXT',
      'status': "TEXT NOT NULL DEFAULT 'DRAFT'",
      'client_id': 'INTEGER',
      'insured_party_id': 'TEXT',
      'vehicle_id': 'INTEGER',
      'insurance_company_id': 'TEXT',
      'insurer_party_id': 'TEXT',
      'insurer_supplier_id': 'INTEGER',
      'product_id': 'TEXT',
      'base_premium': 'REAL NOT NULL DEFAULT 0',
      'discount': 'REAL NOT NULL DEFAULT 0',
      'fees': 'REAL NOT NULL DEFAULT 0',
      'tax': 'REAL NOT NULL DEFAULT 0',
      'commission_rate': 'REAL NOT NULL DEFAULT 0',
      'commission_amount': 'REAL NOT NULL DEFAULT 0',
      'direct_cost': 'REAL NOT NULL DEFAULT 0',
      'net_sale_amount': 'REAL NOT NULL DEFAULT 0',
      'net_insurer_payable': 'REAL NOT NULL DEFAULT 0',
      'gross_profit': 'REAL NOT NULL DEFAULT 0',
      'markup_percent': 'REAL NOT NULL DEFAULT 0',
      'margin_percent': 'REAL NOT NULL DEFAULT 0',
      'currency': "TEXT NOT NULL DEFAULT 'ILS'",
      'posting_key': 'TEXT',
      'gl_entry_id': 'INTEGER',
      'posting_status': "TEXT NOT NULL DEFAULT 'DRAFT'",
      'posted_at': 'TEXT',
      'created_by': 'TEXT',
      'updated_by': 'TEXT',
      'reversal_gl_entry_id': 'INTEGER',
      'reversed_at': 'TEXT',
      'previous_policy_id': 'TEXT',
      'version_no': 'INTEGER NOT NULL DEFAULT 1',
    };
    for (final entry in columns.entries) {
      await _ensureColumn(db, 'insurance_policies', entry.key, entry.value);
    }
  }

  static Future<void> _createMasterData(DatabaseExecutor db) async {
    // insurance_companies already exists in the workshop module since v1
    // as (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE). Extend it
    // in place so old repair/company references remain valid.
    if (!await _tableExists(db, 'insurance_companies')) {
      await db.execute('''
        CREATE TABLE insurance_companies(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
        )
      ''');
    }
    final companyColumns = <String, String>{
      'party_id': 'TEXT',
      'supplier_id': 'INTEGER',
      'code': 'TEXT',
      'phone': 'TEXT',
      'address': 'TEXT',
      'default_commission_rate': 'REAL NOT NULL DEFAULT 0',
      'pricing_rules_json': 'TEXT',
      'is_active': 'INTEGER NOT NULL DEFAULT 1',
      'created_at': 'TEXT',
      'updated_at': 'TEXT',
    };
    for (final entry in companyColumns.entries) {
      await _ensureColumn(db, 'insurance_companies', entry.key, entry.value);
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_insurance_company_code '
      'ON insurance_companies(code) WHERE code IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_insurance_company_party '
      'ON insurance_companies(party_id) WHERE party_id IS NOT NULL',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_products(
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES insurance_companies(id),
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        product_type TEXT NOT NULL,
        default_commission_rate REAL NOT NULL DEFAULT 0,
        pricing_rules_json TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id,code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_coverages(
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES insurance_products(id),
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        deductible REAL NOT NULL DEFAULT 0,
        limit_amount REAL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(product_id,code)
      )
    ''');
  }

  /// Links every legacy workshop insurance-company row to the canonical
  /// Supplier/Party master without replacing its historical integer id.
  static Future<void> _normalizeExistingCompanyParties(
    DatabaseExecutor db,
  ) async {
    if (!await _tableExists(db, 'insurance_companies')) return;
    final rows = await db.query(
      'insurance_companies',
      columns: const ['id', 'name', 'party_id', 'supplier_id', 'code'],
      orderBy: 'id ASC',
    );
    for (final company in rows) {
      final id = company['id'];
      final name = (company['name'] ?? '').toString().trim();
      if (id == null || name.isEmpty) continue;

      int? supplierId = (company['supplier_id'] as num?)?.toInt();
      if (supplierId == null || supplierId <= 0) {
        final suppliers = await db.query(
          'suppliers',
          columns: const ['id'],
          where: 'TRIM(name)=?',
          whereArgs: [name],
          orderBy: 'id ASC',
          limit: 1,
        );
        if (suppliers.isNotEmpty) {
          supplierId = (suppliers.single['id'] as num).toInt();
        } else {
          supplierId = await db.insert(
              'suppliers',
              {
                'name': name,
              },
              conflictAlgorithm: ConflictAlgorithm.abort);
        }
      }

      var partyRows = await db.query(
        'party_roles',
        columns: const ['party_id'],
        where: 'role=? AND legacy_id=?',
        whereArgs: ['SUPPLIER', supplierId.toString()],
        limit: 1,
      );
      if (partyRows.isEmpty) {
        final partyId = 'SUPPLIER:$supplierId';
        await db.insert(
            'parties',
            {
              'id': partyId,
              'display_name': name,
              'role_codes': '["SUPPLIER"]',
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert(
            'party_roles',
            {
              'party_id': partyId,
              'role': 'SUPPLIER',
              'legacy_id': supplierId.toString(),
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        partyRows = [
          {'party_id': partyId},
        ];
      }
      final partyId = partyRows.single['party_id'].toString();

      await db.insert(
          'party_roles',
          {
            'party_id': partyId,
            'role': 'INSURANCE_COMPANY',
            'legacy_id': id.toString(),
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      final rawCode = (company['code'] ?? '').toString().trim();
      final code =
          rawCode.isEmpty ? 'INS-${id.toString().padLeft(4, '0')}' : rawCode;
      final now = DateTime.now().toIso8601String();
      await db.update(
        'insurance_companies',
        {
          'party_id': partyId,
          'supplier_id': supplierId,
          'code': code,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [id],
      );
    }
  }

  /// Converts legacy free-text company_name values into canonical supplier +
  /// Party Master + insurance company records. Safe to run repeatedly.
  static Future<void> backfillLegacyCompanyParties(DatabaseExecutor db) async {
    await _normalizeExistingCompanyParties(db);
    if (!await _tableExists(db, 'insurance_policies') ||
        !await _tableExists(db, 'suppliers') ||
        !await _tableExists(db, 'parties') ||
        !await _tableExists(db, 'party_roles')) {
      return;
    }

    final rows = await db.rawQuery('''
      SELECT DISTINCT TRIM(company_name) AS company_name
      FROM insurance_policies
      WHERE TRIM(COALESCE(company_name,'')) <> ''
      ORDER BY company_name
    ''');
    final now = DateTime.now().toIso8601String();

    for (final row in rows) {
      final name = (row['company_name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final existingCompany = await db.rawQuery(
        '''SELECT id,party_id,supplier_id FROM insurance_companies
           WHERE TRIM(name)=? COLLATE NOCASE LIMIT 1''',
        [name],
      );
      if (existingCompany.isNotEmpty) {
        final company = existingCompany.single;
        await db.update(
          'insurance_policies',
          {
            'insurance_company_id': company['id'],
            'insurer_party_id': company['party_id'],
            'insurer_supplier_id': company['supplier_id'],
          },
          where:
              "TRIM(company_name)=? COLLATE NOCASE AND insurance_company_id IS NULL",
          whereArgs: [name],
        );
        continue;
      }

      var suppliers = await db.rawQuery(
        'SELECT id,name FROM suppliers WHERE TRIM(name)=? COLLATE NOCASE LIMIT 1',
        [name],
      );
      late int supplierId;
      if (suppliers.isEmpty) {
        supplierId = await db.insert(
            'suppliers',
            {
              'name': name,
            },
            conflictAlgorithm: ConflictAlgorithm.abort);
        await db.update(
          'suppliers',
          {'pid': 'S${supplierId.toString().padLeft(4, '0')}'},
          where: 'id=?',
          whereArgs: [supplierId],
        );
      } else {
        supplierId = (suppliers.single['id'] as num).toInt();
      }

      final supplierRole = await db.query(
        'party_roles',
        columns: const ['party_id'],
        where: 'role=? AND legacy_id=?',
        whereArgs: ['SUPPLIER', supplierId.toString()],
        limit: 1,
      );
      final partyId = supplierRole.isNotEmpty
          ? supplierRole.single['party_id'].toString()
          : 'SUPPLIER:$supplierId';

      await db.insert(
          'parties',
          {
            'id': partyId,
            'display_name': name,
            'role_codes': '["SUPPLIER"]',
            'is_active': 1,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert(
          'party_roles',
          {
            'party_id': partyId,
            'role': 'SUPPLIER',
            'legacy_id': supplierId.toString(),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      final companyId = 'INSCO:$supplierId';
      final code = 'INS-${supplierId.toString().padLeft(4, '0')}';
      await db.insert(
          'insurance_companies',
          {
            'id': companyId,
            'party_id': partyId,
            'supplier_id': supplierId,
            'code': code,
            'name': name,
            'default_commission_rate': 0.0,
            'is_active': 1,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert(
          'party_roles',
          {
            'party_id': partyId,
            'role': 'INSURANCE_COMPANY',
            'legacy_id': companyId,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.update(
        'insurance_policies',
        {
          'insurance_company_id': companyId,
          'insurer_party_id': partyId,
          'insurer_supplier_id': supplierId,
        },
        where:
            "TRIM(company_name)=? COLLATE NOCASE AND insurance_company_id IS NULL",
        whereArgs: [name],
      );
    }
  }

  static Future<void> _createCrm(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_prospects(
        id TEXT PRIMARY KEY,
        party_id TEXT NOT NULL REFERENCES parties(id),
        status TEXT NOT NULL,
        city TEXT,
        source TEXT,
        responsible_user_id TEXT,
        current_company TEXT,
        current_policy_expiry TEXT,
        last_contact_at TEXT,
        next_contact_at TEXT,
        contact_result TEXT,
        tags_json TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(party_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_driver_licenses(
        id TEXT PRIMARY KEY,
        party_id TEXT NOT NULL REFERENCES parties(id),
        license_number TEXT NOT NULL,
        license_type TEXT,
        issue_date TEXT,
        expiry_date TEXT,
        categories_json TEXT,
        documents_json TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(party_id,license_number)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_contacts(
        id TEXT PRIMARY KEY,
        party_id TEXT NOT NULL REFERENCES parties(id),
        contact_at TEXT NOT NULL,
        channel TEXT NOT NULL,
        result TEXT,
        notes TEXT,
        next_follow_up_at TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_tasks(
        id TEXT PRIMARY KEY,
        party_id TEXT REFERENCES parties(id),
        policy_id TEXT REFERENCES insurance_policies(id),
        task_type TEXT NOT NULL,
        due_at TEXT,
        status TEXT NOT NULL DEFAULT 'OPEN',
        assigned_to TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createQuotes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_quotes(
        id TEXT PRIMARY KEY,
        quote_number TEXT,
        prospect_id TEXT REFERENCES insurance_prospects(id),
        party_id TEXT NOT NULL REFERENCES parties(id),
        client_id INTEGER REFERENCES clients(id),
        vehicle_id INTEGER REFERENCES vehicles(id),
        status TEXT NOT NULL DEFAULT 'DRAFT',
        requested_at TEXT NOT NULL,
        accepted_item_id TEXT,
        notes TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(quote_number)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_quote_items(
        id TEXT PRIMARY KEY,
        quote_id TEXT NOT NULL REFERENCES insurance_quotes(id) ON DELETE CASCADE,
        company_id TEXT NOT NULL REFERENCES insurance_companies(id),
        product_id TEXT REFERENCES insurance_products(id),
        premium REAL NOT NULL DEFAULT 0,
        deductible REAL NOT NULL DEFAULT 0,
        commission_rate REAL NOT NULL DEFAULT 0,
        commission_amount REAL NOT NULL DEFAULT 0,
        final_price REAL NOT NULL DEFAULT 0,
        coverage_json TEXT,
        status TEXT NOT NULL DEFAULT 'OFFERED',
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createPolicyHistory(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_policy_versions(
        id TEXT PRIMARY KEY,
        policy_id TEXT NOT NULL REFERENCES insurance_policies(id),
        version_no INTEGER NOT NULL,
        snapshot_json TEXT NOT NULL,
        reason TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(policy_id,version_no)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_endorsements(
        id TEXT PRIMARY KEY,
        policy_id TEXT NOT NULL REFERENCES insurance_policies(id),
        endorsement_type TEXT NOT NULL,
        effective_date TEXT NOT NULL,
        delta_sale REAL NOT NULL DEFAULT 0,
        delta_cost REAL NOT NULL DEFAULT 0,
        delta_tax REAL NOT NULL DEFAULT 0,
        gl_entry_id INTEGER,
        reversal_gl_entry_id INTEGER,
        status TEXT NOT NULL DEFAULT 'DRAFT',
        payload_json TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        posted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_commissions(
        id TEXT PRIMARY KEY,
        policy_id TEXT NOT NULL REFERENCES insurance_policies(id),
        company_id TEXT REFERENCES insurance_companies(id),
        producer_party_id TEXT REFERENCES parties(id),
        commission_rate REAL NOT NULL DEFAULT 0,
        commission_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'ACCRUED',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createClaimsAndRenewals(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_claims(
        id TEXT PRIMARY KEY,
        claim_number TEXT,
        policy_id TEXT NOT NULL REFERENCES insurance_policies(id),
        insured_party_id TEXT REFERENCES parties(id),
        vehicle_id INTEGER REFERENCES vehicles(id),
        company_id TEXT REFERENCES insurance_companies(id),
        status TEXT NOT NULL DEFAULT 'NEW',
        loss_date TEXT,
        reported_at TEXT NOT NULL,
        financial_event_id TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(claim_number)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_claim_documents(
        id TEXT PRIMARY KEY,
        claim_id TEXT NOT NULL REFERENCES insurance_claims(id) ON DELETE CASCADE,
        document_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_renewals(
        id TEXT PRIMARY KEY,
        policy_id TEXT NOT NULL REFERENCES insurance_policies(id),
        previous_policy_id TEXT REFERENCES insurance_policies(id),
        renewal_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        last_contact_at TEXT,
        next_contact_at TEXT,
        outcome TEXT,
        new_policy_id TEXT REFERENCES insurance_policies(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(policy_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_alerts(
        id TEXT PRIMARY KEY,
        alert_type TEXT NOT NULL,
        party_id TEXT REFERENCES parties(id),
        policy_id TEXT REFERENCES insurance_policies(id),
        claim_id TEXT REFERENCES insurance_claims(id),
        due_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'OPEN',
        severity TEXT NOT NULL DEFAULT 'NORMAL',
        message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createSettlementsAndFinancialLinks(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_settlements(
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES insurance_companies(id),
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        gross_policies REAL NOT NULL DEFAULT 0,
        cancellations REAL NOT NULL DEFAULT 0,
        commission REAL NOT NULL DEFAULT 0,
        previous_payments REAL NOT NULL DEFAULT 0,
        payable REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'DRAFT',
        payment_voucher_id TEXT,
        created_at TEXT NOT NULL,
        posted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_settlement_items(
        id TEXT PRIMARY KEY,
        settlement_id TEXT NOT NULL REFERENCES insurance_settlements(id) ON DELETE CASCADE,
        policy_id TEXT REFERENCES insurance_policies(id),
        item_type TEXT NOT NULL,
        amount REAL NOT NULL,
        source_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_policy_payments(
        id TEXT PRIMARY KEY,
        policy_id TEXT REFERENCES insurance_policies(id),
        settlement_id TEXT REFERENCES insurance_settlements(id),
        direction TEXT NOT NULL CHECK(direction IN ('CUSTOMER_RECEIPT','INSURER_PAYMENT','REFUND')),
        receipt_number INTEGER,
        payment_id TEXT,
        voucher_id TEXT,
        cheque_id INTEGER,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'ILS',
        status TEXT NOT NULL DEFAULT 'POSTED',
        created_at TEXT NOT NULL,
        UNIQUE(direction,receipt_number,payment_id),
        UNIQUE(direction,voucher_id,policy_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_financial_events(
        id TEXT PRIMARY KEY,
        event_key TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_id TEXT NOT NULL,
        policy_id TEXT REFERENCES insurance_policies(id),
        amount REAL NOT NULL DEFAULT 0,
        gl_entry_id INTEGER,
        reversal_of_event_id TEXT REFERENCES insurance_financial_events(id),
        status TEXT NOT NULL DEFAULT 'POSTED',
        payload_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_period_closes(
        id TEXT PRIMARY KEY,
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        closed_at TEXT NOT NULL,
        closed_by TEXT,
        status TEXT NOT NULL DEFAULT 'CLOSED',
        reconciliation_json TEXT NOT NULL,
        UNIQUE(period_start,period_end)
      )
    ''');
  }

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_insurance_policy_operation '
      'ON insurance_policies(operation_id) WHERE operation_id IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_insurance_policy_number '
      'ON insurance_policies(policy_number) '
      'WHERE policy_number IS NOT NULL AND TRIM(policy_number)<>""',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_insurance_policy_posting '
      'ON insurance_policies(posting_key) '
      'WHERE posting_key IS NOT NULL AND TRIM(posting_key)<>""',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_policy_client '
      'ON insurance_policies(client_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_policy_company '
      'ON insurance_policies(insurance_company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_policy_expiry '
      'ON insurance_policies(end_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_alert_due '
      'ON insurance_alerts(status,due_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_prospect_followup '
      'ON insurance_prospects(status,next_contact_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_claim_policy '
      'ON insurance_claims(policy_id,status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_payment_policy '
      'ON insurance_policy_payments(policy_id,direction)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_fin_event_policy '
      'ON insurance_financial_events(policy_id,event_type)',
    );
  }
}
