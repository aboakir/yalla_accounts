// ============================================================================
// 📁 lib/core/services/db/tables/insurance_tables.dart
// InsuranceTables — v1 (FINAL) + IMAGE COLUMN MIGRATION
// ============================================================================

import 'dart:convert';
import 'package:sqflite/sqflite.dart';

class InsuranceTables {
  // ==========================================================================
  // CREATE ALL TABLES
  // ==========================================================================

  static Future<void> createAllTables(Database db) async {
    await createTables(db);
    await ensureInsuranceSchema(db);
  }

  static Future<void> createTables(Database db) async {
    // ======================================================================
    // insurance_policies
    // ======================================================================
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_policies (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        vehicle_plate TEXT NOT NULL,
        vehicle_make TEXT NOT NULL,
        vehicle_model_year TEXT NOT NULL,
        engine_cc TEXT NOT NULL,

        insured_name TEXT NOT NULL,
        insured_phone TEXT NOT NULL,

        company_name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        is_vip INTEGER NOT NULL DEFAULT 0,

        buy_price REAL NOT NULL DEFAULT 0,
        sell_price REAL NOT NULL DEFAULT 0,

        payment_type TEXT NOT NULL,
        cash_amount REAL NOT NULL DEFAULT 0,

        vehicle_images TEXT,

        notes TEXT
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_policies_plate ON insurance_policies(vehicle_plate);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_policies_company ON insurance_policies(company_name);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_policies_dates ON insurance_policies(start_date, end_date);',
    );

    // ======================================================================
    // insurance_policy_cheques
    // ======================================================================
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_policy_cheques (
        id TEXT PRIMARY KEY,
        policy_id TEXT NOT NULL,

        amount REAL NOT NULL DEFAULT 0,
        issue_date TEXT,
        due_date TEXT,

        bank_name TEXT,
        drawer_name TEXT,
        cheque_number TEXT,

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY(policy_id) REFERENCES insurance_policies(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_policy_cheques_policy ON insurance_policy_cheques(policy_id);',
    );

    // ======================================================================
    // insurance_policy_installments
    // ======================================================================
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_policy_installments (
        id TEXT PRIMARY KEY,
        policy_id TEXT NOT NULL,

        amount REAL NOT NULL DEFAULT 0,
        due_date TEXT,
        note TEXT,

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY(policy_id) REFERENCES insurance_policies(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_policy_installments_policy ON insurance_policy_installments(policy_id);',
    );

    // ======================================================================
    // insurance_policy_promissories
    // ======================================================================
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_policy_promissories (
        id TEXT PRIMARY KEY,
        policy_id TEXT NOT NULL,

        amount REAL NOT NULL DEFAULT 0,
        due_date TEXT,
        image_path TEXT,

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY(policy_id) REFERENCES insurance_policies(id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_policy_promissories_policy ON insurance_policy_promissories(policy_id);',
    );

    // ======================================================================
    // insurance_invoices — canonical schema for the workshop insurance module
    // ======================================================================
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL,
        client_name TEXT NOT NULL,
        insurance_company TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        date TEXT NOT NULL,
        status TEXT NOT NULL
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_invoices_date ON insurance_invoices(date);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_invoices_status ON insurance_invoices(status);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_insurance_invoices_company ON insurance_invoices(insurance_company);',
    );
  }

  // ==========================================================================
  // INSERT POLICY
  // ==========================================================================
  static Future<int> insertPolicy(
    Database db,
    Map<String, dynamic> data,
  ) async {
    await ensureInsuranceSchema(db);

    return db.insert(
      'insurance_policies',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================================================
  // INSERT CHEQUES
  // ==========================================================================
  static Future<int> insertPolicyCheque(
    Database db,
    Map<String, dynamic> data,
  ) async {
    await ensureInsuranceSchema(db);

    return db.insert(
      'insurance_policy_cheques',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================================================
  // INSERT INSTALLMENTS
  // ==========================================================================
  static Future<int> insertPolicyInstallment(
    Database db,
    Map<String, dynamic> data,
  ) async {
    await ensureInsuranceSchema(db);

    return db.insert(
      'insurance_policy_installments',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================================================
  // INSERT PROMISSORIES
  // ==========================================================================
  static Future<int> insertPolicyPromissory(
    Database db,
    Map<String, dynamic> data,
  ) async {
    await ensureInsuranceSchema(db);

    return db.insert(
      'insurance_policy_promissories',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================================================
  // ✅ SAFE UPDATE: تحديث صور البوليصة على insurance_policies بالـ id فقط
  // (لمنع خطأ: no such column policy_id / uuid)
  // ==========================================================================
  static Future<int> updatePolicyImagesById(
    Database db, {
    required String policyId,
    required List<String> images,
    String column = 'vehicle_images',
  }) async {
    await ensureInsuranceSchema(db);

    return db.update(
      'insurance_policies',
      {column: jsonEncode(images)},
      where: 'id = ?',
      whereArgs: [policyId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ==========================================================================
  // ENSURE SCHEMA (BACKWARD COMPATIBLE)
  // ==========================================================================
  static Future<void> ensureInsuranceSchema(Database db) async {
    // 0) insurance_policies — ADD vehicle_images if missing
    final policiesCols =
        await db.rawQuery("PRAGMA table_info(insurance_policies)");

    final hasPoliciesTable = policiesCols.isNotEmpty;
    final hasVehicleImages = policiesCols.any(
      (c) => (c['name'] ?? '').toString() == 'vehicle_images',
    );

    if (hasPoliciesTable && !hasVehicleImages) {
      await db.execute(
        "ALTER TABLE insurance_policies ADD COLUMN vehicle_images TEXT;",
      );
    }

    // 1) insurance_policy_cheques  (REBUILD IF MISSING updated_at)
    final chequeCols =
        await db.rawQuery("PRAGMA table_info(insurance_policy_cheques)");

    final hasChequeTable = chequeCols.isNotEmpty;
    final hasChequeUpdatedAt = chequeCols.any(
      (c) => (c['name'] ?? '').toString() == 'updated_at',
    );

    if (hasChequeTable && !hasChequeUpdatedAt) {
      await db.execute(
        'ALTER TABLE insurance_policy_cheques RENAME TO insurance_policy_cheques_old;',
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS insurance_policy_cheques (
          id TEXT PRIMARY KEY,
          policy_id TEXT NOT NULL,

          amount REAL NOT NULL DEFAULT 0,
          issue_date TEXT,
          due_date TEXT,

          bank_name TEXT,
          drawer_name TEXT,
          cheque_number TEXT,

          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,

          FOREIGN KEY(policy_id) REFERENCES insurance_policies(id) ON DELETE CASCADE
        );
      ''');

      await db.execute('''
        INSERT INTO insurance_policy_cheques (
          id, policy_id, amount, due_date, bank_name, drawer_name, cheque_number, created_at, updated_at
        )
        SELECT
          id, policy_id, amount, due_date, bank_name, drawer_name, cheque_number, created_at,
          COALESCE(created_at, datetime('now'))
        FROM insurance_policy_cheques_old;
      ''');

      await db.execute('DROP TABLE insurance_policy_cheques_old;');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_policy_cheques_policy ON insurance_policy_cheques(policy_id);',
      );
    }

    // 2) insurance_policy_installments (ADD updated_at if missing)
    final installmentCols =
        await db.rawQuery("PRAGMA table_info(insurance_policy_installments)");

    final hasInstallmentTable = installmentCols.isNotEmpty;
    final hasInstallmentUpdatedAt = installmentCols.any(
      (c) => (c['name'] ?? '').toString() == 'updated_at',
    );

    if (hasInstallmentTable && !hasInstallmentUpdatedAt) {
      await db.execute(
        "ALTER TABLE insurance_policy_installments ADD COLUMN updated_at TEXT;",
      );
      await db.execute(
        "UPDATE insurance_policy_installments SET updated_at = created_at WHERE updated_at IS NULL;",
      );
    }

    // 3) insurance_policy_promissories (ADD updated_at if missing)
    final promissoryCols =
        await db.rawQuery("PRAGMA table_info(insurance_policy_promissories)");

    final hasPromissoryTable = promissoryCols.isNotEmpty;
    final hasPromissoryUpdatedAt = promissoryCols.any(
      (c) => (c['name'] ?? '').toString() == 'updated_at',
    );

    if (hasPromissoryTable && !hasPromissoryUpdatedAt) {
      await db.execute(
        "ALTER TABLE insurance_policy_promissories ADD COLUMN updated_at TEXT;",
      );
      await db.execute(
        "UPDATE insurance_policy_promissories SET updated_at = created_at WHERE updated_at IS NULL;",
      );
    }
  }
}
