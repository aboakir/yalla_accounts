import 'dart:io';

import 'package:yalla_accounts/core/security/release_diagnostics.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_identity_tables.dart';
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
import '../restore_file_journal.dart';
import '../offline_outbox_service.dart';
import 'database_platform_policy.dart';
import 'database_encryption_service.dart';

// Database migration compatibility note.
import 'tables/user_tables.dart';
import 'tables/identity_account_tables.dart';
import 'tables/sync_foundation_tables.dart';
import 'tables/unified_sync_tables.dart';
import '../sync/sync_foundation_service.dart';
import '../sync/unified_sync_queue_service.dart';
import 'package:yalla_accounts/features/onboarding/services/workshop_onboarding_tables.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';
import 'package:yalla_accounts/features/raw_materials/services/raw_material_service.dart';
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
import 'tables/party_tables.dart';
import 'tables/accounting_integrity_tables.dart';
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
import 'tables/inventory_tables.dart';

class DatabaseMigration {
  static Database? _database;
  static Future<Database>? _opening;

  @visibleForTesting
  static void useDatabaseForTesting(Database? database) {
    _database = database;
    _opening = null;
  }

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
      ReleaseDiagnostics.debug(
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
    return SyncFoundationService.transaction<T>(db, action);
  }

  static Future<int> _readRecoveredPlaintextVersion(String path) async {
    const sqliteHeader = <int>[
      0x53,
      0x51,
      0x4c,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];
    const maxAttempts = 10;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      RandomAccessFile? handle;
      try {
        handle = await File(path).open(mode: FileMode.read);
        final header = await handle.read(64);
        if (header.length < 64) {
          throw StateError('Recovered SQLite database header is truncated.');
        }
        for (var index = 0; index < sqliteHeader.length; index++) {
          if (header[index] != sqliteHeader[index]) {
            throw StateError(
                'Recovered file is not a plaintext SQLite database.');
          }
        }
        return (header[60] << 24) |
            (header[61] << 16) |
            (header[62] << 8) |
            header[63];
      } on FileSystemException {
        final fileStillExists = await File(path).exists();
        if (!fileStillExists || attempt + 1 >= maxAttempts) rethrow;
        final linearDelayMs = 50 * (attempt + 1);
        final delayMs = linearDelayMs > 500 ? 500 : linearDelayMs;
        ReleaseDiagnostics.debug(
          '[DB] recovered file not readable yet; retry ${attempt + 1}/$maxAttempts in ${delayMs}ms',
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      } finally {
        if (handle != null) await handle.close();
      }
    }

    throw StateError('Unable to read recovered SQLite database header.');
  }

  static Future<int> _readExistingVersion(
    String path, {
    required bool retryAfterRestore,
  }) async {
    if (retryAfterRestore &&
        !DatabaseEncryptionService.mobileEncryptionEnabled) {
      return _readRecoveredPlaintextVersion(path);
    }

    final maxAttempts = retryAfterRestore ? 10 : 1;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      Database? existing;
      try {
        existing = await DatabaseEncryptionService.openReadOnlyCandidate(path);
        return await existing.getVersion();
      } catch (error) {
        final message = error.toString().toLowerCase();
        final retryable = message.contains('unable to open database file') ||
            message.contains('sqlite_error: 14') ||
            message.contains('code 14');
        final fileStillExists = await File(path).exists();
        final canRetry =
            retryable && fileStillExists && attempt + 1 < maxAttempts;
        if (!canRetry) rethrow;

        final delayMs = 50 * (1 << attempt);
        ReleaseDiagnostics.debug(
          '[DB] transient reopen after restore; retry ${attempt + 1}/$maxAttempts in ${delayMs}ms',
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      } finally {
        if (existing != null && existing.isOpen) {
          await existing.close();
        }
      }
    }

    throw StateError('Unable to read existing database version.');
  }

  // ============================================================
  // INIT
  // ============================================================
  static Future<Database> initDatabase({String? pathOverride}) async {
    final path = pathOverride ?? await DatabaseConstants.dbFilePath();
    ReleaseDiagnostics.debug(
      '[DB] opening v${DatabaseConstants.dbVersion} @ $path',
    );

    final recoveredInterruptedRestore =
        await Directory('$path.restore-journal').exists();
    await RestoreFileJournal.recover(path);
    if (await databaseExists(path)) {
      final version = await _readExistingVersion(
        path,
        retryAfterRestore: recoveredInterruptedRestore,
      );
      if (version > DatabaseConstants.dbVersion) {
        throw StateError('Database version $version is newer than supported '
            '${DatabaseConstants.dbVersion}; no downgrade or reset was performed.');
      }
    }
    final encryption = pathOverride == null
        ? await DatabaseEncryptionService.prepareCanonical(path)
        : null;

    Database? db;
    Database? openingHandle;
    try {
      db = encryption == null
          ? await openDatabase(
              path,
              version: DatabaseConstants.dbVersion,
              onConfigure: _onConfigure,
              onCreate: (opened, version) async {
                openingHandle = opened;
                await _onCreate(opened, version);
              },
              onUpgrade: (opened, oldVersion, newVersion) async {
                openingHandle = opened;
                await _onUpgrade(opened, oldVersion, newVersion);
              },
              singleInstance: pathOverride == null,
            )
          : await encryption.open(
              version: DatabaseConstants.dbVersion,
              onConfigure: _onConfigure,
              onCreate: (opened, version) async {
                openingHandle = opened;
                await _onCreate(opened, version);
              },
              onUpgrade: (opened, oldVersion, newVersion) async {
                openingHandle = opened;
                await _onUpgrade(opened, oldVersion, newVersion);
              },
              singleInstance: true,
            );

      await _validateDatabase(db);
      await encryption?.commit();
      return db;
    } catch (_) {
      final failed = db ?? openingHandle;
      if (failed != null && failed.isOpen) {
        try {
          await failed.close();
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
    ReleaseDiagnostics.debug('[DB] onCreate FULL INIT');

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

    await _upgradeV70(db);
    await _upgradeV71(db);
    await _upgradeV72(db);
    await _upgradeV73(db);
    await _upgradeV74(db);
    await _upgradeV75(db);
    await _upgradeV76(db);
    await _upgradeV77(db);
    await _upgradeV78(db);
    await _upgradeV79(db);
    await _upgradeV80(db);
    await _upgradeV81(db);
    await _upgradeV82(db);
    await _upgradeV83(db);
    await _upgradeV84(db, fromSchemaVersion: 0);
    ReleaseDiagnostics.debug('All tables created successfully');
  }

  // ============================================================
  // UPGRADE
  // ============================================================
  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    ReleaseDiagnostics.debug('Upgrade $oldV -> $newV');
    // v70 already contains compatibility schemas. Avoid replaying seed writes
    // under an expired license for additive identity and sync upgrades.
    if (oldV >= 70) {
      // Two independently released branches used 77/78 for different features.
      // Probe capabilities before v79 references the v3 mutation context.
      if (oldV >= 77 && oldV <= 78) {
        await _ensureParallelLineagePrerequisites(db);
      }
      if (oldV < 71) await _upgradeV71(db);
      if (oldV < 72) await _upgradeV72(db);
      if (oldV < 73) await _upgradeV73(db);
      if (oldV < 74) await _upgradeV74(db);
      if (oldV < 75) await _upgradeV75(db);
      if (oldV < 76) await _upgradeV76(db);
      if (oldV < 77) await _upgradeV77(db);
      if (oldV < 78) await _upgradeV78(db);
      if (oldV < 79) await _upgradeV79(db);
      if (oldV < 80) await _upgradeV80(db);
      if (oldV < 81) await _upgradeV81(db);
      if (oldV < 82) await _upgradeV82(db);
      if (oldV < 83) await _upgradeV83(db);
      if (oldV < 84) await _upgradeV84(db, fromSchemaVersion: oldV);
      return;
    }

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
        ReleaseDiagnostics.debug("Adding remaining column to purchases");
        await db.execute(
            "ALTER TABLE purchases ADD COLUMN remaining REAL DEFAULT 0;");
        ReleaseDiagnostics.debug("remaining added to purchases");
      } else {
        ReleaseDiagnostics.debug("remaining already exists -- skipping");
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
      ReleaseDiagnostics.debug(
        "Upgrade v51: preserving legacy purchase detail columns unchanged",
      );

      ReleaseDiagnostics.debug("Upgrade v51 applied successfully");
    }
// ------------------------------------------------------------
    // Upgrade V53 -- add remaining to purchase_invoices
// ------------------------------------------------------------
    if (oldV < 53) {
      final info = await db.rawQuery("PRAGMA table_info(purchase_invoices)");
      final hasRemaining =
          info.any((c) => (c['name'] as String) == 'remaining');

      if (!hasRemaining) {
        ReleaseDiagnostics.debug(
            "ظ‹ع؛â€؛آ  Adding remaining column to purchase_invoicesأ¢â‚¬آ¦");
        await db.execute(
            "ALTER TABLE purchase_invoices ADD COLUMN remaining REAL DEFAULT 0;");
        ReleaseDiagnostics.debug("remaining added to purchase_invoices");
      } else {
        ReleaseDiagnostics.debug("remaining already exists -- skipping");
      }
    }
    // Database migration compatibility note.
    if (oldV < 56) {
      await ChequeTables.ensureChequesSchema(db);
      ReleaseDiagnostics.debug("Upgrade v56 cheque lifecycle schema applied");
    }

    // P0.010 - permanent data-health infrastructure.
    if (oldV < 58) {
      await _ensureDataHealthSchema(db);
      ReleaseDiagnostics.debug("Upgrade v58 data-health schema applied");
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

      ReleaseDiagnostics.debug(
          "Upgrade v59 authentication security schema applied");
    }

    if (oldV < 60) {
      await _ensureCommercialConfigurationSchema(db);
      ReleaseDiagnostics.debug(
          "Upgrade v60 commercial configuration schema applied");
    }

    // SEC.001 must exist before SEC.005+ and First Owner bootstrap. Legacy
    // databases before v64 did not yet have organization_id on users.
    await OrganizationIdentityTables.ensure(db);

    // SEC.005 - installation/device identity metadata foundation.
    if (oldV < 64) {
      await DeviceIdentityTables.ensure(db);
      ReleaseDiagnostics.debug("Upgrade v64 device identity schema applied");
    }

    // SEC.006 - verified online activation receipt/state.
    if (oldV < 65) {
      await LicenseActivationTables.ensure(db);
      ReleaseDiagnostics.debug("Upgrade v65 activation state schema applied");
    }

    // SEC.007 - one-time First Owner bootstrap lifecycle.
    if (oldV < 66) {
      await OwnerBootstrapTables.ensure(db);
      ReleaseDiagnostics.debug(
          "Upgrade v66 First Owner bootstrap schema applied");
    }

    // SEC.008 - canonical roles, permissions and enforcement catalog.
    if (oldV < 67) {
      await UserAuthorizationTables.ensure(db);
      // P16 - roles/audit/backup guardian metadata. Additive and idempotent.
      await P16SecurityTables.ensure(db);
      ReleaseDiagnostics.debug(
          "Upgrade v67 users/roles/permissions schema applied");
    }

    // SEC.011 - runtime license projection + DB-level operational write guards.
    if (oldV < 68) {
      await LicenseRuntimeTables.ensure(db);
      ReleaseDiagnostics.debug(
          "أ¢إ“â€¦ Upgrade v68 expiry/read-only lifecycle guards applied");
    }

    // SEC.012 - periodic online validation + offline grace enforcement.
    if (oldV < 69) {
      await LicenseValidationTables.ensure(db);
      await LicenseRuntimeTables.upgradeForSec012(db);
      ReleaseDiagnostics.debug(
          "أ¢إ“â€¦ Upgrade v69 periodic validation/grace enforcement applied");
    }

    await UserTables.createActivationCodesTable(db);

    await _postInit(db);
    if (oldV < 70) await _upgradeV70(db);
    if (oldV < 71) await _upgradeV71(db);
    if (oldV < 72) await _upgradeV72(db);
    if (oldV < 73) await _upgradeV73(db);
    if (oldV < 74) await _upgradeV74(db);
    if (oldV < 75) await _upgradeV75(db);
    if (oldV < 76) await _upgradeV76(db);
    if (oldV < 77) await _upgradeV77(db);
    if (oldV < 78) await _upgradeV78(db);
    if (oldV < 79) await _upgradeV79(db);
    if (oldV < 80) await _upgradeV80(db);
    if (oldV < 81) await _upgradeV81(db);
    if (oldV < 82) await _upgradeV82(db);
    if (oldV < 83) await _upgradeV83(db);
    if (oldV < 84) await _upgradeV84(db, fromSchemaVersion: oldV);
  }

  /// v77/v78 existed on two parallel branches. Check schema features, not only
  /// PRAGMA user_version; otherwise the owner v78 misses the v3 sync context.
  static Future<void> _ensureParallelLineagePrerequisites(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_outbox'",
    );
    final partyColumns = await db.rawQuery('PRAGMA table_info(parties)');
    if (tables.isNotEmpty &&
        partyColumns.any((c) => c['name'] == 'role_codes')) {
      return;
    }
    await LicenseRuntimeTables.runTrustedMigrationBackfill(db, () async {
      await _upgradeV77(db);
      await _upgradeV78(db);
    });
  }

  /// Joins commercial sync v83 with the independent insurance/cheque branch.
  /// This is additive: no database reset and no replacement of financial rows.
  static Future<void> _upgradeV84(
    Database db, {
    required int fromSchemaVersion,
  }) async {
    await LicenseRuntimeTables.runTrustedMigrationBackfill(db, () async {
      await InsuranceTables.createAllTables(db);
      await ReceiptTables.createAllTables(db);
      await ChequeTables.ensureChequesSchema(db);
      await PartyTables.ensure(db);
      await HRTables.ensureSyncColumns(db);
      await SyncFoundationTables.ensure(db);
      await UnifiedSyncTables.ensure(db);
      await UnifiedSyncQueueService.resetInterruptedSending(db);
      await db.execute('''CREATE TABLE IF NOT EXISTS schema_feature_migrations(
        feature_key TEXT PRIMARY KEY, from_schema_version INTEGER NOT NULL,
        applied_at TEXT NOT NULL
      )''');
      final now = DateTime.now().toUtc().toIso8601String();
      for (final feature in [
        'commercial_sync_v3',
        'insurance_invoice_v77',
        'canonical_cheques_v78',
        'parallel_lineages_unified_v84'
      ]) {
        await db.insert(
            'schema_feature_migrations',
            {
              'feature_key': feature,
              'from_schema_version': fromSchemaVersion,
              'applied_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert(
        'schema_migrations',
        {
          'version': 84,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _upgradeV83(Database db) async {
    await HRTables.ensureSyncColumns(db);
    await AccountingIntegrityTables.ensure(db);
    await SyncFoundationTables.ensure(db);
    await UnifiedSyncTables.ensure(db);
    await UnifiedSyncTables.refreshFinancialPayloadsForMigration(db);
    await UnifiedSyncQueueService.resetInterruptedSending(db);
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert(
      'schema_migrations',
      {'version': 83, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _upgradeV82(Database db) async {
    await InventoryTables.ensure(db);
    await SyncFoundationTables.ensure(db);
    final oldContext = await db.query(SyncFoundationTables.context,
        where: 'singleton_id=1', limit: 1);
    await db.insert(
        SyncFoundationTables.context,
        {
          'singleton_id': 1,
          'user_id': null,
          'origin': 'remote',
          'remote_entity_type': '__migration__',
          'remote_entity_uuid': '00000000-0000-4000-8000-000000000082',
          'remote_revision': 1
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await InventoryTables.backfillLegacyStock(db);
      await UnifiedSyncTables.ensure(db);
    } finally {
      if (oldContext.isEmpty) {
        await db.delete(SyncFoundationTables.context, where: 'singleton_id=1');
      } else {
        await db.insert(SyncFoundationTables.context,
            Map<String, Object?>.from(oldContext.single),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await UnifiedSyncQueueService.resetInterruptedSending(db);
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert('schema_migrations',
        {'version': 82, 'applied_at': DateTime.now().toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _upgradeV81(Database db) async {
    final oldContext = await db.query(SyncFoundationTables.context,
        where: 'singleton_id=1', limit: 1);
    await db.insert(
      SyncFoundationTables.context,
      {
        'singleton_id': 1,
        'user_id': null,
        'origin': 'remote',
        'remote_entity_type': '__migration__',
        'remote_entity_uuid': '00000000-0000-4000-8000-000000000081',
        'remote_revision': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await PurchaseInvoicesTable.createAllTables(db);
      await PurchasePaymentsTable.createAllTables(db);
      await SyncFoundationTables.ensure(db);
      await _backfillPurchaseSyncReferences(db);
      await UnifiedSyncTables.ensure(db);
      await UnifiedSyncTables.refreshPurchasePayloadsForMigration(db);
    } finally {
      if (oldContext.isEmpty) {
        await db.delete(SyncFoundationTables.context, where: 'singleton_id=1');
      } else {
        await db.insert(SyncFoundationTables.context,
            Map<String, Object?>.from(oldContext.single),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await UnifiedSyncQueueService.resetInterruptedSending(db);
    await db.insert(
      'schema_migrations',
      {'version': 81, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _backfillPurchaseSyncReferences(Database db) async {
    await db.execute('''
      UPDATE purchase_invoices
      SET supplier_party_uuid=(
        SELECT r.entity_uuid
        FROM party_roles pr
        JOIN ${SyncFoundationTables.registry} r
          ON r.entity_type='party' AND r.local_id=pr.party_id
        WHERE pr.role='SUPPLIER'
          AND pr.legacy_id=CAST(purchase_invoices.supplier_id AS TEXT)
        LIMIT 1
      )
      WHERE supplier_id IS NOT NULL
        AND (supplier_party_uuid IS NULL OR TRIM(supplier_party_uuid)='')
    ''');
    await db.execute('''
      UPDATE purchase_payments
      SET purchase_invoice_entity_uuid=(
        SELECT r.entity_uuid FROM ${SyncFoundationTables.registry} r
        WHERE r.entity_type='purchase_invoice'
          AND r.local_id=CAST(purchase_payments.invoice_id AS TEXT)
        LIMIT 1
      )
      WHERE invoice_id IS NOT NULL
        AND (purchase_invoice_entity_uuid IS NULL
          OR TRIM(purchase_invoice_entity_uuid)='')
    ''');
  }

  static Future<void> _upgradeV80(Database db) async {
    final oldContext = await db.query(SyncFoundationTables.context,
        where: 'singleton_id=1', limit: 1);
    await db.insert(
      SyncFoundationTables.context,
      {
        'singleton_id': 1,
        'user_id': null,
        'origin': 'remote',
        'remote_entity_type': '__migration__',
        'remote_entity_uuid': '00000000-0000-4000-8000-000000000080',
        'remote_revision': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await RepairTables.ensureRepairsSchema(db);
      await SyncFoundationTables.ensure(db);
      await _backfillRepairSyncReferences(db);
      await UnifiedSyncTables.ensure(db);
      await UnifiedSyncTables.refreshRepairPayloadsForMigration(db);
    } finally {
      if (oldContext.isEmpty) {
        await db.delete(SyncFoundationTables.context, where: 'singleton_id=1');
      } else {
        await db.insert(
          SyncFoundationTables.context,
          Map<String, Object?>.from(oldContext.single),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await UnifiedSyncQueueService.resetInterruptedSending(db);
    await db.insert(
      'schema_migrations',
      {'version': 80, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _backfillRepairSyncReferences(Database db) async {
    final rows = await db.query(
      'repairs',
      columns: const [
        'id',
        'client_id',
        'vehicleNumber',
        'customer_party_uuid',
        'vehicle_entity_uuid'
      ],
    );
    for (final row in rows) {
      String? partyUuid = row['customer_party_uuid']?.toString().trim();
      if (partyUuid != null && partyUuid.isEmpty) partyUuid = null;
      final rawClient = row['client_id'];
      final clientId = rawClient is num
          ? rawClient.toInt()
          : int.tryParse(rawClient?.toString() ?? '');
      if (partyUuid == null && clientId != null) {
        final partyId = await PartyTables.resolvePartyId(
          db,
          role: 'CUSTOMER',
          legacyId: clientId,
        );
        if (partyId != null) {
          final registry = await db.query(
            SyncFoundationTables.registry,
            columns: const ['entity_uuid'],
            where: 'entity_type=? AND local_id=?',
            whereArgs: ['party', partyId],
            limit: 1,
          );
          if (registry.isNotEmpty) {
            partyUuid = registry.single['entity_uuid']?.toString();
          }
        }
      }

      String? vehicleUuid = row['vehicle_entity_uuid']?.toString().trim();
      if (vehicleUuid != null && vehicleUuid.isEmpty) vehicleUuid = null;
      if (vehicleUuid == null) {
        final normalized = VehicleTables.normalizeNumber(
          row['vehicleNumber']?.toString() ?? '',
        );
        if (normalized.isNotEmpty) {
          final vehicles = await db.query(
            VehicleTables.tableName,
            columns: const ['id'],
            where: 'normalized_number=?',
            whereArgs: [normalized],
            limit: 2,
          );
          if (vehicles.length == 1) {
            final registry = await db.query(
              SyncFoundationTables.registry,
              columns: const ['entity_uuid'],
              where: 'entity_type=? AND local_id=?',
              whereArgs: ['vehicle', vehicles.single['id'].toString()],
              limit: 1,
            );
            if (registry.isNotEmpty) {
              vehicleUuid = registry.single['entity_uuid']?.toString();
            }
          }
        }
      }

      final update = <String, Object?>{};
      if (partyUuid != null && row['customer_party_uuid'] != partyUuid) {
        update['customer_party_uuid'] = partyUuid;
      }
      if (vehicleUuid != null && row['vehicle_entity_uuid'] != vehicleUuid) {
        update['vehicle_entity_uuid'] = vehicleUuid;
      }
      if (update.isNotEmpty) {
        await db
            .update('repairs', update, where: 'id=?', whereArgs: [row['id']]);
      }
    }
  }

  static Future<void> _upgradeV79(Database db) async {
    final oldContext = await db.query(SyncFoundationTables.context,
        where: 'singleton_id=1', limit: 1);
    await db.insert(
      SyncFoundationTables.context,
      {
        'singleton_id': 1,
        'user_id': null,
        'origin': 'remote',
        'remote_entity_type': '__migration__',
        'remote_entity_uuid': '00000000-0000-4000-8000-000000000079',
        'remote_revision': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await VehicleTables.ensure(db);
      await VehicleTables.backfillOwnerPartyUuid(db);
      await SyncFoundationTables.ensure(db);
      await UnifiedSyncTables.ensure(db);
    } finally {
      if (oldContext.isEmpty) {
        await db.delete(SyncFoundationTables.context, where: 'singleton_id=1');
      } else {
        await db.insert(SyncFoundationTables.context,
            Map<String, Object?>.from(oldContext.single),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await db.insert(
      'schema_migrations',
      {'version': 79, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _upgradeV78(Database db) async {
    await LicenseRuntimeTables.runTrustedMigrationBackfill(
      db,
      () async {
        await PartyTables.ensure(db);
        await SyncFoundationTables.ensure(db);
        await UnifiedSyncTables.ensure(db);
      },
    );
    await UnifiedSyncQueueService.resetInterruptedSending(db);
    await db.insert(
      'schema_migrations',
      {'version': 78, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _upgradeV77(Database db) async {
    await SyncFoundationTables.ensure(db);
    await UnifiedSyncTables.ensure(db);
    await UnifiedSyncQueueService.resetInterruptedSending(db);
    await InsuranceTables.createAllTables(db);
    await db.insert(
      'schema_migrations',
      {'version': 77, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _upgradeV76(Database db) async {
    await RawMaterialService.createTable(db);
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert(
      'schema_migrations',
      {'version': 76, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _upgradeV75(Database db) async {
    // Stage 5 commercial Job Costing becomes part of the versioned schema.
    await RepairCostService.ensureSchema(db);
    await LicenseRuntimeTables.runTrustedMigrationBackfill(
      db,
      () => PartyTables.ensure(db),
    );
    await SyncFoundationTables.ensure(db);
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert(
      'schema_migrations',
      {'version': 75, 'applied_at': DateTime.now().toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _upgradeV74(Database db) async {
    await CloudIdentityTables.ensure(db);
    await SyncFoundationTables.ensure(db);
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert('schema_migrations',
        {'version': 74, 'applied_at': DateTime.now().toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _upgradeV73(Database db) async {
    await WorkshopOnboardingTables.ensure(db);
    await SyncFoundationTables.ensure(db);
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert(
        'schema_migrations',
        {
          'version': 73,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _upgradeV72(Database db) async {
    await IdentityAccountTables.ensure(db);
    await UserAuthorizationTables.refreshRoleCatalog(db);
    await LicenseRuntimeTables.installOperationalTriggers(db);
    await db.insert(
        'schema_migrations',
        {
          'version': 72,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _upgradeV71(Database db) async {
    await LicenseRuntimeTables.upgradeBackupAvailability(db);
    await db.insert(
        'schema_migrations',
        {
          'version': 71,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // Sqflite runs onCreate/onUpgrade in one transaction and advances
  // user_version only after this entire versioned migration succeeds.
  static Future<void> _upgradeV70(Database db) async {
    // Consolidate the previously unversioned v69 compatibility additions.
    await ensureP05VehicleCompatibilityBeforeValidation(db);
    await ensureP04OutboxCompatibilityBeforeValidation(db);
    await UserTables.ensureWorkshopSettingsCompatibility(db);
    await PaymentsTables.ensurePaymentsSchema(db);
    await ReceiptTables.createAllTables(db);
    await PurchaseInvoicesTable.createAllTables(db);
    await PurchasePaymentsTable.createAllTables(db);
    await ensureStage1AccountingCoreCompatibilityBeforeValidation(db);
    await db.execute('CREATE TABLE IF NOT EXISTS schema_migrations '
        '(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)');
    await db.insert(
        'schema_migrations',
        {
          'version': 70,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
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
    // Authorization and backup metadata are included in versioned initialization.
    await P16SecurityTables.ensure(db);

    await ChequeTables.ensureChequesSchema(db);
    await AccountingTables.ensureInvoicesSchema(db);
    await PaymentsTables.ensurePaymentsSchema(db);
    await ReceiptTables.createAllTables(db);
    await InsuranceTables.ensureInsuranceSchema(db);

    // Stage 1 canonical accounting core: safe additive
    // compatibility plus read-time Party mapping preserves historical GL.
    await PartyTables.ensure(db);
    await AccountingIntegrityTables.ensure(db);

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

    await VoucherTables.runTrustedPostedVoucherBackfill(
      db,
      () => db.execute(r'''
        UPDATE vouchers
        SET currency = COALESCE(NULLIF(TRIM(currency), ''), 'ILS'),
            currency_decimals = COALESCE(currency_decimals, 2)
        WHERE NULLIF(TRIM(currency), '') IS NULL OR currency_decimals IS NULL;
      '''),
    );

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

  /// Stage 1 current-v69 compatibility hook.
  @visibleForTesting
  static Future<void> ensureStage1AccountingCoreCompatibilityBeforeValidation(
    DatabaseExecutor db,
  ) async {
    await PartyTables.ensure(db);
    await AccountingIntegrityTables.ensure(db);
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
    await IdentityAccountTables.validate(db);
    await SyncFoundationTables.validate(db);
    await UnifiedSyncTables.validate(db);
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
        ReleaseDiagnostics.debug("Database migration step");
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
    ReleaseDiagnostics.debug('Development DB reset completed');
  }

  // ============================================================
  // Debug.
  // ============================================================
  static Future<void> _debugDump(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    ReleaseDiagnostics.debug('DB Tables:');
    for (final t in tables) {
      final name = t['name'] as String;
      final count = await db.rawQuery("SELECT COUNT(*) c FROM $name");
      ReleaseDiagnostics.debug('  - $name: ${count.first['c']}');
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

    ReleaseDiagnostics.debug("linked_payment_ids compatibility update");

    if (hasOld) {
      await db.execute(
          "ALTER TABLE cheques RENAME COLUMN linked_payment_id TO linked_payment_ids;");
      ReleaseDiagnostics.debug(
          "أ¢إ“â€‌ ط·آ¥ط·آ¹ط·آ§ط·آ¯ط·آ© ط·ع¾ط·آ³ط¸â€¦ط¸ظ¹ط·آ© ط·آ§ط¸â€‍ط·آ¹ط¸â€¦ط¸ث†ط·آ¯ ط·ع¾ط¸â€¦ط·ع¾ ط·آ¨ط¸â€ ط·آ¬ط·آ§ط·آ­");
      return;
    }

    await db.execute("ALTER TABLE cheques ADD COLUMN linked_payment_ids TEXT;");
    ReleaseDiagnostics.debug("linked_payment_ids compatibility update");
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
      ReleaseDiagnostics.debug("Database migration step");
      await db.execute("ALTER TABLE vouchers ADD COLUMN source TEXT;");
    }

    if (!hasSourceId) {
      ReleaseDiagnostics.debug("Database migration step");
      await db.execute("ALTER TABLE vouchers ADD COLUMN source_id TEXT;");
    }
  }
}
