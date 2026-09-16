import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_contract_v3.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

class PurchaseSyncService {
  PurchaseSyncService._();

  static Future<void> applyInbound(
    DatabaseExecutor executor,
    InboundSyncChange change,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Purchase inbound sync requires a transaction.');
    }
    switch (change.entityType) {
      case 'purchase_invoice':
        await _applyInvoice(executor, change);
        return;
      case 'purchase_invoice_line':
        await _applyLine(executor, change);
        return;
      case 'purchase_payment':
        await _applyPayment(executor, change);
        return;
      default:
        throw StateError(
            'SYNC_PURCHASE_UNSUPPORTED_ENTITY:${change.entityType}');
    }
  }

  static Future<Map<String, Object?>?> _identity(
    DatabaseExecutor db,
    String entityType,
    String entityUuid,
  ) async {
    final rows = await db.query(
      SyncFoundationTables.registry,
      where: 'entity_type=? AND entity_uuid=?',
      whereArgs: [entityType, entityUuid],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  static void _requireNextRevision(
    Map<String, Object?>? identity,
    int revision,
  ) {
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

  static bool _restoreIntent(Map<String, Object?> payload) =>
      payload[SyncContractV3.tombstoneRestoreMarker] == true;

  static Future<int> _supplierIdForPartyUuid(
    DatabaseExecutor db,
    String partyUuid,
  ) async {
    final party = await _identity(db, 'party', partyUuid);
    if (party == null) throw StateError('SYNC_PURCHASE_SUPPLIER_PARTY_MISSING');
    final roles = await db.query(
      'party_roles',
      columns: const ['legacy_id'],
      where: 'party_id=? AND role=?',
      whereArgs: [party['local_id'].toString(), 'SUPPLIER'],
      limit: 1,
    );
    if (roles.isEmpty) {
      throw StateError('SYNC_PURCHASE_SUPPLIER_ROLE_MISSING');
    }
    final raw = roles.single['legacy_id'];
    final id = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (id == null || id <= 0) {
      throw StateError('SYNC_PURCHASE_SUPPLIER_ID_INVALID');
    }
    return id;
  }

  static Future<String> _invoiceIdForUuid(
    DatabaseExecutor db,
    String invoiceUuid,
  ) async {
    final identity = await _identity(db, 'purchase_invoice', invoiceUuid);
    if (identity == null) throw StateError('SYNC_PURCHASE_PARENT_MISSING');
    return identity['local_id']!.toString();
  }

  static Future<void> _applyInvoice(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity =
        await _identity(txn, 'purchase_invoice', change.entityUuid);
    _requireNextRevision(identity, change.revision);
    final localId = identity?['local_id']?.toString() ?? change.entityUuid;

    if (change.operation == 'DELETE') {
      if (identity == null) throw StateError('SYNC_PURCHASE_DELETE_MISSING');
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'purchase_invoice',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.update(
            'purchase_invoices',
            {
              'is_active': 0,
              'updated_at': change.occurredAt.toUtc().toIso8601String(),
            },
            where: 'id=? AND COALESCE(is_active,1)=1',
            whereArgs: [localId],
          );
          if (changed != 1) throw StateError('SYNC_PURCHASE_DELETE_MISSING');
        },
      );
      return;
    }

    final supplierPartyUuid = _text(payload['supplier_party_uuid']);
    if (supplierPartyUuid == null) {
      throw StateError('SYNC_PURCHASE_SUPPLIER_PARTY_MISSING');
    }
    final supplierId = await _supplierIdForPartyUuid(txn, supplierPartyUuid);
    final restore = _restoreIntent(payload);
    if (identity?['is_voided'] == 1 && !restore) {
      throw StateError('SYNC_PURCHASE_RESTORE_REQUIRED');
    }
    if (identity?['is_voided'] != 1 && restore) {
      throw StateError('SYNC_PURCHASE_RESTORE_WITHOUT_TOMBSTONE');
    }
    final now = change.occurredAt.toUtc().toIso8601String();
    const allowed = <String>{
      'invoice_number',
      'purchase_type',
      'subtotal',
      'vat',
      'total',
      'amount_total',
      'date',
      'note',
      'method',
      'created_at',
      'updated_at',
    };
    final values = <String, Object?>{
      for (final entry in payload.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
      'supplier_id': supplierId,
      'supplier_party_uuid': supplierPartyUuid,
      'is_active': 1,
      'updated_at': now,
    };
    final dateText = _text(values['date']);
    if (dateText == null || DateTime.tryParse(dateText) == null) {
      throw const FormatException('Purchase date is invalid.');
    }
    final total = (values['amount_total'] as num?)?.toDouble() ??
        (values['total'] as num?)?.toDouble() ??
        double.tryParse('${values['amount_total'] ?? values['total']}');
    if (total == null || total <= 0) {
      throw const FormatException('Purchase total must be positive.');
    }
    values['amount_total'] = total;
    values['total'] ??= total;
    values['subtotal'] ??= total;

    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'purchase_invoice',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn.query(
          'purchase_invoices',
          where: 'id=?',
          whereArgs: [localId],
          limit: 1,
        );
        if (rows.isEmpty) {
          final method = (_text(values['method']) ?? '').toLowerCase();
          final paid = method == 'cash' || method == 'bank';
          values['created_at'] ??= now;
          values['paid_total'] = paid ? total : 0.0;
          values['remaining'] = paid ? 0.0 : total;
          values['status'] = paid ? 'PAID' : 'UNPAID';
          await txn.insert(
            'purchase_invoices',
            {'id': localId, ...values},
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          await txn.update(
            'purchase_invoices',
            values,
            where: 'id=?',
            whereArgs: [localId],
          );
        }
      },
    );
  }

  static Future<void> _applyLine(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final parentUuid = _text(payload['purchase_invoice_entity_uuid']);
    if (parentUuid == null) {
      throw StateError('SYNC_PURCHASE_PARENT_UUID_MISSING');
    }
    final invoiceId = await _invoiceIdForUuid(txn, parentUuid);
    final identity =
        await _identity(txn, 'purchase_invoice_line', change.entityUuid);
    _requireNextRevision(identity, change.revision);
    final localId = identity?['local_id']?.toString() ?? change.entityUuid;
    final restore = _restoreIntent(payload);

    if (change.operation == 'DELETE') {
      if (identity == null) {
        throw StateError('SYNC_PURCHASE_LINE_DELETE_MISSING');
      }
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'purchase_invoice_line',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.delete(
            'purchase_invoice_lines',
            where: 'id=?',
            whereArgs: [localId],
          );
          if (changed != 1) {
            throw StateError('SYNC_PURCHASE_LINE_DELETE_MISSING');
          }
        },
      );
      return;
    }
    if (identity?['is_voided'] == 1 && !restore) {
      throw StateError('SYNC_PURCHASE_LINE_RESTORE_REQUIRED');
    }
    if (identity?['is_voided'] != 1 && restore) {
      throw StateError('SYNC_PURCHASE_LINE_RESTORE_WITHOUT_TOMBSTONE');
    }

    final name = _text(payload['item_name'] ?? payload['item']);
    final qty = (payload['qty'] as num?)?.toDouble() ??
        double.tryParse('${payload['qty']}');
    final price = (payload['price'] as num?)?.toDouble() ??
        (payload['unit_price'] as num?)?.toDouble() ??
        double.tryParse('${payload['price'] ?? payload['unit_price']}');
    if (name == null || qty == null || qty <= 0 || price == null || price < 0) {
      throw const FormatException('Purchase line payload is invalid.');
    }
    final total = double.parse((qty * price).toStringAsFixed(2));
    final values = <String, Object?>{
      'invoice_id': invoiceId,
      'item': name,
      'item_name': name,
      'qty': qty,
      'unit_price': price,
      'price': price,
      'total': total,
      'category': _text(payload['category']),
      'note': _text(payload['note']),
    };
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'purchase_invoice_line',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn.query(
          'purchase_invoice_lines',
          where: 'id=?',
          whereArgs: [localId],
          limit: 1,
        );
        if (rows.isEmpty) {
          await txn.insert(
            'purchase_invoice_lines',
            {'id': localId, ...values},
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          await txn.update(
            'purchase_invoice_lines',
            values,
            where: 'id=?',
            whereArgs: [localId],
          );
        }
      },
    );
  }

  static Future<void> _applyPayment(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_PURCHASE_PAYMENT_DELETE_DENIED');
    }
    if (_restoreIntent(payload)) {
      throw StateError('SYNC_PURCHASE_PAYMENT_RESTORE_DENIED');
    }
    final parentUuid = _text(payload['purchase_invoice_entity_uuid']);
    if (parentUuid == null) {
      throw StateError('SYNC_PURCHASE_PARENT_UUID_MISSING');
    }
    final invoiceId = await _invoiceIdForUuid(txn, parentUuid);
    final identity =
        await _identity(txn, 'purchase_payment', change.entityUuid);
    _requireNextRevision(identity, change.revision);
    final localId = identity?['local_id']?.toString() ?? change.entityUuid;

    final amount = (payload['amount'] as num?)?.toDouble() ??
        double.tryParse('${payload['amount']}');
    final dateText = _text(payload['date']);
    if (amount == null ||
        amount <= 0 ||
        dateText == null ||
        DateTime.tryParse(dateText) == null) {
      throw const FormatException('Purchase payment payload is invalid.');
    }
    final now = change.occurredAt.toUtc().toIso8601String();
    final values = <String, Object?>{
      'invoice_id': invoiceId,
      'purchase_invoice_entity_uuid': parentUuid,
      'amount': amount,
      'date': dateText,
      'method': _text(payload['method']),
      'note': _text(payload['note']),
      'created_at': _text(payload['created_at']) ?? now,
      'updated_at': now,
    };
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'purchase_payment',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn.query(
          'purchase_payments',
          where: 'id=?',
          whereArgs: [localId],
          limit: 1,
        );
        if (rows.isEmpty) {
          await txn.insert(
            'purchase_payments',
            {'id': localId, ...values},
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          if (rows.single['gl_entry_id'] != null) {
            throw StateError('SYNC_PURCHASE_PAYMENT_IMMUTABLE');
          }
          await txn.update(
            'purchase_payments',
            values,
            where: 'id=?',
            whereArgs: [localId],
          );
        }
      },
    );
  }
}
