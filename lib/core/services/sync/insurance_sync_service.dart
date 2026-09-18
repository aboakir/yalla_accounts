import 'package:sqflite/sqflite.dart';

import '../db/tables/sync_foundation_tables.dart';
import 'sync_foundation_service.dart';
import 'unified_sync_queue_service.dart';

class InsuranceSyncService {
  InsuranceSyncService._();

  static const handledTypes = <String>{
    'insurance_policy',
    'insurance_policy_cheque',
    'insurance_policy_installment',
    'insurance_policy_promissory',
  };

  static Future<void> applyInbound(
    DatabaseExecutor executor,
    InboundSyncChange change,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Insurance inbound sync requires a transaction.');
    }
    if (!handledTypes.contains(change.entityType)) {
      throw StateError('SYNC_INSURANCE_UNSUPPORTED:${change.entityType}');
    }
    if (change.entityType == 'insurance_policy') {
      return _applyPolicy(executor, change);
    }
    return _applyChild(executor, change);
  }

  static Future<Map<String, Object?>?> _identity(
    DatabaseExecutor db,
    String type,
    String uuid,
  ) async {
    final rows = await db.query(
      SyncFoundationTables.registry,
      where: 'entity_type=? AND entity_uuid=?',
      whereArgs: [type, uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  static void _requireRevision(Map<String, Object?>? identity, int revision) {
    if (identity == null) {
      if (revision != 1) throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
      return;
    }
    final local = (identity['revision'] as num?)?.toInt() ?? -1;
    if (local + 1 != revision) {
      throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
    }
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, Object?> _pick(
    Map<String, Object?> payload,
    Set<String> allowed,
  ) =>
      <String, Object?>{
        for (final entry in payload.entries)
          if (allowed.contains(entry.key)) entry.key: entry.value,
      };

  static Future<String> _policyId(
    DatabaseExecutor db,
    Object? rawUuid,
  ) async {
    final uuid = _text(rawUuid);
    if (uuid == null) {
      throw StateError('SYNC_INSURANCE_POLICY_REFERENCE_MISSING');
    }
    final identity = await _identity(db, 'insurance_policy', uuid);
    if (identity == null) {
      throw StateError('SYNC_INSURANCE_POLICY_REFERENCE_MISSING');
    }
    return identity['local_id']!.toString();
  }

  static Future<void> _applyPolicy(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity =
        await _identity(txn, 'insurance_policy', change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = identity?['local_id']?.toString() ?? change.entityId;
    if (change.operation == 'DELETE') {
      if (identity == null) throw StateError('SYNC_INSURANCE_DELETE_MISSING');
      for (final table in const [
        'insurance_policy_cheques',
        'insurance_policy_installments',
        'insurance_policy_promissories',
      ]) {
        final rows = await txn.query(table,
            where: 'policy_id=?', whereArgs: [id], limit: 1);
        if (rows.isNotEmpty) throw StateError('SYNC_INSURANCE_CHILDREN_REMAIN');
      }
      return SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'insurance_policy',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn
              .delete('insurance_policies', where: 'id=?', whereArgs: [id]);
          if (changed != 1) throw StateError('SYNC_INSURANCE_DELETE_MISSING');
        },
      );
    }
    const allowed = <String>{
      'created_at',
      'updated_at',
      'vehicle_plate',
      'vehicle_make',
      'vehicle_model_year',
      'engine_cc',
      'insured_name',
      'insured_phone',
      'company_name',
      'start_date',
      'end_date',
      'is_vip',
      'buy_price',
      'sell_price',
      'payment_type',
      'cash_amount',
      'vehicle_images',
      'notes',
    };
    final values = _pick(payload, allowed)
      ..['updated_at'] =
          _text(payload['updated_at']) ?? change.occurredAt.toIso8601String();
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'insurance_policy',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn
            .query('insurance_policies', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          values['created_at'] ??= change.occurredAt.toIso8601String();
          await txn.insert('insurance_policies', {'id': id, ...values});
        } else {
          await txn.update('insurance_policies', values,
              where: 'id=?', whereArgs: [id]);
        }
      },
    );
  }

  static Future<void> _applyChild(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, change.entityType, change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = identity?['local_id']?.toString() ?? change.entityId;
    final table = switch (change.entityType) {
      'insurance_policy_cheque' => 'insurance_policy_cheques',
      'insurance_policy_installment' => 'insurance_policy_installments',
      'insurance_policy_promissory' => 'insurance_policy_promissories',
      _ => throw StateError('SYNC_INSURANCE_UNSUPPORTED:${change.entityType}'),
    };
    if (change.operation == 'DELETE') {
      if (identity == null) {
        throw StateError('SYNC_INSURANCE_CHILD_DELETE_MISSING');
      }
      return SyncFoundationService.withRemoteMutation(
        txn,
        entityType: change.entityType,
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed =
              await txn.delete(table, where: 'id=?', whereArgs: [id]);
          if (changed != 1) {
            throw StateError('SYNC_INSURANCE_CHILD_DELETE_MISSING');
          }
        },
      );
    }
    final policy = await _policyId(txn, payload['policy_entity_uuid']);
    final allowed = change.entityType == 'insurance_policy_cheque'
        ? const <String>{
            'amount',
            'due_date',
            'bank_name',
            'drawer_name',
            'cheque_number',
            'created_at',
            'updated_at',
          }
        : change.entityType == 'insurance_policy_installment'
            ? const <String>{
                'amount',
                'due_date',
                'note',
                'created_at',
                'updated_at'
              }
            : const <String>{'amount', 'due_date', 'created_at', 'updated_at'};
    final values = _pick(payload, allowed)
      ..['policy_id'] = policy
      ..['updated_at'] =
          _text(payload['updated_at']) ?? change.occurredAt.toIso8601String();
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: change.entityType,
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn.query(table, where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          values['created_at'] ??= change.occurredAt.toIso8601String();
          await txn.insert(table, {'id': id, ...values});
        } else {
          await txn.update(table, values, where: 'id=?', whereArgs: [id]);
        }
      },
    );
  }
}
