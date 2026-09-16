import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';

class PurchaseSyncReferenceService {
  PurchaseSyncReferenceService._();

  static Future<String?> supplierPartyUuid(
    DatabaseExecutor db,
    int supplierId,
  ) async {
    if (supplierId <= 0 || !await SyncFoundationTables.isInstalled(db)) {
      return null;
    }
    final partyId = await PartyTables.resolvePartyId(
      db,
      role: 'SUPPLIER',
      legacyId: supplierId,
    );
    if (partyId == null) return null;
    final rows = await db.query(
      SyncFoundationTables.registry,
      columns: const ['entity_uuid'],
      where: 'entity_type=? AND local_id=?',
      whereArgs: ['party', partyId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['entity_uuid']?.toString();
  }

  static Future<String?> invoiceEntityUuid(
    DatabaseExecutor db,
    String invoiceId,
  ) async {
    if (!await SyncFoundationTables.isInstalled(db)) return null;
    final rows = await db.query(
      SyncFoundationTables.registry,
      columns: const ['entity_uuid'],
      where: 'entity_type=? AND local_id=?',
      whereArgs: ['purchase_invoice', invoiceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['entity_uuid']?.toString();
  }
}
