import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/repair_tables.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair_intake_draft.dart';
import 'package:yalla_accounts/features/repairs/services/repair_payer_bridge.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_sync_reference_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

/// P07 canonical intake save path.
///
/// This deliberately creates only an intake/QUOTE repair. It does not create
/// an invoice, approve a quote, post GL, or create a payment. Those are owned
/// by later phases (P09+ / P10+).
class RepairIntakeService {
  RepairIntakeService._();

  static Future<String> save(RepairIntakeDraft draft) async {
    final repairId = await DBService.inTx<String>((db) => saveOn(db, draft));

    // Run image scoring only after the intake transaction commits.
    if (draft.photoPaths.any((path) => path.trim().isNotEmpty)) {
      try {
        final svc = await RepairsService.instance();
        await svc.autoSelectCoverAndSave(repairId: repairId);
      } catch (_) {
        // Profile selection is non-critical; repair creation must stay valid.
      }
    }

    return repairId;
  }

  static Future<String> saveOn(
    DatabaseExecutor db,
    RepairIntakeDraft draft,
  ) async {
    await RepairTables.ensureP07IntakeSchema(db);

    final clientName = draft.clientName.trim();
    if (clientName.isEmpty) {
      throw StateError('اسم العميل مطلوب');
    }

    final vehicleNumber = draft.vehicleNumber.trim();
    if (vehicleNumber.isEmpty) {
      throw StateError('رقم المركبة مطلوب');
    }

    if (draft.odometer < 0) {
      throw StateError('قراءة العداد غير صحيحة');
    }
    if (draft.fuelLevel < 0 || draft.fuelLevel > 100) {
      throw StateError('مستوى الوقود يجب أن يكون بين 0 و100');
    }
    // P07: intake documentation is optional.
    // Zero photos and an empty signature path are valid.
    // Keep the intake image limit aligned with the UI.
    if (draft.photoPaths.length > 8) {
      throw StateError('الحد الأقصى لصور الاستلام هو 8 صور');
    }
    var effectiveNotes = draft.notes.trim();
    final payerKind = RepairPayerBridge.resolve(notes: effectiveNotes);
    if (payerKind == RepairPayerKind.insurance ||
        payerKind == RepairPayerKind.mixed) {
      final insuranceCompany =
          RepairPayerBridge.insuranceCompanyNameFromNotes(effectiveNotes);
      if (insuranceCompany != null) {
        final insuranceClientId = await ClientService.upsertFromRepairOn(
          db,
          name: insuranceCompany,
          type: 'شركة تأمين',
        );
        effectiveNotes = RepairPayerBridge.withInsuranceClientId(
          effectiveNotes,
          insuranceClientId,
        );
      }
    }

    final clientId = draft.clientId ??
        await ClientService.upsertFromRepairOn(
          db,
          name: clientName,
          type: draft.clientType.trim().isEmpty
              ? 'أفراد'
              : draft.clientType.trim(),
        );

    final vehicleId = await VehicleService.upsertFromRepairOn(
      db,
      number: vehicleNumber,
      type: draft.vehicleType.trim(),
      model: draft.vehicleModel.trim(),
      clientId: clientId,
    );

    final syncRefs = await RepairSyncReferenceService.resolve(
      db, clientId: clientId, vehicleId: vehicleId);

    final repairId = DBService.newUuid();
    final now = DateTime.now().toUtc().toIso8601String();
    final receivedAt = draft.receivedDate.toUtc().toIso8601String();
    final photos = draft.photoPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);

    await db.insert(
      'repairs',
      <String, Object?>{
        'id': repairId,
        'invoiceNumber': '',
        'vehicleModel': draft.vehicleModel.trim(),
        'vehicleType': draft.vehicleType.trim(),
        'vehicleNumber': vehicleNumber,
        'receivedDate': receivedAt,
        'beneficiaryType':
            draft.clientType.trim().isEmpty ? 'أفراد' : draft.clientType.trim(),
        'beneficiaryName': clientName,
        'client_id': clientId,
        'customer_party_uuid': syncRefs.customerPartyUuid,
        'vehicle_entity_uuid': syncRefs.vehicleEntityUuid,
        'is_active': 1,
        'insuranceStatus': '',
        'repairType': '',
        'vehicleStatus': 'بانتظار الإصلاح',
        'status': 'QUOTE',
        'parts': jsonEncode(const <Object>[]),
        'works': jsonEncode(const <Object>[]),
        'fileValue': 0.0,
        'paymentType': payerKind == RepairPayerKind.insurance
            ? 'insurance'
            : payerKind == RepairPayerKind.mixed
                ? 'mixed'
                : 'cash',
        'paidAmount': 0.0,
        'paymentStatus': 'غير مسدد',
        'notes': effectiveNotes,
        'imagePaths': jsonEncode(photos),
        'isArchived': 0,
        'isLedgerEnabled': 0,
        'isLedgerSynced': 0,
        'thumbnail_path': photos.isEmpty ? '' : photos.first,
        'thumbnail_updated_at': now,
        'created_at': now,
        'updated_at': now,
        'odometer': draft.odometer,
        'fuel_level': draft.fuelLevel,
        'previous_damage': draft.previousDamage.trim(),
        'customer_signature_path': draft.customerSignaturePath.trim(),
        'intake_completed_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    for (final path in photos) {
      await db.insert(
        'repairs_images',
        <String, Object?>{
          'id': DBService.newUuid(),
          'repair_id': repairId,
          'path': path,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    await OfflineOutboxService.enqueue(
      db,
      channel: OfflineOutboxService.channelSync,
      operation: 'UPSERT',
      entityType: 'repair',
      entityId: repairId,
      idempotencyKey: 'repair:$repairId:create',
      payload: <String, dynamic>{
        'schema': 1,
        'entity_type': 'repair',
        'entity_id': repairId,
        'operation': 'UPSERT',
        'workflow_status': 'QUOTE',
        'intake_completed': true,
        'updated_at': now,
      },
    );

    return repairId;
  }
}
