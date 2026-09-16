import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/parties/services/party_sync_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_sync_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_sync_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_sync_service.dart';

import 'unified_sync_queue_service.dart';

class UnifiedSyncInboundRouter {
  UnifiedSyncInboundRouter._();

  static Future<void> apply(
    DatabaseExecutor transaction,
    InboundSyncChange change,
  ) async {
    switch (change.entityType) {
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
