import 'package:sqflite/sqflite.dart';

import '../services/db/db_service.dart';
import '../services/db/tables/device_identity_tables.dart';
import '../services/db/tables/license_runtime_tables.dart';
import '../services/db/tables/organization_identity_tables.dart';
import '../services/db/tables/owner_bootstrap_tables.dart';

typedef CommercialOrganizationDatabaseProvider = Future<Database> Function();

class CommercialOrganizationBindingException implements Exception {
  const CommercialOrganizationBindingException(this.code);
  final String code;

  @override
  String toString() => 'CommercialOrganizationBindingException($code)';
}

/// Reconciles the installation-local bootstrap organization with the canonical
/// organization issued by the PHP commercial backend.
///
/// A fresh installation receives a local UUID before it has server authority.
/// Once license-check returns the canonical organization, that placeholder must
/// be replaced before First Owner creation or authenticated access checks.
class CommercialOrganizationBindingService {
  CommercialOrganizationBindingService({
    CommercialOrganizationDatabaseProvider? databaseProvider,
  }) : _databaseProvider = databaseProvider ?? (() => DBService.database);

  final CommercialOrganizationDatabaseProvider _databaseProvider;

  static const _operationalTables = <String>{
    'clients',
    'vehicles',
    'repairs',
    'invoices',
    'repair_lines',
    'repairs_images',
    'repair_workflow',
    'repair_workflow_events',
    'gl_entries',
    'gl_lines',
    'payments',
    'journal_entries',
    'ledger_entries',
    'employees',
    'attendance',
    'employee_advances',
    'payroll_runs',
    'payroll_payments',
    'cheques',
    'cheque_events',
    'cheque_voucher_links',
    'cheque_allocations',
    'cheque_books',
    'cheque_deposit_batches',
    'cheque_deposit_items',
    'cheque_endorsements',
    'monthly_expenses',
    'receipt_requests',
    'receipt_headers',
    'receipt_allocations',
    'receipt_instruments',
    'customer_credit_allocations',
    'vouchers',
    'purchase_invoices',
    'purchase_invoice_lines',
    'purchase_payments',
    'insurance_policies',
    'insurance_policy_cheques',
    'insurance_policy_installments',
    'insurance_policy_promissories',
    'insurance_invoices',
    'invoice_settlements',
    'raw_materials',
  };

  Future<void> reconcile(String canonicalOrganizationId) async {
    final canonical = canonicalOrganizationId.trim();
    if (!_looksLikeUuid(canonical)) {
      throw const CommercialOrganizationBindingException(
        'INVALID_CANONICAL_ORGANIZATION',
      );
    }

    final db = await _databaseProvider();
    await db.transaction((txn) async {
      final identity = await txn.query(
        'organization_identity',
        columns: const ['organization_id'],
        where: 'singleton_id = 1',
        limit: 2,
      );
      if (identity.length != 1) {
        throw const CommercialOrganizationBindingException(
          'LOCAL_ORGANIZATION_MISSING',
        );
      }

      final current = identity.single['organization_id']?.toString() ?? '';
      if (current == canonical) return;
      if (!_looksLikeUuid(current)) {
        throw const CommercialOrganizationBindingException(
          'LOCAL_ORGANIZATION_INVALID',
        );
      }

      await _assertNoOperationalData(txn);

      final currentRows = await txn.query(
        'organizations',
        where: 'id = ?',
        whereArgs: [current],
        limit: 1,
      );
      if (currentRows.length != 1) {
        throw const CommercialOrganizationBindingException(
          'LOCAL_ORGANIZATION_ROW_MISSING',
        );
      }
      final currentRow = currentRows.single;

      final canonicalRows = await txn.query(
        'organizations',
        where: 'id = ?',
        whereArgs: [canonical],
        limit: 1,
      );
      if (canonicalRows.isEmpty) {
        final now = DateTime.now().toUtc().toIso8601String();
        await txn.insert('organizations', {
          'id': canonical,
          'display_name': currentRow['display_name'],
          'country_code': currentRow['country_code'],
          'status': 'active',
          'created_at': currentRow['created_at'] ?? now,
          'updated_at': now,
        });
      }

      // Scope guards on users/workshop_settings validate against this singleton.
      // Move the singleton first, then move every scoped row to the same UUID.
      await txn.update(
        'organization_identity',
        {'organization_id': canonical},
        where: 'singleton_id = 1 AND organization_id = ?',
        whereArgs: [current],
      );

      await LicenseRuntimeTables.runTrustedMigrationBackfill(txn, () async {
        final tables = await txn.rawQuery(
          "SELECT name FROM sqlite_master "
          "WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        );
        for (final row in tables) {
          final table = row['name']?.toString() ?? '';
          // sync_change_log is append-only historical evidence. Its
          // organization_id is intentionally not an FK to organizations and
          // must retain the original bootstrap attribution.
          if (!_safeIdentifier(table) ||
              table == 'organizations' ||
              table == 'sync_change_log') {
            continue;
          }
          final columns = await txn.rawQuery('PRAGMA table_info("$table")');
          if (!columns.any((column) => column['name'] == 'organization_id')) {
            continue;
          }
          await txn.update(
            table,
            {'organization_id': canonical},
            where: 'organization_id = ?',
            whereArgs: [current],
          );
        }
      });

      final deleted = await txn.delete(
        'organizations',
        where: 'id = ?',
        whereArgs: [current],
      );
      if (deleted != 1) {
        throw const CommercialOrganizationBindingException(
          'PLACEHOLDER_ORGANIZATION_NOT_REMOVED',
        );
      }

      final foreignKeyProblems = await txn.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeyProblems.isNotEmpty) {
        throw const CommercialOrganizationBindingException(
          'FOREIGN_KEY_REBIND_FAILED',
        );
      }

      await OrganizationIdentityTables.validate(txn);
      await OwnerBootstrapTables.validate(txn);
      await DeviceIdentityTables.validate(txn);
    });
  }

  Future<void> _assertNoOperationalData(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final existing = tables
        .map((row) => row['name']?.toString() ?? '')
        .where(_operationalTables.contains)
        .toSet();

    for (final table in existing) {
      if (!_safeIdentifier(table)) continue;
      final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM "$table"'),
          ) ??
          0;
      if (count != 0) {
        throw CommercialOrganizationBindingException(
          'LOCAL_OPERATIONAL_DATA_PRESENT:$table',
        );
      }
    }
  }

  static bool _looksLikeUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
        r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  static bool _safeIdentifier(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
}
