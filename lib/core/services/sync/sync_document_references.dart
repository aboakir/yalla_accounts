import 'package:sqflite/sqflite.dart';
import '../db/tables/sync_foundation_tables.dart';

/// Read-only UUID edges for future transport. Never guesses a relation by name
/// or applies a remote document. An unresolved edge blocks export readiness.
class SyncDocumentReferences {
  SyncDocumentReferences._();

  static Future<Map<String, Object?>> resolve(
    DatabaseExecutor db, {
    required String entityType,
    required String organizationId,
    required Map<String, Object?> snapshot,
  }) async {
    final references = <String, Object?>{};
    final unresolved = <String>[];
    final fields = <String, String>{
      'client_id': 'client',
      'supplier_id': 'supplier',
      'employee_id': 'employee',
      'employeeId': 'employee',
      'vehicle_id': 'vehicle',
      'repair_id': 'repair',
      'account_id': 'account',
      'cash_account_id': 'account',
      'bank_account_id': 'account',
      'entry_id': 'gl_entry',
      'gl_entry_id': 'gl_entry',
      'payment_id': 'payment',
      'voucher_id': 'voucher',
      'payroll_run_id': 'payroll_run',
      'invoice_id': entityType == 'purchase_invoice_line' ||
              entityType == 'purchase_payment'
          ? 'purchase_invoice'
          : 'invoice',
      if (entityType == 'account') 'parent_id': 'account',
      if (entityType == 'party') 'merged_into_id': 'party',
    };
    final role = '${snapshot['party_type'] ?? ''}'.toUpperCase();
    if (snapshot.containsKey('party_id')) {
      fields['party_id'] = switch (role) {
        'CUSTOMER' || 'CLIENT' => 'client',
        'SUPPLIER' => 'supplier',
        'EMPLOYEE' => 'employee',
        _ => 'party',
      };
    }
    for (final entry in fields.entries) {
      final raw = snapshot[entry.key];
      if (raw == null || '$raw'.trim().isEmpty) continue;
      final rows = await db.query(SyncFoundationTables.registry,
          columns: ['entity_uuid'],
          where: 'entity_type=? AND local_id=? AND organization_id=?',
          whereArgs: [entry.value, '$raw', organizationId]);
      if (rows.length != 1) {
        unresolved.add(entry.key);
      } else {
        references[entry.key] = {
          'entity_type': entry.value,
          'entity_uuid': rows.single['entity_uuid']
        };
      }
    }
    // Legacy repairs store the plate instead of a vehicle_id. Resolve only one
    // exact vehicle for the same client. Ambiguous or missing records stay local.
    final plate = '${snapshot['vehicleNumber'] ?? ''}'.trim();
    if (entityType == 'repair' &&
        plate.isNotEmpty &&
        snapshot['vehicle_id'] == null) {
      final rows = await db.rawQuery('''SELECT r.entity_uuid
        FROM vehicles v JOIN ${SyncFoundationTables.registry} r
          ON r.entity_type='vehicle' AND r.local_id=CAST(v.id AS TEXT)
        WHERE TRIM(v.number)=? AND v.client_id=? AND r.organization_id=?''',
          [plate, snapshot['client_id'], organizationId]);
      if (rows.length == 1) {
        references['vehicleNumber'] = {
          'entity_type': 'vehicle',
          'entity_uuid': rows.single['entity_uuid']
        };
      } else {
        unresolved.add('vehicleNumber');
      }
    }
    return {
      'references': references,
      'unresolved': unresolved,
      'ready': unresolved.isEmpty
    };
  }
}
