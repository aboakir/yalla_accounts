import 'package:sqflite/sqflite.dart';

import '../accounting_source_policy.dart';
import '../db/tables/accounting_integrity_tables.dart';
import '../db/tables/accounting_tables.dart';
import '../db/tables/sync_foundation_tables.dart';
import 'sync_foundation_service.dart';
import 'unified_sync_queue_service.dart';

class FinancialHrSyncService {
  FinancialHrSyncService._();

  static const handledTypes = <String>{
    'employee',
    'invoice',
    'payment',
    'receipt',
    'receipt_allocation',
    'customer_credit_allocation',
    'voucher',
    'cheque',
    'employee_advance',
    'payroll_run',
    'payroll_payment',
    'invoice_settlement',
    'monthly_expense',
    'gl_entry',
    'gl_line',
    'accounting_audit_event',
  };
  static Future<void> applyInbound(
    DatabaseExecutor executor,
    InboundSyncChange change,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Financial inbound sync requires a transaction.');
    }
    if (!handledTypes.contains(change.entityType)) {
      throw StateError(
          'SYNC_FINANCIAL_UNSUPPORTED_ENTITY:${change.entityType}');
    }
    switch (change.entityType) {
      case 'employee':
        return _applyEmployee(executor, change);
      case 'invoice':
        return _applyInvoice(executor, change);
      case 'payment':
        return _applyPayment(executor, change);
      case 'receipt':
        return _applyReceipt(executor, change);
      case 'receipt_allocation':
        return _applyReceiptAllocation(executor, change);
      case 'customer_credit_allocation':
        return _applyCreditAllocation(executor, change);
      case 'voucher':
        return _applyVoucher(executor, change);
      case 'cheque':
        return _applyCheque(executor, change);
      case 'employee_advance':
        return _applyAdvance(executor, change);
      case 'payroll_run':
        return _applyPayrollRun(executor, change);
      case 'payroll_payment':
        return _applyPayrollPayment(executor, change);
      case 'invoice_settlement':
        return _applySettlement(executor, change);
      case 'monthly_expense':
        return _applyMonthlyExpense(executor, change);
      case 'gl_entry':
        return _applyGlEntry(executor, change);
      case 'gl_line':
        return _applyGlLine(executor, change);
      case 'accounting_audit_event':
        return _applyAudit(executor, change);
    }
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

  static void _requireRevision(
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

  static int? _int(Object? value) {
    if (value == null) return null;
    return value is num ? value.toInt() : int.tryParse(value.toString());
  }

  static double _money(Object? value, String field) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('Invalid financial value: $field');
    }
    return parsed;
  }

  static Future<String> _localIdByUuid(
    DatabaseExecutor db,
    String type,
    Object? rawUuid, {
    bool required = true,
  }) async {
    final uuid = _text(rawUuid);
    if (uuid == null) {
      if (required) throw StateError('SYNC_REFERENCE_MISSING:$type');
      return '';
    }
    final identity = await _identity(db, type, uuid);
    if (identity == null) throw StateError('SYNC_REFERENCE_MISSING:$type');
    return identity['local_id']!.toString();
  }

  static Future<int?> _localIntByUuid(
    DatabaseExecutor db,
    String type,
    Object? rawUuid,
  ) async {
    final uuid = _text(rawUuid);
    if (uuid == null) return null;
    final local = await _localIdByUuid(db, type, uuid);
    final value = int.tryParse(local);
    if (value == null) throw StateError('SYNC_REFERENCE_INVALID:$type');
    return value;
  }

  static Future<int?> _partyLegacyId(
    DatabaseExecutor db,
    String role,
    Object? rawUuid,
  ) async {
    final uuid = _text(rawUuid);
    if (uuid == null) return null;
    final party = await _identity(db, 'party', uuid);
    if (party == null) throw StateError('SYNC_PARTY_REFERENCE_MISSING');
    final rows = await db.query(
      'party_roles',
      columns: const ['legacy_id'],
      where: 'party_id=? AND role=?',
      whereArgs: [party['local_id'].toString(), role],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('SYNC_PARTY_ROLE_MISSING:$role');
    final value = int.tryParse(rows.single['legacy_id'].toString());
    if (value == null) throw StateError('SYNC_PARTY_LEGACY_ID_INVALID');
    return value;
  }

  static Future<String?> _partyLocalId(
    DatabaseExecutor db,
    String? partyType,
    Object? rawUuid,
    Object? localHint,
  ) async {
    final type = (partyType ?? '').trim().toUpperCase();
    if (_text(rawUuid) == null) return _text(localHint);
    if (type == 'EMPLOYEE') {
      return _localIdByUuid(db, 'employee', rawUuid);
    }
    if (type == 'CUSTOMER' || type == 'CLIENT') {
      return '${await _partyLegacyId(db, 'CUSTOMER', rawUuid)}';
    }
    if (type == 'SUPPLIER') {
      return '${await _partyLegacyId(db, 'SUPPLIER', rawUuid)}';
    }
    return _text(localHint);
  }

  static Future<int> _accountId(
    DatabaseExecutor db,
    Map<String, Object?> payload,
  ) async {
    final code = _text(payload['account_code']);
    if (code == null) throw StateError('SYNC_GL_ACCOUNT_CODE_MISSING');
    final rows = await db.query(
      'accounts',
      columns: const ['id', 'name', 'type', 'normal_balance'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isNotEmpty) return (rows.single['id'] as num).toInt();

    final type = (_text(payload['account_type']) ?? '').toUpperCase();
    if (!const {'ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE'}
        .contains(type)) {
      throw StateError('SYNC_GL_ACCOUNT_TYPE_INVALID');
    }
    final normal =
        (_text(payload['account_normal_balance']) ?? '').toUpperCase();
    if (!const {'DEBIT', 'CREDIT'}.contains(normal)) {
      throw StateError('SYNC_GL_ACCOUNT_NORMAL_INVALID');
    }
    return db.insert('accounts', {
      'code': code,
      'name': _text(payload['account_name']) ?? code,
      'type': type,
      'normal_balance': normal,
      'report_class': _text(payload['account_report_class']),
      'is_postable': _int(payload['account_is_postable']) ?? 1,
      'is_system': _int(payload['account_is_system']) ?? 0,
      'is_active': _int(payload['account_is_active']) ?? 1,
      'is_legacy': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static String _newTextId(
    InboundSyncChange change,
    Map<String, Object?>? identity,
  ) {
    if (identity != null) return identity['local_id']!.toString();
    final candidate = change.entityId.trim();
    if (candidate.isEmpty) throw StateError('SYNC_ENTITY_ID_MISSING');
    return candidate;
  }

  static Map<String, Object?> _pick(
    Map<String, Object?> payload,
    Set<String> allowed,
  ) =>
      <String, Object?>{
        for (final entry in payload.entries)
          if (allowed.contains(entry.key)) entry.key: entry.value,
      };
  static Future<void> _applyEmployee(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'employee', change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = _newTextId(change, identity);
    if (change.operation == 'DELETE') {
      if (identity == null) throw StateError('SYNC_EMPLOYEE_DELETE_MISSING');
      return SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'employee',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () async {
          final changed = await txn.update(
            'employees',
            {
              'status': 'inactive',
              'updated_at': change.occurredAt.toIso8601String()
            },
            where: 'id=?',
            whereArgs: [id],
          );
          if (changed != 1) throw StateError('SYNC_EMPLOYEE_DELETE_MISSING');
        },
      );
    }
    const allowed = <String>{
      'full_name',
      'employee_code',
      'job_title',
      'hire_date',
      'phone',
      'email',
      'address',
      'status',
      'base_salary',
      'allowances',
      'deductions',
      'advances',
      'total_work_days',
      'total_hours',
      'absences',
      'late_days',
      'notes',
      'photo_url',
      'contract_url',
      'last_salary_paid_date',
      'created_at',
      'updated_at',
      'payment_method',
      'work_days_per_week',
      'hours_per_day',
    };
    final values = _pick(payload, allowed);
    if ((_text(values['full_name']) ?? '').isEmpty) {
      throw const FormatException('Employee full_name is required.');
    }
    values['updated_at'] ??= change.occurredAt.toIso8601String();
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'employee',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows =
            await txn.query('employees', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          await txn.insert('employees', {'id': id, ...values});
        } else {
          await txn.update('employees', values, where: 'id=?', whereArgs: [id]);
        }
      },
    );
  }

  static Future<void> _applyInvoice(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'invoice', change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = _newTextId(change, identity);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_POSTED_FINANCIAL_DELETE_DENIED');
    }
    final clientId = await _partyLegacyId(
      txn,
      'CUSTOMER',
      payload['customer_party_uuid'],
    );
    final repairUuid = _text(payload['repair_entity_uuid']);
    final repairId = repairUuid == null
        ? null
        : await _localIdByUuid(txn, 'repair', repairUuid);
    const material = <String>{
      'date',
      'subtotal',
      'vat',
      'vat_amount',
      'total',
      'client_id',
      'repair_id',
    };
    const allowed = <String>{
      'date',
      'subtotal',
      'vat',
      'vat_amount',
      'total',
      'paid',
      'status',
      'notes',
      'method',
      'note',
      'post_to_gl',
      'created_at',
      'updated_at',
    };
    final values = _pick(payload, allowed)
      ..['client_id'] = clientId
      ..['repair_id'] = repairId
      ..['updated_at'] = change.occurredAt.toIso8601String();
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'invoice',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final current =
            await txn.query('invoices', where: 'id=?', whereArgs: [id]);
        if (current.isEmpty) {
          values['created_at'] ??= change.occurredAt.toIso8601String();
          await txn.insert('invoices', {'id': id, ...values});
          return;
        }
        final posted = await txn.rawQuery(
          "SELECT 1 FROM gl_entries WHERE UPPER(source)='INVOICE' AND source_id=? LIMIT 1",
          [id],
        );
        if (posted.isNotEmpty) {
          for (final key in material) {
            if (values.containsKey(key) &&
                '${current.single[key]}' != '${values[key]}') {
              throw StateError('SYNC_POSTED_INVOICE_MUTATION_DENIED');
            }
          }
          values.removeWhere((key, _) => material.contains(key));
        }
        await txn.update('invoices', values, where: 'id=?', whereArgs: [id]);
      },
    );
  }

  static Future<void> _applyPayment(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'payment', change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = _newTextId(change, identity);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_POSTED_FINANCIAL_DELETE_DENIED');
    }
    final clientId = await _partyLegacyId(
      txn,
      'CUSTOMER',
      payload['customer_party_uuid'],
    );
    Future<String?> ref(String type, String key) async {
      final uuid = _text(payload[key]);
      return uuid == null ? null : _localIdByUuid(txn, type, uuid);
    }

    final receiptNo =
        await _localIntByUuid(txn, 'receipt', payload['receipt_entity_uuid']);
    final glId =
        await _localIntByUuid(txn, 'gl_entry', payload['gl_entry_entity_uuid']);
    final chequeId =
        await _localIntByUuid(txn, 'cheque', payload['cheque_entity_uuid']);
    const allowed = <String>{
      'reversal_of_payment_id',
      'amount',
      'date',
      'method',
      'accountName',
      'status',
      'notes',
      'attachments',
      'isIncome',
    };
    final values = _pick(payload, allowed)
      ..['receipt_number'] = receiptNo
      ..['client_id'] = clientId
      ..['repair_id'] = await ref('repair', 'repair_entity_uuid')
      ..['invoice_id'] = await ref('invoice', 'invoice_entity_uuid')
      ..['relatedRepairId'] = await ref('repair', 'related_repair_entity_uuid')
      ..['gl_entry_id'] = glId
      ..['cheque_id'] = chequeId;
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'payment',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final current =
            await txn.query('payments', where: 'id=?', whereArgs: [id]);
        if (current.isEmpty) {
          await txn.insert('payments', {'id': id, ...values});
        } else {
          const mutable = <String>{
            'status',
            'notes',
            'attachments',
            'gl_entry_id',
            'cheque_id'
          };
          final update = <String, Object?>{
            for (final e in values.entries)
              if (mutable.contains(e.key)) e.key: e.value,
          };
          await txn.update('payments', update, where: 'id=?', whereArgs: [id]);
        }
      },
    );
  }

  static Future<void> _applyReceipt(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'receipt', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_POSTED_FINANCIAL_DELETE_DENIED');
    }
    final clientId = await _partyLegacyId(
      txn,
      'CUSTOMER',
      payload['customer_party_uuid'],
    );
    final reversal = await _localIntByUuid(
      txn,
      'receipt',
      payload['reversal_receipt_entity_uuid'],
    );
    const allowed = <String>{
      'date',
      'method',
      'total_amount',
      'allocated_amount',
      'credit_amount',
      'status',
      'notes',
      'created_at',
    };
    final values = _pick(payload, allowed)
      ..['client_id'] = clientId
      ..['reversal_of_receipt_number'] = reversal;
    if (identity == null) {
      final preferred = int.tryParse(change.entityId);
      if (preferred == null || preferred <= 0) {
        throw StateError('SYNC_RECEIPT_NUMBER_INVALID');
      }
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'receipt',
        entityUuid: change.entityUuid,
        revision: change.revision,
        action: () => txn.insert(
          'receipt_headers',
          {'receipt_number': preferred, ...values},
          conflictAlgorithm: ConflictAlgorithm.abort,
        ),
      );
      return;
    }
    final local = int.parse(identity['local_id'].toString());
    final current = (await txn.query(
      'receipt_headers',
      where: 'receipt_number=?',
      whereArgs: [local],
      limit: 1,
    ))
        .single;
    for (final key in const [
      'client_id',
      'date',
      'method',
      'total_amount',
      'allocated_amount',
      'credit_amount',
      'reversal_of_receipt_number',
      'created_at'
    ]) {
      if (values.containsKey(key) && '${current[key]}' != '${values[key]}') {
        throw StateError('SYNC_RECEIPT_IMMUTABLE_MISMATCH');
      }
    }
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'receipt',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () => txn.update(
        'receipt_headers',
        {'status': values['status'], 'notes': values['notes']},
        where: 'receipt_number=?',
        whereArgs: [local],
      ),
    );
  }

  static Future<void> _applyReceiptAllocation(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity =
        await _identity(txn, 'receipt_allocation', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (identity != null ||
        change.operation != 'UPSERT' ||
        change.revision != 1) {
      throw StateError('SYNC_IMMUTABLE_ALLOCATION_MUTATION_DENIED');
    }
    final receipt =
        await _localIntByUuid(txn, 'receipt', payload['receipt_entity_uuid']);
    final payment =
        await _localIdByUuid(txn, 'payment', payload['payment_entity_uuid']);
    final repairUuid = _text(payload['repair_entity_uuid']);
    final repair = repairUuid == null
        ? null
        : await _localIdByUuid(txn, 'repair', repairUuid);
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'receipt_allocation',
      entityUuid: change.entityUuid,
      revision: 1,
      action: () => txn.insert('receipt_allocations', {
        'receipt_number': receipt,
        'payment_id': payment,
        'repair_id': repair,
        'amount': _money(payload['amount'], 'amount'),
        'allocation_type': _text(payload['allocation_type']) ?? 'repair',
        'created_at':
            _text(payload['created_at']) ?? change.occurredAt.toIso8601String(),
      }),
    );
  }

  static Future<void> _applyCreditAllocation(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity =
        await _identity(txn, 'customer_credit_allocation', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (identity != null ||
        change.operation != 'UPSERT' ||
        change.revision != 1) {
      throw StateError('SYNC_IMMUTABLE_ALLOCATION_MUTATION_DENIED');
    }
    final id = _newTextId(change, identity);
    final client =
        await _partyLegacyId(txn, 'CUSTOMER', payload['customer_party_uuid']);
    final repair =
        await _localIdByUuid(txn, 'repair', payload['repair_entity_uuid']);
    final payment =
        await _localIdByUuid(txn, 'payment', payload['payment_entity_uuid']);
    final gl =
        await _localIntByUuid(txn, 'gl_entry', payload['gl_entry_entity_uuid']);
    if (gl == null) throw StateError('SYNC_REFERENCE_MISSING:gl_entry');
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'customer_credit_allocation',
      entityUuid: change.entityUuid,
      revision: 1,
      action: () => txn.insert('customer_credit_allocations', {
        'id': id,
        'client_id': client,
        'repair_id': repair,
        'payment_id': payment,
        'amount': _money(payload['amount'], 'amount'),
        'gl_entry_id': gl,
        'date': _text(payload['date']) ?? change.occurredAt.toIso8601String(),
        'notes': _text(payload['notes']),
        'created_at':
            _text(payload['created_at']) ?? change.occurredAt.toIso8601String(),
      }),
    );
  }

  static Future<void> _applyVoucher(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'voucher', change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = _newTextId(change, identity);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_POSTED_FINANCIAL_DELETE_DENIED');
    }
    final partyType = _text(payload['party_type']);
    final partyId = await _partyLocalId(
      txn,
      partyType,
      payload['party_entity_uuid'],
      payload['party_local_hint'],
    );
    final gl =
        await _localIntByUuid(txn, 'gl_entry', payload['gl_entry_entity_uuid']);
    final reversal = await _localIntByUuid(
      txn,
      'gl_entry',
      payload['reversal_gl_entry_entity_uuid'],
    );
    final cheque =
        await _localIntByUuid(txn, 'cheque', payload['cheque_entity_uuid']);
    const allowed = <String>{
      'voucher_type',
      'voucher_number',
      'voucher_code',
      'party_type',
      'amount',
      'currency',
      'date',
      'method',
      'reference',
      'source',
      'source_id',
      'is_posted',
      'status',
      'reversed_at',
      'reversal_reason',
      'posted_by',
      'posted_at',
      'notes',
      'attachments',
      'created_at',
      'updated_at',
    };
    final values = _pick(payload, allowed)
      ..['party_id'] = partyId
      ..['gl_entry_id'] = gl
      ..['reversal_gl_entry_id'] = reversal
      ..['cheque_id'] = cheque?.toString();
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'voucher',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows =
            await txn.query('vouchers', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          await txn.insert('vouchers', {'id': id, ...values});
          return;
        }
        final current = rows.single;
        final posted =
            _int(current['is_posted']) == 1 || current['gl_entry_id'] != null;
        if (!posted) {
          await txn.update('vouchers', values, where: 'id=?', whereArgs: [id]);
          return;
        }
        const mutable = <String>{
          'gl_entry_id',
          'is_posted',
          'status',
          'reversal_gl_entry_id',
          'reversed_at',
          'reversal_reason',
          'posted_by',
          'posted_at',
          'updated_at',
        };
        final update = <String, Object?>{
          for (final e in values.entries)
            if (mutable.contains(e.key)) e.key: e.value,
        };
        await txn.update('vouchers', update, where: 'id=?', whereArgs: [id]);
      },
    );
  }

  static Future<void> _applyCheque(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'cheque', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_POSTED_FINANCIAL_DELETE_DENIED');
    }
    final client =
        await _partyLegacyId(txn, 'CUSTOMER', payload['customer_party_uuid']);
    final supplier =
        await _partyLegacyId(txn, 'SUPPLIER', payload['supplier_party_uuid']);
    final gl =
        await _localIntByUuid(txn, 'gl_entry', payload['gl_entry_entity_uuid']);
    final origin = await _localIntByUuid(
        txn, 'cheque', payload['origin_cheque_entity_uuid']);
    const allowed = <String>{
      'uuid',
      'cheque_no',
      'cheque_type',
      'status',
      'drawer_name',
      'bank_name',
      'bank_branch',
      'amount',
      'currency',
      'issue_date',
      'due_date',
      'source_type',
      'source_id',
      'supplier_pid',
      'recipient_type',
      'recipient_id',
      'recipient_name',
      'linked_payment_ids',
      'linked_repair_ids',
      'notes',
      'is_endorsed',
      'endorsed_at',
      'last_endorser_name',
      'auto_return_date',
      'return_reason',
      'is_legacy_incomplete',
      'created_at',
      'updated_at',
      'payment_id',
      'date',
      'bank',
      'number',
    };
    final values = _pick(payload, allowed)
      ..['uuid'] = change.entityUuid
      ..['client_id'] = client
      ..['supplier_id'] = supplier
      ..['gl_entry_id'] = gl
      ..['origin_cheque_id'] = origin?.toString();
    if (identity == null) {
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'cheque',
        entityUuid: change.entityUuid,
        revision: 1,
        action: () => txn.insert('cheques', values),
      );
      return;
    }
    final id = int.parse(identity['local_id'].toString());
    final current =
        (await txn.query('cheques', where: 'id=?', whereArgs: [id])).single;
    final posted = current['gl_entry_id'] != null;
    const mutableAfterPosting = <String>{
      'status',
      'recipient_type',
      'recipient_id',
      'recipient_name',
      'linked_payment_ids',
      'linked_repair_ids',
      'gl_entry_id',
      'notes',
      'is_endorsed',
      'endorsed_at',
      'last_endorser_name',
      'auto_return_date',
      'return_reason',
      'updated_at',
    };
    final update = posted
        ? <String, Object?>{
            for (final e in values.entries)
              if (mutableAfterPosting.contains(e.key)) e.key: e.value,
          }
        : values;
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'cheque',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () =>
          txn.update('cheques', update, where: 'id=?', whereArgs: [id]),
    );
  }

  static Future<void> _applyAdvance(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity =
        await _identity(txn, 'employee_advance', change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = _newTextId(change, identity);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_POSTED_FINANCIAL_DELETE_DENIED');
    }
    final employee =
        await _localIdByUuid(txn, 'employee', payload['employee_entity_uuid']);
    final gl =
        await _localIntByUuid(txn, 'gl_entry', payload['gl_entry_entity_uuid']);
    const allowed = <String>{
      'amount',
      'type',
      'date',
      'method',
      'note',
      'created_at'
    };
    final values = _pick(payload, allowed)
      ..['employee_id'] = employee
      ..['gl_entry_id'] = gl;
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'employee_advance',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows = await txn
            .query('employee_advances', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          await txn.insert('employee_advances', {'id': id, ...values});
        } else {
          final current = rows.single;
          if (current['gl_entry_id'] != null) {
            final onlyLink = <String, Object?>{'gl_entry_id': gl};
            await txn.update('employee_advances', onlyLink,
                where: 'id=?', whereArgs: [id]);
          } else {
            await txn.update('employee_advances', values,
                where: 'id=?', whereArgs: [id]);
          }
        }
      },
    );
  }

  static Future<void> _applyPayrollRun(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'payroll_run', change.entityUuid);
    _requireRevision(identity, change.revision);
    final id = _newTextId(change, identity);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_POSTED_FINANCIAL_DELETE_DENIED');
    }
    final employee =
        await _localIdByUuid(txn, 'employee', payload['employee_entity_uuid']);
    const allowed = <String>{
      'gross',
      'allowances',
      'deductions',
      'advance_applied',
      'net',
      'amount_paid',
      'status',
      'period_start',
      'period_end',
      'accrual_date',
      'method',
      'note',
      'attendance_snapshot',
      'entitlement_basis',
      'created_at',
    };
    final values = _pick(payload, allowed)..['employee_id'] = employee;
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'payroll_run',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        final rows =
            await txn.query('payroll_runs', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          await txn.insert('payroll_runs', {'id': id, ...values});
          return;
        }
        final gl = await txn.rawQuery(
          "SELECT 1 FROM gl_entries WHERE UPPER(source)='PAYROLL_ACCRUAL' AND source_id=? LIMIT 1",
          [id],
        );
        if (gl.isEmpty) {
          await txn
              .update('payroll_runs', values, where: 'id=?', whereArgs: [id]);
          return;
        }
        const mutable = <String>{'amount_paid', 'status', 'method', 'note'};
        final update = <String, Object?>{
          for (final e in values.entries)
            if (mutable.contains(e.key)) e.key: e.value,
        };
        await txn
            .update('payroll_runs', update, where: 'id=?', whereArgs: [id]);
      },
    );
  }

  static Future<void> _applyPayrollPayment(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'payroll_payment', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (identity != null ||
        change.operation != 'UPSERT' ||
        change.revision != 1) {
      throw StateError('SYNC_PAYROLL_PAYMENT_IMMUTABLE');
    }
    final id = _newTextId(change, identity);
    final run = await _localIdByUuid(
        txn, 'payroll_run', payload['payroll_run_entity_uuid']);
    final voucherUuid = _text(payload['voucher_entity_uuid']);
    final voucher = voucherUuid == null
        ? null
        : await _localIdByUuid(txn, 'voucher', voucherUuid);
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'payroll_payment',
      entityUuid: change.entityUuid,
      revision: 1,
      action: () => txn.insert('payroll_payments', {
        'id': id,
        'run_id': run,
        'amount': _money(payload['amount'], 'amount'),
        'date': _text(payload['date']) ?? change.occurredAt.toIso8601String(),
        'method': _text(payload['method']),
        'note': _text(payload['note']),
        'voucher_id': voucher,
      }),
    );
  }

  static Future<void> _applySettlement(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity =
        await _identity(txn, 'invoice_settlement', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (identity != null ||
        change.operation != 'UPSERT' ||
        change.revision != 1) {
      throw StateError('SYNC_SETTLEMENT_IMMUTABLE');
    }
    final id = _newTextId(change, identity);
    final supplier =
        await _partyLegacyId(txn, 'SUPPLIER', payload['supplier_party_uuid']);
    final invoice = await _localIdByUuid(
        txn, 'purchase_invoice', payload['purchase_invoice_entity_uuid']);
    final voucher =
        await _localIdByUuid(txn, 'voucher', payload['voucher_entity_uuid']);
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'invoice_settlement',
      entityUuid: change.entityUuid,
      revision: 1,
      action: () => txn.insert('invoice_settlements', {
        'id': id,
        'supplier_id': supplier,
        'invoice_id': invoice,
        'voucher_id': voucher,
        'amount_applied': _money(payload['amount_applied'], 'amount_applied'),
        'created_at':
            _text(payload['created_at']) ?? change.occurredAt.toIso8601String(),
      }),
    );
  }

  static Future<void> _applyMonthlyExpense(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'monthly_expense', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (change.operation == 'DELETE') {
      throw StateError('SYNC_MONTHLY_EXPENSE_DELETE_DENIED');
    }
    const allowed = <String>{
      'month',
      'salaries',
      'raw_materials',
      'electricity',
      'rent',
      'other',
      'date'
    };
    final values = _pick(payload, allowed);
    if (identity == null) {
      await SyncFoundationService.withRemoteMutation(
        txn,
        entityType: 'monthly_expense',
        entityUuid: change.entityUuid,
        revision: 1,
        action: () => txn.insert('monthly_expenses', values),
      );
      return;
    }
    final id = int.parse(identity['local_id'].toString());
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'monthly_expense',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () => txn
          .update('monthly_expenses', values, where: 'id=?', whereArgs: [id]),
    );
  }

  static Future<void> _applyGlEntry(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'gl_entry', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (change.operation != 'UPSERT' ||
        change.revision != 1 ||
        identity != null) {
      throw StateError('SYNC_GL_ENTRY_IMMUTABLE');
    }
    final source = (_text(payload['source']) ?? '').toUpperCase();
    final sourceId = _text(payload['source_id']);
    if (source.isEmpty || sourceId == null) {
      throw StateError('SYNC_GL_SOURCE_IDENTITY_REQUIRED');
    }
    final duplicate = await txn.rawQuery(
      '''SELECT id FROM gl_entries
      WHERE ${AccountingSourcePolicy.sqlCanonicalExpression('source')}=?
        AND TRIM(source_id)=? LIMIT 1''',
      [AccountingSourcePolicy.canonical(source), sourceId],
    );
    if (duplicate.isNotEmpty) throw StateError('SYNC_GL_SOURCE_CONFLICT');
    final reversal = await _localIntByUuid(
      txn,
      'gl_entry',
      payload['reversal_of_entity_uuid'],
    );
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'gl_entry',
      entityUuid: change.entityUuid,
      revision: 1,
      action: () => AccountingTables.stageSyncedGlEntryOn(
        ex: txn,
        date: DateTime.tryParse(_text(payload['date']) ?? '') ??
            change.occurredAt,
        ref: _text(payload['ref']),
        source: source,
        sourceId: sourceId,
        sourceNumber: _text(payload['source_number']),
        postingVersion: _int(payload['posting_version']) ?? 1,
        reversalOf: reversal,
        createdBy: _text(payload['created_by']),
        note: _text(payload['note']),
        createdAt: DateTime.tryParse(_text(payload['created_at']) ?? ''),
      ),
    );
  }

  static Future<void> _applyGlLine(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity = await _identity(txn, 'gl_line', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (identity != null ||
        change.operation != 'UPSERT' ||
        change.revision != 1) {
      throw StateError('SYNC_GL_LINE_IMMUTABLE');
    }
    final entry =
        await _localIntByUuid(txn, 'gl_entry', payload['gl_entry_entity_uuid']);
    if (entry == null) throw StateError('SYNC_REFERENCE_MISSING:gl_entry');
    final debit = _money(payload['debit'] ?? 0, 'debit');
    final credit = _money(payload['credit'] ?? 0, 'credit');
    if (debit < 0 ||
        credit < 0 ||
        (debit > 0 && credit > 0) ||
        (debit == 0 && credit == 0)) {
      throw StateError('SYNC_GL_LINE_AMOUNT_INVALID');
    }
    final partyType = _text(payload['party_type']);
    final partyId = await _partyLocalId(
      txn,
      partyType,
      payload['party_entity_uuid'],
      payload['party_local_hint'],
    );
    final invoiceUuid = _text(payload['invoice_entity_uuid']);
    final repairUuid = _text(payload['repair_entity_uuid']);
    final invoice = invoiceUuid == null
        ? null
        : await _localIdByUuid(txn, 'invoice', invoiceUuid);
    final repair = repairUuid == null
        ? null
        : await _localIdByUuid(txn, 'repair', repairUuid);
    final cheque =
        await _localIntByUuid(txn, 'cheque', payload['cheque_entity_uuid']);
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'gl_line',
      entityUuid: change.entityUuid,
      revision: 1,
      action: () async {
        final account = await _accountId(txn, payload);
        await AccountingTables.stageSyncedGlLineOn(
          ex: txn,
          entryId: entry,
          accountId: account,
          debit: debit,
          credit: credit,
          partyType: partyType,
          partyId: partyId,
          invoiceId: invoice,
          repairId: repair,
          chequeId: cheque,
          referenceId: _text(payload['reference_id']),
          referenceType: _text(payload['reference_type']),
          createdAt: DateTime.tryParse(_text(payload['created_at']) ?? '') ??
              change.occurredAt,
        );
      },
    );
  }

  static Future<void> _applyAudit(
    Transaction txn,
    InboundSyncChange change,
  ) async {
    final payload = Map<String, Object?>.from(change.payload);
    final identity =
        await _identity(txn, 'accounting_audit_event', change.entityUuid);
    _requireRevision(identity, change.revision);
    if (identity != null ||
        change.operation != 'UPSERT' ||
        change.revision != 1) {
      throw StateError('SYNC_ACCOUNTING_AUDIT_IMMUTABLE');
    }
    final gl =
        await _localIntByUuid(txn, 'gl_entry', payload['gl_entry_entity_uuid']);
    if (gl == null) throw StateError('SYNC_REFERENCE_MISSING:gl_entry');
    final entryRows =
        await txn.query('gl_entries', where: 'id=?', whereArgs: [gl], limit: 1);
    if (entryRows.isEmpty) throw StateError('SYNC_GL_ENTRY_MISSING');
    final entry = entryRows.single;
    final balance = await txn.rawQuery(
      '''SELECT COUNT(*) AS c,
        COALESCE(SUM(ROUND(debit*100)),0) AS d,
        COALESCE(SUM(ROUND(credit*100)),0) AS cr
      FROM gl_lines WHERE entry_id=?''',
      [gl],
    );
    final count = _int(balance.single['c']) ?? 0;
    final debit = _int(balance.single['d']) ?? 0;
    final credit = _int(balance.single['cr']) ?? 0;
    if (count < 2 || debit <= 0 || debit != credit) {
      throw StateError('SYNC_GL_UNBALANCED_ENTRY');
    }
    final source = _text(entry['source']) ?? '';
    final sourceId = _text(entry['source_id']) ?? '';
    if (_text(payload['source']) != source ||
        _text(payload['source_id']) != sourceId) {
      throw StateError('SYNC_ACCOUNTING_AUDIT_SOURCE_MISMATCH');
    }
    final reversal = await _localIntByUuid(
      txn,
      'gl_entry',
      payload['reversal_of_entity_uuid'],
    );
    await SyncFoundationService.withRemoteMutation(
      txn,
      entityType: 'accounting_audit_event',
      entityUuid: change.entityUuid,
      revision: 1,
      action: () => AccountingIntegrityTables.recordPostingEvent(
        txn,
        glEntryId: gl,
        source: source,
        sourceId: sourceId,
        canonicalSource: AccountingSourcePolicy.canonical(source),
        reversalOf: reversal,
        actorUserId: _text(payload['actor_user_id']),
      ),
    );
  }
}
