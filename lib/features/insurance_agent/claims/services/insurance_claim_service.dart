import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';

class InsuranceClaimRecord {
  const InsuranceClaimRecord({
    required this.id,
    required this.claimNumber,
    required this.policyId,
    required this.insuredPartyId,
    required this.vehicleId,
    required this.companyId,
    required this.status,
    required this.reportedAt,
    required this.createdAt,
    required this.updatedAt,
    this.lossDate,
    this.financialEventId,
    this.notes,
  });

  final String id;
  final String claimNumber;
  final String policyId;
  final String insuredPartyId;
  final int vehicleId;
  final int companyId;
  final String status;
  final DateTime? lossDate;
  final DateTime reportedAt;
  final String? financialEventId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  static DateTime? _date(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  factory InsuranceClaimRecord.fromRow(Map<String, Object?> row) {
    return InsuranceClaimRecord(
      id: row['id'].toString(),
      claimNumber: (row['claim_number'] ?? '').toString(),
      policyId: row['policy_id'].toString(),
      insuredPartyId: row['insured_party_id'].toString(),
      vehicleId: int.parse(row['vehicle_id'].toString()),
      companyId: int.parse(row['company_id'].toString()),
      status: row['status'].toString().trim().toUpperCase(),
      lossDate: _date(row['loss_date']),
      reportedAt: DateTime.parse(row['reported_at'].toString()),
      financialEventId: row['financial_event_id']?.toString(),
      notes: row['notes']?.toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      updatedAt: DateTime.parse(row['updated_at'].toString()),
    );
  }
}

class InsuranceClaimDocumentRecord {
  const InsuranceClaimDocumentRecord({
    required this.id,
    required this.claimId,
    required this.documentType,
    required this.filePath,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String claimId;
  final String documentType;
  final String filePath;
  final String? notes;
  final DateTime createdAt;

  factory InsuranceClaimDocumentRecord.fromRow(Map<String, Object?> row) {
    return InsuranceClaimDocumentRecord(
      id: row['id'].toString(),
      claimId: row['claim_id'].toString(),
      documentType: row['document_type'].toString(),
      filePath: row['file_path'].toString(),
      notes: row['notes']?.toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
    );
  }
}

class InsuranceClaimRepairOption {
  const InsuranceClaimRepairOption({
    required this.repairId,
    required this.vehicleNumber,
    this.beneficiaryName,
    this.vehicleStatus,
    this.receivedDate,
  });

  final String repairId;
  final String vehicleNumber;
  final String? beneficiaryName;
  final String? vehicleStatus;
  final DateTime? receivedDate;

  factory InsuranceClaimRepairOption.fromRow(Map<String, Object?> row) {
    final received = row['receivedDate']?.toString().trim();
    return InsuranceClaimRepairOption(
      repairId: row['id'].toString(),
      vehicleNumber: (row['vehicleNumber'] ?? '').toString(),
      beneficiaryName: row['beneficiaryName']?.toString(),
      vehicleStatus: row['vehicleStatus']?.toString(),
      receivedDate: received == null || received.isEmpty
          ? null
          : DateTime.tryParse(received),
    );
  }
}

class InsuranceClaimTimelineEvent {
  const InsuranceClaimTimelineEvent({
    required this.id,
    required this.action,
    required this.createdAt,
    this.reason,
    this.before,
    this.after,
    this.metadata,
  });
  final int id;
  final String action;
  final DateTime createdAt;
  final String? reason;
  final Object? before;
  final Object? after;
  final Map<String, Object?>? metadata;

  static Object? _decode(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  factory InsuranceClaimTimelineEvent.fromRow(Map<String, Object?> row) {
    final rawMetadata = _decode(row['metadata_json']);
    return InsuranceClaimTimelineEvent(
      id: int.parse(row['id'].toString()),
      action: row['action'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      reason: row['reason']?.toString(),
      before: _decode(row['before_json']),
      after: _decode(row['after_json']),
      metadata: rawMetadata is Map
          ? rawMetadata.map((key, value) => MapEntry(key.toString(), value))
          : null,
    );
  }
}

class InsuranceClaimService {
  InsuranceClaimService._();

  static const entityType = 'INSURANCE_CLAIM';
  static const statuses = <String>{
    'NEW',
    'DOCUMENTS_REQUIRED',
    'SUBMITTED',
    'ASSESSOR',
    'APPROVED',
    'REPAIR',
    'SETTLED',
    'CLOSED',
    'REJECTED',
  };

  static const Map<String, Set<String>> _transitions = {
    'NEW': {'DOCUMENTS_REQUIRED', 'SUBMITTED', 'REJECTED'},
    'DOCUMENTS_REQUIRED': {'SUBMITTED', 'REJECTED'},
    'SUBMITTED': {'DOCUMENTS_REQUIRED', 'ASSESSOR', 'REJECTED'},
    'ASSESSOR': {'DOCUMENTS_REQUIRED', 'APPROVED', 'REJECTED'},
    'APPROVED': {'REPAIR', 'SETTLED', 'CLOSED'},
    'REPAIR': {'SETTLED', 'CLOSED'},
    'SETTLED': {'CLOSED'},
    'CLOSED': <String>{},
    'REJECTED': <String>{},
  };

  static Set<String> allowedTransitions(String status) => Set.unmodifiable(
        _transitions[status.trim().toUpperCase()] ?? const <String>{},
      );
  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _json(Object? value) => jsonEncode(value);

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static Future<Map<String, Object?>> _policy(
    DatabaseExecutor db,
    String policyId,
  ) async {
    final rows = await db.query(
      'insurance_policies',
      columns: const [
        'id',
        'policy_number',
        'insured_party_id',
        'vehicle_id',
        'insurance_company_id',
        'posting_status',
        'status',
      ],
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Insurance policy not found.');
    }
    final row = rows.single;
    final postingStatus = _clean(row['posting_status'])?.toUpperCase();
    if (postingStatus != 'POSTED') {
      throw StateError('Claim requires a posted insurance policy.');
    }
    if (_clean(row['insured_party_id']) == null ||
        row['vehicle_id'] == null ||
        _clean(row['insurance_company_id']) == null) {
      throw StateError('Policy is missing canonical claim relationships.');
    }
    return row;
  }

  static Future<void> _audit(
    DatabaseExecutor db, {
    required String claimId,
    required String action,
    Object? before,
    Object? after,
    String? reason,
    String? actorUserId,
    Map<String, Object?>? metadata,
  }) async {
    await db.insert('app_audit_events', {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'actor_user_id': _clean(actorUserId),
      'action': action,
      'entity_type': entityType,
      'entity_id': claimId,
      'before_json': before == null ? null : _json(before),
      'after_json': after == null ? null : _json(after),
      'reason': _clean(reason),
      'metadata_json': metadata == null ? null : _json(metadata),
    });
  }

  static String _generatedClaimNumber(DateTime now) {
    final token = const Uuid().v4().replaceAll('-', '').substring(0, 8);
    return 'CLM-${now.year}-${token.toUpperCase()}';
  }

  static Future<InsuranceClaimRecord> createClaim({
    required String policyId,
    String? claimNumber,
    DateTime? lossDate,
    DateTime? reportedAt,
    String? notes,
    String? workshopRef,
    String? actorUserId,
    DatabaseExecutor? database,
  }) async {
    final db = await _db(database);
    final cleanPolicyId = policyId.trim();
    if (cleanPolicyId.isEmpty) {
      throw ArgumentError.value(policyId, 'policyId', 'Policy is required.');
    }

    late InsuranceClaimRecord result;
    await SyncFoundationService.writeOn<void>(db, (txn) async {
      final policy = await _policy(txn, cleanPolicyId);
      final now = DateTime.now();
      final id = const Uuid().v4();
      final number = _clean(claimNumber) ?? _generatedClaimNumber(now);
      final insuredPartyId = policy['insured_party_id'].toString();
      final vehicleId = int.parse(policy['vehicle_id'].toString());
      final companyId = int.parse(policy['insurance_company_id'].toString());
      final reported = reportedAt ?? now;
      final values = <String, Object?>{
        'id': id,
        'claim_number': number,
        'policy_id': cleanPolicyId,
        'insured_party_id': insuredPartyId,
        'vehicle_id': vehicleId,
        'company_id': companyId,
        'status': 'NEW',
        'loss_date': lossDate?.toIso8601String(),
        'reported_at': reported.toIso8601String(),
        'financial_event_id': null,
        'notes': _clean(notes),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      await txn.insert('insurance_claims', values);
      await _audit(
        txn,
        claimId: id,
        action: 'CLAIM_CREATED',
        after: values,
        actorUserId: actorUserId,
        metadata: {
          if (_clean(workshopRef) != null) 'workshop_ref': _clean(workshopRef),
          'policy_number': _clean(policy['policy_number']),
        },
      );
      result = InsuranceClaimRecord.fromRow(values);
    });
    return result;
  }

  static Future<void> transitionStatus({
    required String claimId,
    required String status,
    String? reason,
    String? actorUserId,
    DatabaseExecutor? database,
  }) async {
    final db = await _db(database);
    final target = status.trim().toUpperCase();
    if (!statuses.contains(target)) {
      throw ArgumentError.value(status, 'status', 'Unsupported claim status.');
    }

    await SyncFoundationService.writeOn<void>(db, (txn) async {
      final rows = await txn.query(
        'insurance_claims',
        where: 'id=?',
        whereArgs: [claimId.trim()],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Insurance claim not found.');
      final row = rows.single;
      final current = row['status'].toString().trim().toUpperCase();
      if (current == target) return;
      final allowed = _transitions[current] ?? const <String>{};
      if (!allowed.contains(target)) {
        throw StateError('Invalid claim transition $current -> $target.');
      }
      final updatedAt = DateTime.now().toIso8601String();
      final changed = await txn.update(
        'insurance_claims',
        {'status': target, 'updated_at': updatedAt},
        where: 'id=? AND status=?',
        whereArgs: [claimId.trim(), current],
      );
      if (changed != 1) throw StateError('Claim status update was not atomic.');
      await _audit(
        txn,
        claimId: claimId.trim(),
        action: 'CLAIM_STATUS_CHANGED',
        before: {'status': current},
        after: {'status': target, 'updated_at': updatedAt},
        reason: reason,
        actorUserId: actorUserId,
      );
    });
  }

  static Future<InsuranceClaimDocumentRecord> attachDocumentFromPath({
    required String claimId,
    required String documentType,
    required String sourcePath,
    String? notes,
    String? actorUserId,
    DatabaseExecutor? database,
  }) async {
    final source = File(sourcePath.trim());
    if (!await source.exists()) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'File not found.');
    }
    final root = await YallaStorageService.rootDirectory();
    final now = DateTime.now();
    final safeClaim = claimId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final relativeDirectory = p.posix.join(
      'insurance',
      now.year.toString(),
      now.month.toString().padLeft(2, '0'),
      'claims',
      safeClaim,
    );
    final directory = Directory(
      p.joinAll([root.path, ...relativeDirectory.split('/')]),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final original =
        p.basename(source.path).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fileName = '${now.microsecondsSinceEpoch}_$original';
    final stored = p.posix.join(relativeDirectory, fileName);
    final target = File(p.join(directory.path, fileName));
    await source.copy(target.path);
    try {
      return await addDocument(
        claimId: claimId,
        documentType: documentType,
        filePath: stored,
        notes: notes,
        actorUserId: actorUserId,
        database: database,
      );
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  static Future<InsuranceClaimDocumentRecord> addDocument({
    required String claimId,
    required String documentType,
    required String filePath,
    String? notes,
    String? actorUserId,
    DatabaseExecutor? database,
  }) async {
    final db = await _db(database);
    final type = documentType.trim();
    final path = filePath.trim();
    if (type.isEmpty || path.isEmpty) {
      throw ArgumentError('Document type and file path are required.');
    }
    late InsuranceClaimDocumentRecord result;
    await SyncFoundationService.writeOn<void>(db, (txn) async {
      final claim = await txn.query(
        'insurance_claims',
        columns: const ['id'],
        where: 'id=?',
        whereArgs: [claimId.trim()],
        limit: 1,
      );
      if (claim.isEmpty) throw StateError('Insurance claim not found.');
      final now = DateTime.now();
      final values = <String, Object?>{
        'id': const Uuid().v4(),
        'claim_id': claimId.trim(),
        'document_type': type,
        'file_path': path,
        'notes': _clean(notes),
        'created_at': now.toIso8601String(),
      };
      await txn.insert('insurance_claim_documents', values);
      await _audit(
        txn,
        claimId: claimId.trim(),
        action: 'CLAIM_DOCUMENT_ADDED',
        after: values,
        actorUserId: actorUserId,
      );
      result = InsuranceClaimDocumentRecord.fromRow(values);
    });
    return result;
  }

  static Future<List<InsuranceClaimRepairOption>> eligibleRepairsForClaim(
    String claimId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final cleanClaimId = claimId.trim();
    if (cleanClaimId.isEmpty) {
      throw ArgumentError('Claim is required.');
    }
    final claims = await db.query(
      'insurance_claims',
      columns: const ['vehicle_id'],
      where: 'id=?',
      whereArgs: [cleanClaimId],
      limit: 1,
    );
    if (claims.isEmpty) throw StateError('Insurance claim not found.');

    final vehicleId = int.parse(claims.single['vehicle_id'].toString());
    final vehicles = await db.query(
      'vehicles',
      columns: const ['number', 'normalized_number'],
      where: 'id=?',
      whereArgs: [vehicleId],
      limit: 1,
    );
    if (vehicles.isEmpty) throw StateError('Claim vehicle not found.');
    final vehicle = vehicles.single;
    var normalized = (vehicle['normalized_number'] ?? '').toString().trim();
    if (normalized.isEmpty) {
      normalized = VehicleTables.normalizeNumber(
        (vehicle['number'] ?? '').toString(),
      );
    }

    final registry = await db.query(
      SyncFoundationTables.registry,
      columns: const ['entity_uuid'],
      where: 'entity_type=? AND local_id=?',
      whereArgs: ['vehicle', vehicleId.toString()],
      limit: 1,
    );
    final vehicleUuid =
        registry.isEmpty ? null : _clean(registry.single['entity_uuid']);

    final repairs = await db.query(
      'repairs',
      columns: const [
        'id',
        'vehicleNumber',
        'vehicle_entity_uuid',
        'beneficiaryName',
        'vehicleStatus',
        'receivedDate',
      ],
      where: 'is_active=1',
      orderBy: 'receivedDate DESC, id DESC',
    );
    return repairs
        .where((row) {
          final repairUuid = _clean(row['vehicle_entity_uuid']);
          if (repairUuid != null) {
            return vehicleUuid != null && repairUuid == vehicleUuid;
          }
          if (normalized.isEmpty) return false;
          return VehicleTables.normalizeNumber(
                (row['vehicleNumber'] ?? '').toString(),
              ) ==
              normalized;
        })
        .map(InsuranceClaimRepairOption.fromRow)
        .toList(growable: false);
  }

  static Future<void> linkRepair({
    required String claimId,
    required String repairId,
    String? reason,
    String? actorUserId,
    DatabaseExecutor? database,
  }) async {
    final db = await _db(database);
    final cleanClaimId = claimId.trim();
    final cleanRepairId = repairId.trim();
    if (cleanClaimId.isEmpty || cleanRepairId.isEmpty) {
      throw ArgumentError('Claim and repair are required.');
    }
    await SyncFoundationService.writeOn<void>(db, (txn) async {
      final candidates = await eligibleRepairsForClaim(
        cleanClaimId,
        executor: txn,
      );
      if (!candidates.any((row) => row.repairId == cleanRepairId)) {
        throw StateError('Repair does not match the claim vehicle.');
      }
      await _audit(
        txn,
        claimId: cleanClaimId,
        action: 'CLAIM_REPAIR_LINKED',
        reason: reason,
        actorUserId: actorUserId,
        metadata: {
          'repair_id': cleanRepairId,
          'workshop_ref': cleanRepairId,
        },
      );
    });
  }

  static Future<void> linkWorkshop({
    required String claimId,
    required String workshopRef,
    String? reason,
    String? actorUserId,
    DatabaseExecutor? database,
  }) async {
    final db = await _db(database);
    final workshop = workshopRef.trim();
    if (workshop.isEmpty) {
      throw ArgumentError('Workshop reference is required.');
    }
    await SyncFoundationService.writeOn<void>(db, (txn) async {
      final claim = await txn.query(
        'insurance_claims',
        columns: const ['id'],
        where: 'id=?',
        whereArgs: [claimId.trim()],
        limit: 1,
      );
      if (claim.isEmpty) throw StateError('Insurance claim not found.');
      await _audit(
        txn,
        claimId: claimId.trim(),
        action: 'CLAIM_WORKSHOP_LINKED',
        reason: reason,
        actorUserId: actorUserId,
        metadata: {'workshop_ref': workshop},
      );
    });
  }

  static Future<List<InsuranceClaimRecord>> listClaims({
    String? status,
    String? policyId,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final where = <String>[];
    final args = <Object?>[];
    final cleanStatus = _clean(status)?.toUpperCase();
    if (cleanStatus != null) {
      if (!statuses.contains(cleanStatus)) {
        throw ArgumentError.value(
            status, 'status', 'Unsupported claim status.');
      }
      where.add('status=?');
      args.add(cleanStatus);
    }
    final cleanPolicy = _clean(policyId);
    if (cleanPolicy != null) {
      where.add('policy_id=?');
      args.add(cleanPolicy);
    }
    final rows = await db.query(
      'insurance_claims',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'reported_at DESC, id DESC',
    );
    return rows.map(InsuranceClaimRecord.fromRow).toList(growable: false);
  }

  static Future<List<InsuranceClaimDocumentRecord>> listDocuments(
    String claimId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'insurance_claim_documents',
      where: 'claim_id=?',
      whereArgs: [claimId.trim()],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows
        .map(InsuranceClaimDocumentRecord.fromRow)
        .toList(growable: false);
  }

  static Future<List<InsuranceClaimTimelineEvent>> timeline(
    String claimId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'app_audit_events',
      where: 'entity_type=? AND entity_id=?',
      whereArgs: [entityType, claimId.trim()],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows
        .map(InsuranceClaimTimelineEvent.fromRow)
        .toList(growable: false);
  }

  static Future<String?> repairId(
    String claimId, {
    DatabaseExecutor? executor,
  }) async {
    final events = await timeline(claimId, executor: executor);
    for (final event in events.reversed) {
      if (event.action != 'CLAIM_REPAIR_LINKED') continue;
      final value = _clean(event.metadata?['repair_id']);
      if (value != null) return value;
    }
    return null;
  }

  static Future<String?> workshopRef(
    String claimId, {
    DatabaseExecutor? executor,
  }) async {
    final events = await timeline(claimId, executor: executor);
    for (final event in events.reversed) {
      final value = _clean(event.metadata?['workshop_ref']);
      if (value != null) return value;
    }
    return null;
  }
}
