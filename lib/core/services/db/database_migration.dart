// Database migration compatibility note.
//
// Purchase schema compatibility.
// -----------------------------------------------------------
// Database migration compatibility note.
// Purchase schema compatibility.
// Purchase schema compatibility.
// Purchase schema compatibility.
// Purchase schema compatibility.
// Ensure voucher compatibility columns.
// Database migration compatibility note.
// -----------------------------------------------------------

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_constants.dart';
import '../offline_outbox_service.dart';
import 'database_platform_policy.dart';
import 'database_encryption_service.dart';

// Database migration compatibility note.
import 'tables/user_tables.dart';
import 'tables/organization_identity_tables.dart';
import 'tables/device_identity_tables.dart';
import 'tables/license_activation_tables.dart';
import 'tables/license_runtime_tables.dart';
import 'tables/license_validation_tables.dart';
import 'tables/owner_bootstrap_tables.dart';
import 'tables/user_authorization_tables.dart';
import 'tables/p16_security_tables.dart';
import 'tables/repair_tables.dart';
import 'tables/accounting_tables.dart';
import 'tables/hr_tables.dart';
import 'tables/insurance_tables.dart';
import 'tables/supplier_tables.dart';
import 'tables/cheque_tables.dart';
import 'tables/report_tables.dart';
import 'tables/technical_tables.dart';
import 'tables/vehicle_tables.dart';
import 'views/accounting_views.dart';
import 'tables/payments_tables.dart';
import 'tables/receipt_tables.dart';
import 'tables/voucher_tables.dart';
import 'tables/purchase_invoices_table.dart';
import 'tables/purchase_payments_table.dart';

class DatabaseMigration {
  static Database? _database;
  static Future<Database>? _opening;

// ---------------------------------------------------------------
// Database migration compatibility note.
// ---------------------------------------------------------------
  static Future<void> _ensureGeneralSupplier(Database db) async {
    final res = await db.query(
      'suppliers',
      where: 'name = ?',
      whereArgs: ['المصاريف العامة'],
      limit: 1,
    );

    if (res.isEmpty) {
      await db.insert('suppliers', {'name': 'المصاريف العامة'});
      debugPrint(
          "أ¢إ“â€‌ ط·ع¾ط¸â€¦ ط·آ¥ط¸â€ ط·آ´ط·آ§ط·طŒ ط·آ§ط¸â€‍ط¸â€¦ط¸ث†ط·آ±ط·آ¯ ط·آ§ط¸â€‍ط·آ§ط¸ظ¾ط·ع¾ط·آ±ط·آ§ط·آ¶ط¸ظ¹ S0000 ط¸â€‍ط¸â€‍ط¸â€¦ط·آµط·آ§ط·آ±ط¸ظ¹ط¸ظ¾ ط·آ§ط¸â€‍ط·آ¹ط·آ§ط¸â€¦ط·آ©");
    }
  }

  // ============================================================
  // API
  // ============================================================
  static Future<Database> get database async {
    if (_database != null) return _database!;

    _opening ??= initDatabase();

    try {
      final db = await _opening!;
      _database = db;
      return db;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<T> inTx<T>(
      Future<T> Function(DatabaseExecutor db) action) async {
    final db = await database;
    return db.transaction<T>((txn) async => await action(txn));
  }

  // ============================================================
  // INIT
  // ============================================================
  static Future<Database> initDatabase({String? pathOverride}) async {
    final path = pathOverride ?? await DatabaseConstants.dbFilePath();
    debugPrint(
      '[DB] opening v${DatabaseConstants.dbVersion} @ $path',
    );

    final encryption = pathOverride == null
        ? await DatabaseEncryptionService.prepareCanonical(path)
        : null;

    Database? db;
    try {
      db = encryption == null
          ? await openDatabase(
              path,
              version: DatabaseConstants.dbVersion,
              onConfigure: _onConfigure,
              onCreate: _onCreate,
              onUpgrade: _onUpgrade,
              singleInstance: pathOverride == null,
            )
          : await encryption.open(
              version: DatabaseConstants.dbVersion,
              onConfigure: _onConfigure,
              onCreate: _onCreate,
              onUpgrade: _onUpgrade,
              singleInstance: true,
            );

      // C02 FIX7 / P05 current-v69 compatibility:
      // P05 added the canonical vehicles table without increasing dbVersion.
      // Existing v69 installations therefore do not run onUpgrade. Ensure only
      // this derived P05 master-data table before fail-closed validation.
      await ensureP05VehicleCompatibilityBeforeValidation(db);

      // C02 FIX8 / P04 current-v69 compatibility:
      // Existing v69 installations can still carry the legacy Outbox layout.
      // Upgrade/create the technical Outbox before any sync-state consumer can
      // query the newer status/retry columns.
      await ensureP04OutboxCompatibilityBeforeValidation(db);

      // Group 2 hardening: workshop settings are part of the canonical DB
      // contract. Older/current-v69 installations may have the narrow legacy
      // table because dbVersion did not change when presentation fields were
      // introduced. Add only missing nullable columns before validation.
      await UserTables.ensureWorkshopSettingsCompatibility(db);

      // P11 keeps dbVersion at 69: receipt identity/reversal columns are
      // additive and must exist on already-upgraded installations too.
      await PaymentsTables.ensurePaymentsSchema(db);
      await ReceiptTables.createAllTables(db);

      // P14 keeps dbVersion at 69. Purchase-line category/note are additive
      // compatibility columns and must exist on already-upgraded databases.
      await PurchaseInvoicesTable.createAllTables(db);
      await PurchasePaymentsTable.createAllTables(db);

      await _validateDatabase(db);
      await encryption?.commit();
      return db;
    } catch (_) {
      if (db != null && db.isOpen) {
        try {
          await db.close();
        } catch (_) {
          // Rollback below remains the authoritative recovery step.
        }
      }
      await encryption?.rollback();
      rethrow;
    }
  }

  // ============================================================
  static Future<void> _onConfigure(Database db) async {
    await DatabasePlatformPolicy.configure(db);
  }

  // ============================================================
  // CREATE ALL
  // ============================================================
  static Future<void> _onCreate(Database db, int version) async {
    debugPrint('[DB] onCreate FULL INIT');

    await UserTables.createAllTables(db);
    await UserTables.createActivationCodesTable(db);

    await RepairTables.createAllTables(db);
    await AccountingTables.createAllTables(db);
    await HRTables.createAllTables(db);
    await SupplierTables.createAllTables(db);
    await ChequeTables.createAllTables(db);
    await ReportTables.createAllTables(db);
    await TechnicalTables.createAllTables(db);

    await PaymentsTables.createAllTables(db);
    await ReceiptTables.createAllTables(db);
    await VoucherTables.createAllTables(db);

    // Database migration compatibility note.
    await _createPurchaseSchema(db);
    await InsuranceTables.createAllTables(db);

    // P0.010 - permanent data-health infrastructure.
    await _ensureDataHealthSchema(db);
    await _ensureCommercialConfigurationSchema(db);

    await AccountingViews.createAllViews(db);

    // P1.001 - lifecycle/database normalization.
    await _postInit(db);

    debugPrint('All tables created successfully');
  }

  // ============================================================
  // UPGRADE
  // ============================================================
  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    debugPrint('Upgrade $oldV -> $newV');

    await UserTables.onUpgrade(db, oldV, newV);
    await RepairTables.onUpgrade(db, oldV, newV);
    await AccountingTables.onUpgrade(db, oldV, newV);
    await HRTables.onUpgrade(db, oldV, newV);
    await SupplierTables.ensureSuppliersSchema(db);

    await ReportTables.onUpgrade(db, oldV, newV);
    await TechnicalTables.onUpgrade(db, oldV, newV);

    await PaymentsTables.ensurePaymentsSchema(db);
    await ReceiptTables.createAllTables(db);
    await InsuranceTables.ensureInsuranceSchema(db);

    await InsuranceTables.createAllTables(db);

    // Database migration compatibility note.
    await VoucherTables.createAllTables(db);

    // Database migration compatibility note.
    await _createPurchaseSchema(db);
    await InsuranceTables.createAllTables(db);

    // ------------------------------------------------------------
    // Upgrade v50 -- add remaining to purchases
    // ------------------------------------------------------------
    if (oldV < 50) {
      final info = await db.rawQuery("PRAGMA table_info(purchases)");
      final hasRemaining =
          info.any((c) => (c['name'] as String) == 'remaining');

      if (!hasRemaining) {
        debugPrint("Adding remaining column to purchases");
        await db.execute(
            "ALTER TABLE purchases ADD COLUMN remaining REAL DEFAULT 0;");
        debugPrint("remaining added to purchases");
      } else {
        debugPrint("remaining already exists -- skipping");
      }
    }
// ------------------------------------------------------------
    // Upgrade v51 -- finalize purchase & cheque schema
    // ------------------------------------------------------------
    if (oldV < 51) {
      await SupplierTables.ensureSuppliersSchema(db);
      await PaymentsTables.ensurePaymentsSchema(db);
      await InsuranceTables.createAllTables(db);

      await ChequeTables.ensureChequesSchema(db);

      // Database migration compatibility note.
      await PurchaseInvoicesTable.createAllTables(db);
      await PurchasePaymentsTable.createAllTables(db);

      // P1.001 - lifecycle/database normalization.
      // Legacy columns may be unused by a newer UI, but migration must never
      // erase customer data merely because a new schema exists.
      debugPrint(
        "Upgrade v51: preserving legacy purchase detail columns unchanged",
      );

      debugPrint("Upgrade v51 applied successfully");
    }
// ------------------------------------------------------------
    // Upgrade V53 -- add remaining to purchase_invoices
// ------------------------------------------------------------
    if (oldV < 53) {
      final info = await db.rawQuery("PRAGMA table_info(purchase_invoices)");
      final hasRemaining =
          info.any((c) => (c['name'] as String) == 'remaining');

      if (!hasRemaining) {
        debugPrint(
            "ظ‹ع؛â€؛آ  Adding remaining column to purchase_invoicesأ¢â‚¬آ¦");
        await db.execute(
            "ALTER TABLE purchase_invoices ADD COLUMN remaining REAL DEFAULT 0;");
        debugPrint("remaining added to purchase_invoices");
      } else {
        debugPrint("remaining already exists -- skipping");
      }
    }
    // Database migration compatibility note.
    if (oldV < 56) {
      await ChequeTables.ensureChequesSchema(db);
      debugPrint("Upgrade v56 cheque lifecycle schema applied");
    }

    // P0.010 - permanent data-health infrastructure.
    if (oldV < 58) {
      await _ensureDataHealthSchema(db);
      debugPrint("Upgrade v58 data-health schema applied");
    }

    // P1.002 - authentication/session hardening.
    if (oldV < 59) {
      await UserTables.ensureAuthSecuritySchema(db);

      // Preserve the exact existing password so current customers are never
      // locked out by migration. Legacy hashes are upgraded only after a
      // successful login, while the user is forced to choose a new password.
      await db.execute(r"""
        UPDATE users
        SET must_change_password = 1
        WHERE password NOT LIKE 'pbkdf2_sha256$%'
      """);

      debugPrint("Upgrade v59 authentication security schema applied");
    }

    if (oldV < 60) {
      await _ensureCommercialConfigurationSchema(db);
      debugPrint("Upgrade v60 commercial configuration schema applied");
    }

    // SEC.005 - installation/device identity metadata foundation.
    if (oldV < 64) {
      await DeviceIdentityTables.ensure(db);
      debugPrint("Upgrade v64 device identity schema applied");
    }

    // SEC.006 - verified online activation receipt/state.
    if (oldV < 65) {
      await LicenseActivationTables.ensure(db);
      debugPrint("Upgrade v65 activation state schema applied");
    }

    // SEC.007 - one-time First Owner bootstrap lifecycle.
    if (oldV < 66) {
      await OwnerBootstrapTables.ensure(db);
      debugPrint("Upgrade v66 First Owner bootstrap schema applied");
    }

    // SEC.008 - canonical roles, permissions and enforcement catalog.
    if (oldV < 67) {
      await UserAuthorizationTables.ensure(db);
      // P16 - roles/audit/backup guardian metadata. Additive and idempotent.
      await P16SecurityTables.ensure(db);
      debugPrint("Upgrade v67 users/roles/permissions schema applied");
    }

    // SEC.011 - runtime license projection + DB-level operational write guards.
    if (oldV < 68) {
      await LicenseRuntimeTables.ensure(db);
      debugPrint(
          "أ¢إ“â€¦ Upgrade v68 expiry/read-only lifecycle guards applied");
    }

    // SEC.012 - periodic online validation + offline grace enforcement.
    if (oldV < 69) {
      await LicenseValidationTables.ensure(db);
      await LicenseRuntimeTables.upgradeForSec012(db);
      debugPrint(
          "أ¢إ“â€¦ Upgrade v69 periodic validation/grace enforcement applied");
    }

    await UserTables.createActivationCodesTable(db);

    await _postInit(db);
  }

  // ============================================================
  // POST INIT
  // ============================================================
  static Future<void> _postInit(Database db) async {
    // P1.001 - lifecycle/database normalization.
    // Never replay the full historical upgrade chain on every normal startup.
    await SupplierTables.ensureSuppliersSchema(db);
    await RepairTables.ensureRepairsSchema(db);

    // P05 - canonical clients/vehicles master-data foundation.
    await VehicleTables.ensure(db);

    // SEC.001 - stable local organization identity foundation.
    await OrganizationIdentityTables.ensure(db);

    // SEC.005 - device identity metadata; private key material is external.
    await DeviceIdentityTables.ensure(db);

    // SEC.006 - public signed activation receipt only.
    await LicenseActivationTables.ensure(db);

    // SEC.011/SEC.012 - operational runtime projection, periodic validation
    // window and DB-level write-guard triggers.
    await LicenseValidationTables.ensure(db);
    await LicenseRuntimeTables.ensure(db);

    // P04.2C - current databases are already v69, so the Outbox compatibility
    // upgrade must run in the normal idempotent post-init path, not only in an
    // historical onUpgrade branch.
    await TechnicalTables.ensureP04OutboxSchema(db);
    await OfflineOutboxService.resetInterruptedSending(db);

    // SEC.007 - local one-time First Owner bootstrap state.
    await OwnerBootstrapTables.ensure(db);

    // SEC.008 - canonical local authorization catalog and role guards.
    await UserAuthorizationTables.ensure(db);

    // P16 - append-only audit + backup guardian / recovery metadata.
    // dbVersion intentionally remains 69, so this must run on every current-version open.
    await P16SecurityTables.ensure(db);

    await ChequeTables.ensureChequesSchema(db);
    await AccountingTables.ensureInvoicesSchema(db);
    await PaymentsTables.ensurePaymentsSchema(db);
    await ReceiptTables.createAllTables(db);
    await InsuranceTables.ensureInsuranceSchema(db);

    await _ensureVoucherExtraColumns(db);
    await _ensureDataHealthSchema(db);

    // ============================================================
    // FIX OLD EMPLOYEE PAYMENTS -> EMPLOYEE ADVANCES
    // ============================================================
    await db.execute('''
      UPDATE vouchers
      SET
        source = 'EMP_ADV',
        source_id = party_id
      WHERE
        voucher_type = 'PAYMENT'
        AND party_type = 'EMPLOYEE'
        AND source IS NULL;
    ''');

    await AccountingTables.ensureDefaultAccounts(db);
    await _ensureGeneralSupplier(db);

    // Database migration compatibility note.
    await UserTables.createActivationCodesTable(db);

    await _fixLinkedPaymentIds(db);
    await _debugDump(db);
  }

  // ============================================================
  // P1.003 - commercial country/currency/VAT/numbering schema.
  // ============================================================
  static Future<void> _ensureCommercialColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name']?.toString() == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  static Future<void> _ensureCommercialConfigurationSchema(Database db) async {
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'country_code', 'TEXT');
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'base_currency_code', 'TEXT');
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'currency_symbol', 'TEXT');
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'currency_decimals', 'INTEGER');
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'default_vat_rate', 'REAL');
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'prices_include_vat', 'INTEGER');
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'tax_registration_number', 'TEXT');
    await _ensureCommercialColumn(
        db, 'workshop_settings', 'document_locale', 'TEXT');

    await db.execute(r'''
      UPDATE workshop_settings
      SET
        country_code = COALESCE(NULLIF(TRIM(country_code), ''), 'PS'),
        base_currency_code = COALESCE(NULLIF(TRIM(base_currency_code), ''), 'ILS'),
        currency_symbol = COALESCE(NULLIF(TRIM(currency_symbol), ''), '₪'),
        currency_decimals = COALESCE(currency_decimals, 2),
        default_vat_rate = COALESCE(default_vat_rate, 0),
        prices_include_vat = COALESCE(prices_include_vat, 0),
        document_locale = COALESCE(NULLIF(TRIM(document_locale), ''), 'ar')
      WHERE id = 1;
    ''');

    for (final table in ['invoices', 'purchase_invoices', 'payments']) {
      await _ensureCommercialColumn(db, table, 'document_number', 'TEXT');
      await _ensureCommercialColumn(db, table, 'currency_code', 'TEXT');
      await _ensureCommercialColumn(db, table, 'currency_decimals', 'INTEGER');
    }

    await _ensureCommercialColumn(db, 'invoices', 'vat_rate', 'REAL');
    await _ensureCommercialColumn(db, 'invoices', 'tax_mode', 'TEXT');
    await _ensureCommercialColumn(db, 'purchase_invoices', 'vat_rate', 'REAL');
    await _ensureCommercialColumn(db, 'purchase_invoices', 'tax_mode', 'TEXT');
    await _ensureCommercialColumn(
        db, 'vouchers', 'currency_decimals', 'INTEGER');

    await db.execute(r'''
      UPDATE invoices
      SET currency_code = COALESCE(NULLIF(TRIM(currency_code), ''), 'ILS'),
          currency_decimals = COALESCE(currency_decimals, 2),
          vat_rate = COALESCE(
            vat_rate,
            CASE WHEN COALESCE(subtotal,0) > 0
              THEN ROUND((COALESCE(vat_amount,vat,0)/subtotal)*100, 6)
              ELSE 0 END
          ),
          tax_mode = COALESCE(NULLIF(TRIM(tax_mode), ''), 'exclusive');
    ''');

    await db.execute(r'''
      UPDATE purchase_invoices
      SET currency_code = COALESCE(NULLIF(TRIM(currency_code), ''), 'ILS'),
          currency_decimals = COALESCE(currency_decimals, 2),
          vat_rate = COALESCE(
            vat_rate,
            CASE WHEN COALESCE(subtotal,0) > 0
              THEN ROUND((COALESCE(vat,0)/subtotal)*100, 6)
              ELSE 0 END
          ),
          tax_mode = COALESCE(NULLIF(TRIM(tax_mode), ''), 'exclusive');
    ''');

    await db.execute(r'''
      UPDATE payments
      SET currency_code = COALESCE(NULLIF(TRIM(currency_code), ''), 'ILS'),
          currency_decimals = COALESCE(currency_decimals, 2);
    ''');

    await db.execute(r'''
      UPDATE vouchers
      SET currency = COALESCE(NULLIF(TRIM(currency), ''), 'ILS'),
          currency_decimals = COALESCE(currency_decimals, 2);
    ''');

    await db.execute(r'''
      CREATE TABLE IF NOT EXISTS document_sequences (
        document_type TEXT PRIMARY KEY,
        prefix TEXT NOT NULL,
        next_value INTEGER NOT NULL CHECK(next_value > 0),
        pad_width INTEGER NOT NULL DEFAULT 4 CHECK(pad_width BETWEEN 1 AND 12),
        reset_policy TEXT NOT NULL DEFAULT 'NEVER'
          CHECK(reset_policy IN ('NEVER','YEARLY')),
        updated_at TEXT NOT NULL
      );
    ''');

    final now = DateTime.now().toIso8601String();

    Future<void> seed(String type, String prefix, int nextValue) async {
      await db.insert(
        'document_sequences',
        {
          'document_type': type,
          'prefix': prefix,
          'next_value': nextValue,
          'pad_width': 4,
          'reset_policy': 'NEVER',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final p = await db.rawQuery(r'''
      SELECT COALESCE(MAX(
        CASE WHEN voucher_number GLOB 'P-[0-9]*'
             THEN CAST(SUBSTR(voucher_number,3) AS INTEGER)
             ELSE 0 END
      ),0) AS m
      FROM vouchers WHERE voucher_type='PAYMENT';
    ''');
    final r = await db.rawQuery(r'''
      SELECT COALESCE(MAX(
        CASE WHEN voucher_number GLOB 'R-[0-9]*'
             THEN CAST(SUBSTR(voucher_number,3) AS INTEGER)
             ELSE 0 END
      ),0) AS m
      FROM vouchers WHERE voucher_type='RECEIPT';
    ''');

    int maxValue(List<Map<String, Object?>> rows) {
      final v = rows.first['m'];
      return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    }

    await seed('SALES_INVOICE', 'INV', 1);
    await seed('RECEIPT_VOUCHER', 'R', maxValue(r) + 1);
    await seed('PAYMENT_VOUCHER', 'P', maxValue(p) + 1);
    await seed('PURCHASE_INVOICE', 'PUR', 1);
    await seed('REPAIR_FILE', 'REP', 1);
    await seed('QUOTE', 'Q', 1);

    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_voucher_type_number
      ON vouchers(voucher_type, voucher_number)
      WHERE voucher_number IS NOT NULL AND TRIM(voucher_number) <> '';
    ''');
    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_invoices_document_number
      ON invoices(document_number)
      WHERE document_number IS NOT NULL AND TRIM(document_number) <> '';
    ''');
    await db.execute(r'''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_document_number
      ON purchase_invoices(document_number)
      WHERE document_number IS NOT NULL AND TRIM(document_number) <> '';
    ''');
  }

  // ============================================================
  // P0.010 - permanent data-health infrastructure.
  // ============================================================
  static Future<void> _ensureDataHealthSchema(Database db) async {
    await _ensureCanonicalSettlementSchema(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_health_repair_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_at TEXT NOT NULL,
        backup_path TEXT,
        changes_json TEXT NOT NULL,
        before_summary TEXT,
        after_summary TEXT
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_data_health_repair_log_run_at
      ON data_health_repair_log(run_at);
    ''');
  }

  static Future<void> _ensureCanonicalSettlementSchema(Database db) async {
    final existing = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='invoice_settlements'",
    );

    if (existing.isEmpty) {
      await _createCanonicalSettlementTable(db);
      return;
    }

    final info = await db.rawQuery('PRAGMA table_info(invoice_settlements)');
    final invoiceColumn = info.where(
      (column) => column['name']?.toString() == 'invoice_id',
    );

    final declaredType = invoiceColumn.isEmpty
        ? ''
        : (invoiceColumn.first['type'] ?? '').toString().toUpperCase();

    if (declaredType != 'TEXT') {
      await db.execute('DROP TABLE IF EXISTS invoice_settlements_v58;');

      await db.execute('''
        CREATE TABLE invoice_settlements_v58 (
          id TEXT PRIMARY KEY,
          supplier_id INTEGER NOT NULL,
          invoice_id TEXT NOT NULL,
          voucher_id TEXT NOT NULL,
          amount_applied REAL NOT NULL,
          created_at TEXT
        );
      ''');

      await db.execute('''
        INSERT INTO invoice_settlements_v58(
          id,
          supplier_id,
          invoice_id,
          voucher_id,
          amount_applied,
          created_at
        )
        SELECT
          id,
          supplier_id,
          CAST(invoice_id AS TEXT),
          voucher_id,
          amount_applied,
          created_at
        FROM invoice_settlements;
      ''');

      await db.execute('DROP TABLE invoice_settlements;');
      await db.execute(
        'ALTER TABLE invoice_settlements_v58 '
        'RENAME TO invoice_settlements;',
      );
    }

    await _ensureSettlementIndexes(db);
  }

  static Future<void> _createCanonicalSettlementTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_settlements (
        id TEXT PRIMARY KEY,
        supplier_id INTEGER NOT NULL,
        invoice_id TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        amount_applied REAL NOT NULL,
        created_at TEXT
      );
    ''');

    await _ensureSettlementIndexes(db);
  }

  static Future<void> _ensureSettlementIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_settlements_supplier
      ON invoice_settlements(supplier_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_settlements_invoice
      ON invoice_settlements(invoice_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_settlements_voucher
      ON invoice_settlements(voucher_id);
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_settlements_voucher_invoice
      ON invoice_settlements(voucher_id, invoice_id);
    ''');
  }

  // ============================================================
  // P1.001 - lifecycle/database normalization.
  /// C02 FIX7 — current-v69 compatibility for the P05 vehicles master table.
  ///
  /// P05 intentionally kept dbVersion at 69. Existing customer databases are
  /// already v69, so sqflite does not invoke onUpgrade and the P05 table must
  /// be ensured explicitly before the fail-closed core-table validation.
  ///
  /// This is deliberately narrow:
  /// - it never resets/replaces the database;
  /// - it never creates missing legacy prerequisites;
  /// - it only runs VehicleTables.ensure when both clients and repairs exist;
  /// - VehicleTables backfill is non-destructive and never overwrites an
  ///   already-canonical vehicle record.
  @visibleForTesting
  static Future<void> ensureP05VehicleCompatibilityBeforeValidation(
    DatabaseExecutor db,
  ) async {
    final existing = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = existing
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();

    if (!names.contains('clients') || !names.contains('repairs')) {
      return;
    }

    await VehicleTables.ensure(db);
  }

  /// C02 FIX8 — current-v69 compatibility for the P04 technical Outbox.
  ///
  /// P04 kept dbVersion at 69. A pre-P04 installation may therefore already
  /// report user_version=69 while `outbox_messages` still has the legacy
  /// id/channel/payload_json/created_at/sent layout. The sync-state service
  /// queries `status`, so this compatibility ensure must happen during every
  /// same-version open before the database is handed to runtime consumers.
  ///
  /// TechnicalTables.createAllTables is idempotent and non-destructive:
  /// it creates the technical tables if absent and upgrades the existing
  /// Outbox in place while preserving all legacy rows and the `sent` column.
  @visibleForTesting
  static Future<void> ensureP04OutboxCompatibilityBeforeValidation(
    DatabaseExecutor db,
  ) async {
    await TechnicalTables.createAllTables(db);
    await OfflineOutboxService.resetInterruptedSending(db);
  }

  // ============================================================
  static Future<void> _validateDatabase(Database db) async {
    final version = Sqflite.firstIntValue(
          await db.rawQuery('PRAGMA user_version'),
        ) ??
        0;

    if (version != DatabaseConstants.dbVersion) {
      throw StateError(
        'Database version mismatch: expected '
        '${DatabaseConstants.dbVersion}, found $version.',
      );
    }

    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty ||
        integrity.first.values.first.toString().toLowerCase() != 'ok') {
      throw StateError('Database integrity_check failed: $integrity');
    }

    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeys.isNotEmpty) {
      throw StateError(
        'Database contains foreign-key violations: $foreignKeys',
      );
    }

    final existing = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = existing
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();

    final missing = DatabaseConstants.coreTables
        .where((table) => !names.contains(table))
        .toList(growable: false);

    if (missing.isNotEmpty) {
      throw StateError('Database is missing required tables: $missing');
    }

    await OrganizationIdentityTables.validate(db);
    await DeviceIdentityTables.validate(db);
    await LicenseActivationTables.validate(db);
    await LicenseRuntimeTables.validate(db);
    await OwnerBootstrapTables.validate(db);
  }

  static Future<void> closeDatabase({bool checkpoint = true}) async {
    final db = _database;

    _database = null;
    _opening = null;

    if (db == null || !db.isOpen) return;

    if (checkpoint) {
      try {
        await DatabasePlatformPolicy.checkpoint(db);
      } catch (e) {
        debugPrint("Database migration step");
      }
    }

    await db.close();
  }

  static Future<Database> reopenDatabase() async {
    await closeDatabase();
    return database;
  }

  // Destructive reset is developer-only. Backup/restore must never call it.
  static Future<void> resetDatabase() async {
    if (!kDebugMode) {
      throw StateError(
        'Database reset is disabled in production builds.',
      );
    }

    await closeDatabase();
    final path = await DatabaseConstants.dbFilePath();
    await deleteDatabase(path);
    await database;
    debugPrint('Development DB reset completed');
  }

  // ============================================================
  // Debug.
  // ============================================================
  static Future<void> _debugDump(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    debugPrint('DB Tables:');
    for (final t in tables) {
      final name = t['name'] as String;
      final count = await db.rawQuery("SELECT COUNT(*) c FROM $name");
      debugPrint('  - $name: ${count.first['c']}');
    }
  }

  // ============================================================
  // Database migration compatibility note.
  // ============================================================
  static Future<void> _fixLinkedPaymentIds(Database db) async {
    final info = await db.rawQuery("PRAGMA table_info(cheques)");
    final hasCorrect =
        info.any((c) => (c['name'] as String) == 'linked_payment_ids');
    final hasOld =
        info.any((c) => (c['name'] as String) == 'linked_payment_id');

    if (hasCorrect) return;

    debugPrint("linked_payment_ids compatibility update");

    if (hasOld) {
      await db.execute(
          "ALTER TABLE cheques RENAME COLUMN linked_payment_id TO linked_payment_ids;");
      debugPrint(
          "أ¢إ“â€‌ ط·آ¥ط·آ¹ط·آ§ط·آ¯ط·آ© ط·ع¾ط·آ³ط¸â€¦ط¸ظ¹ط·آ© ط·آ§ط¸â€‍ط·آ¹ط¸â€¦ط¸ث†ط·آ¯ ط·ع¾ط¸â€¦ط·ع¾ ط·آ¨ط¸â€ ط·آ¬ط·آ§ط·آ­");
      return;
    }

    await db.execute("ALTER TABLE cheques ADD COLUMN linked_payment_ids TEXT;");
    debugPrint("linked_payment_ids compatibility update");
  }

  // ============================================================
  // Database migration compatibility note.
  // ============================================================
  static Future<void> _createPurchaseSchema(DatabaseExecutor db) async {
    await PurchaseInvoicesTable.createAllTables(db);
    await PurchasePaymentsTable.createAllTables(db);
  }

  // ============================================================
// Ensure voucher compatibility columns.
// ============================================================
  static Future<void> _ensureVoucherExtraColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(vouchers)");

    final hasSource = cols.any((c) => c['name']?.toString() == 'source');
    final hasSourceId = cols.any((c) => c['name']?.toString() == 'source_id');

    if (!hasSource) {
      debugPrint("Database migration step");
      await db.execute("ALTER TABLE vouchers ADD COLUMN source TEXT;");
    }

    if (!hasSourceId) {
      debugPrint("Database migration step");
      await db.execute("ALTER TABLE vouchers ADD COLUMN source_id TEXT;");
    }
  }
}
