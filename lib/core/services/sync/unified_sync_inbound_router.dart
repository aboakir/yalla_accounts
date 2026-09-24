import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/parties/services/party_sync_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_sync_service.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_sync_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_sync_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_sync_service.dart';

import 'financial_hr_sync_service.dart';
import 'insurance_sync_service.dart';
import 'sync_file_metadata_service.dart';
import 'unified_sync_queue_service.dart';

class UnifiedSyncInboundRouter {
  UnifiedSyncInboundRouter._();

  static Future<void> apply(
    DatabaseExecutor transaction,
    InboundSyncChange change,
  ) async {
    if (FinancialHrSyncService.handledTypes.contains(change.entityType)) {
      await FinancialHrSyncService.applyInbound(transaction, change);
      return;
    }
    if (InsuranceSyncService.handledTypes.contains(change.entityType)) {
      await InsuranceSyncService.applyInbound(transaction, change);
      return;
    }
    // Chart-of-accounts rows are intentionally not a standalone wire entity.
    // GL lines carry the canonical account code/metadata required to resolve it.
    if (change.entityType == 'account') return;

    switch (change.entityType) {
      case 'file_ref':
        await SyncFileMetadataService.applyInbound(transaction, change);
        return;
      case 'party':
        await PartySyncService.applyInbound(transaction, change);
        return;
      case 'vehicle':
        await VehicleSyncService.applyInbound(transaction, change);
        return;
      case 'repair':
      case 'repair_line':
      case 'repair_workflow':
        await RepairSyncService.applyInbound(transaction, change);
        return;
      case 'purchase_invoice':
      case 'purchase_invoice_line':
      case 'purchase_payment':
        await PurchaseSyncService.applyInbound(transaction, change);
        return;
      case 'inventory_item':
      case 'inventory_warehouse':
      case 'inventory_movement':
      case 'inventory_item_alternative':
      case 'inventory_item_compatibility':
        await InventorySyncService.applyInbound(transaction, change);
        return;
      // Phase 06 compatibility: obsolete wire projections from pre-master-Party clients.
      // Their legacy IDs are device-local and must never be applied remotely.
      // The canonical Party record is authoritative for cross-device identity.
      case 'client':
      case 'supplier':
        return;
      default:
        throw StateError('SYNC_INBOUND_APPLIER_MISSING:${change.entityType}');
    }
  }
}
