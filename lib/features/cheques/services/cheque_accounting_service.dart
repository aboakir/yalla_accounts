import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
// -----------------------------------------------------------------------------
// lib/features/cheques/services/cheque_accounting_service.dart
// P0.008 — one canonical cheque lifecycle / accounting service
// -----------------------------------------------------------------------------

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/cheque_tables.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';

class ChequeAccountingService {
  static bool isChequeMethod(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'cheque' ||
        normalized == 'check' ||
        normalized == 'شيك' ||
        normalized == 'شيكات' ||
        normalized.contains('cheque') ||
        normalized.contains('check') ||
        normalized.contains('شيك');
  }

  static Future<int> createLinkedChequeOnTxn({
    required Transaction txn,
    required Map<String, dynamic> draft,
    required ChequeType type,
    required double amount,
    required String currency,
    required String sourceType,
    required String sourceId,
    int? clientId,
    String? supplierPid,
    String? recipientType,
    String? recipientId,
    String? recipientName,
  }) async {
    await ChequeTables.ensureChequesSchema(txn);

    if (amount <= 0) {
      throw StateError('Cheque amount must be greater than zero.');
    }
    if (sourceId.trim().isEmpty || sourceType.trim().isEmpty) {
      throw StateError('Cheque requires a valid accounting source.');
    }

    final chequeNo = (draft['cheque_no'] ?? '').toString().trim();
    final drawerName = (draft['drawer_name'] ?? '').toString().trim();
    final bankName = (draft['bank_name'] ?? '').toString().trim();
    final bankBranch = (draft['bank_branch'] ?? '').toString().trim();
    final notes = (draft['notes'] ?? '').toString().trim();
    final lastEndorser = (draft['last_endorser_name'] ?? '').toString().trim();

    if (chequeNo.isEmpty) {
      throw StateError('Cheque number is required.');
    }
    if (drawerName.isEmpty) {
      throw StateError('Cheque drawer name is required.');
    }
    if (bankName.isEmpty) {
      throw StateError('Cheque bank is required.');
    }

    final issueDate = _parseDate(draft['issue_date'], 'issue date');
    final dueDate = _parseDate(draft['due_date'], 'due date');

    final existing = await txn.query(
      'cheques',
      columns: ['id', 'amount', 'cheque_type'],
      where: 'source_type=? AND source_id=?',
      whereArgs: [sourceType.toUpperCase(), sourceId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingAmount =
          double.tryParse(existing.first['amount'].toString()) ?? 0.0;
      final existingType =
          (existing.first['cheque_type'] ?? '').toString().toLowerCase();

      if ((existingAmount - amount).abs() > 0.01 || existingType != type.name) {
        throw StateError(
          'Existing cheque for $sourceType/$sourceId has different '
          'material fields.',
        );
      }

      return _asInt(existing.first['id']);
    }

    if (type == ChequeType.outgoing &&
        (supplierPid == null || supplierPid.trim().isEmpty) &&
        (recipientName == null || recipientName.trim().isEmpty)) {
      throw StateError('Outgoing cheque requires a recipient.');
    }

    if (type == ChequeType.incoming && (clientId == null || clientId <= 0)) {
      throw StateError('Incoming cheque requires a client.');
    }

    final uuid = (draft['uuid'] ?? '').toString().trim().isNotEmpty
        ? draft['uuid'].toString().trim()
        : 'chq-${DateTime.now().microsecondsSinceEpoch}';

    final now = DateTime.now().toIso8601String();
    final linkedPayments =
        sourceType.toUpperCase() == 'PAYMENT' ? jsonEncode([sourceId]) : '[]';

    final id = await txn.insert(
      'cheques',
      {
        'uuid': uuid,
        'cheque_no': chequeNo,
        'cheque_type': type.name,
        'status': ChequeStatus.pending.name,
        'drawer_name': drawerName,
        'bank_name': bankName,
        'bank_branch': bankBranch,
        'amount': amount,
        'currency': currency.trim().isEmpty ? 'ILS' : currency.trim(),
        'issue_date': issueDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'source_type': sourceType.toUpperCase(),
        'source_id': sourceId,
        'supplier_pid': supplierPid,
        'client_id': clientId,
        'recipient_type': recipientType,
        'recipient_id': recipientId,
        'recipient_name': recipientName,
        'linked_payment_ids': linkedPayments,
        'linked_repair_ids': '[]',
        'gl_entry_id': null,
        'notes': notes.isEmpty ? null : notes,
        'origin_cheque_id': null,
        'is_endorsed': 0,
        'endorsed_at': null,
        'last_endorser_name': lastEndorser.isEmpty ? null : lastEndorser,
        'auto_return_date': null,
        'return_reason': null,
        'is_legacy_incomplete': 0,
        'created_at': now,
        'updated_at': now,

        // Compatibility aliases.
        'supplier_id': int.tryParse(supplierPid ?? ''),
        'payment_id': sourceType.toUpperCase() == 'PAYMENT' ? sourceId : null,
        'date': issueDate.toIso8601String(),
        'bank': bankName,
        'number': chequeNo,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    await _event(
      txn,
      chequeId: id,
      type: 'registered',
      fromStatus: null,
      toStatus: ChequeStatus.pending.name,
      note: '$sourceType/$sourceId',
    );

    return id;
  }

  static Future<void> attachInitialGlOnTxn({
    required Transaction txn,
    required int chequeId,
    required int glEntryId,
  }) async {
    await txn.update(
      'cheques',
      {
        'gl_entry_id': glEntryId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );

    final existingEvent = await txn.query(
      'cheque_events',
      columns: ['id'],
      where: 'cheque_id=? AND event_type=? AND gl_entry_id=?',
      whereArgs: [chequeId, 'initial_accounting', glEntryId],
      limit: 1,
    );

    if (existingEvent.isEmpty) {
      await _event(
        txn,
        chequeId: chequeId,
        type: 'initial_accounting',
        fromStatus: ChequeStatus.pending.name,
        toStatus: ChequeStatus.pending.name,
        glEntryId: glEntryId,
      );
    }
  }

  static Future<Cheque> transitionStatus({
    required int chequeId,
    required ChequeStatus newStatus,
    String? reason,
    DateTime? eventDate,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.chequeManage);
    final db = await DBService.database;
    final beforeRows = await db.query(
      'cheques',
      columns: const ['status'],
      where: 'id=?',
      whereArgs: [chequeId],
      limit: 1,
    );
    final beforeStatus =
        beforeRows.isEmpty ? null : beforeRows.first['status']?.toString();
    final result = await SyncFoundationService.transaction<Cheque>(
      db,
      (txn) => transitionStatusOnTxn(
        txn: txn,
        chequeId: chequeId,
        newStatus: newStatus,
        reason: reason,
        eventDate: eventDate,
      ),
    );
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'CHEQUE_STATUS_CHANGED',
      entityType: 'cheque',
      entityId: chequeId.toString(),
      before: {'status': beforeStatus},
      after: {'status': result.status.name},
      reason: reason,
    );
    return result;
  }

  /// P11: same-transaction lifecycle action used by a formal receipt reversal.
  /// This keeps cheque status + lifecycle GL + receipt counter-document atomic.
  static Future<Cheque> transitionStatusOnTxn({
    required Transaction txn,
    required int chequeId,
    required ChequeStatus newStatus,
    String? reason,
    DateTime? eventDate,
  }) async {
    await ChequeTables.ensureChequesSchema(txn);

    final rows = await txn.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Cheque not found.');

    final cheque = Cheque.fromMap(rows.first);
    if (cheque.isLegacyIncomplete == 1) {
      throw StateError(
        'Complete the recovered cheque number, bank and dates before '
        'recording a lifecycle event.',
      );
    }
    if (cheque.status == newStatus) return cheque;

    _assertTransition(cheque, newStatus);

    final when = eventDate ?? DateTime.now();
    int? lifecycleGlId;
    final hasAccountingSource = cheque.glEntryId != null &&
        (cheque.sourceType ?? '').trim().isNotEmpty &&
        (cheque.sourceId ?? '').trim().isNotEmpty;

    if (hasAccountingSource) {
      lifecycleGlId = await _postStatusAccounting(
        txn: txn,
        cheque: cheque,
        newStatus: newStatus,
        date: when,
        reason: reason,
      );
    }

    await txn.update(
      'cheques',
      {
        'status': newStatus.name,
        'return_reason': (newStatus == ChequeStatus.returned ||
                newStatus == ChequeStatus.cancelled)
            ? reason
            : cheque.returnReason,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [chequeId],
    );

    await _event(
      txn,
      chequeId: chequeId,
      type: 'status:${newStatus.name}',
      fromStatus: cheque.status.name,
      toStatus: newStatus.name,
      glEntryId: lifecycleGlId,
      note: reason,
      eventDate: when,
    );

    final refreshed = await txn.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
      limit: 1,
    );
    return Cheque.fromMap(refreshed.first);
  }

  static Future<Cheque> endorseToSupplier({
    required int chequeId,
    required String supplierPid,
    required DateTime endorsementDate,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.chequeManage);
    final db = await DBService.database;

    final result =
        await SyncFoundationService.transaction<Cheque>(db, (txn) async {
      await ChequeTables.ensureChequesSchema(txn);

      final rows = await txn.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Cheque not found.');

      final cheque = Cheque.fromMap(rows.first);
      if (cheque.isLegacyIncomplete == 1) {
        throw StateError('Complete recovered cheque metadata first.');
      }
      if (cheque.chequeType != ChequeType.incoming ||
          cheque.status != ChequeStatus.pending) {
        throw StateError(
          'Only a pending incoming cheque can be endorsed.',
        );
      }
      if (cheque.glEntryId == null ||
          (cheque.sourceType ?? '').trim().isEmpty ||
          (cheque.sourceId ?? '').trim().isEmpty) {
        throw StateError(
          'An unaccounted manual cheque cannot be endorsed financially.',
        );
      }

      final supplierId = int.tryParse(supplierPid);
      if (supplierId == null || supplierId <= 0) {
        throw StateError('Invalid supplier.');
      }

      final apId = await _ensureSupplierAp(txn, supplierId);
      final incomingId = await _requiredAccount(txn, '1020');

      final glId = await DBService.postEntryGLOn(
        ex: txn,
        date: endorsementDate,
        source: 'CHEQUE_ENDORSE',
        sourceId: chequeId.toString(),
        note: 'Cheque endorsed to supplier $supplierId',
        lines: [
          {
            'account_id': apId,
            'debit': cheque.amount,
            'credit': 0.0,
            'party_type': 'SUPPLIER',
            'party_id': supplierId.toString(),
            'cheque_id': chequeId,
          },
          {
            'account_id': incomingId,
            'debit': 0.0,
            'credit': cheque.amount,
            'party_type': null,
            'party_id': null,
            'cheque_id': chequeId,
          },
        ],
      );

      await txn.update(
        'cheques',
        {
          'cheque_type': ChequeType.outgoing.name,
          'status': ChequeStatus.delivered.name,
          'supplier_pid': supplierId.toString(),
          'supplier_id': supplierId,
          'recipient_type': 'SUPPLIER',
          'recipient_id': supplierId.toString(),
          'is_endorsed': 1,
          'endorsed_at': endorsementDate.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [chequeId],
      );

      await _event(
        txn,
        chequeId: chequeId,
        type: 'endorsed',
        fromStatus: cheque.status.name,
        toStatus: ChequeStatus.delivered.name,
        glEntryId: glId,
        note: 'Supplier $supplierId',
        eventDate: endorsementDate,
      );

      final refreshed = await txn.query(
        'cheques',
        where: 'id=?',
        whereArgs: [chequeId],
        limit: 1,
      );
      return Cheque.fromMap(refreshed.first);
    });
    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'CHEQUE_ENDORSED',
      entityType: 'cheque',
      entityId: chequeId.toString(),
      before: {
        'status': ChequeStatus.pending.name,
        'cheque_type': ChequeType.incoming.name
      },
      after: {
        'status': result.status.name,
        'cheque_type': result.chequeType.name,
        'supplier_id': supplierPid,
      },
    );
    return result;
  }

  static Future<Map<String, Object?>> _paymentDimensionsOnTxn(
    DatabaseExecutor db,
    Cheque cheque,
  ) async {
    if ((cheque.sourceType ?? '').toUpperCase() == 'VOUCHER') {
      final rows = await db.query('vouchers',
          columns: ['reference'],
          where: 'id=?',
          whereArgs: [cheque.sourceId],
          limit: 1);
      return {'invoice_id': rows.isEmpty ? null : rows.first['reference']};
    }
    if ((cheque.sourceType ?? '').toUpperCase() != 'PAYMENT' ||
        (cheque.sourceId ?? '').trim().isEmpty) {
      return const <String, Object?>{};
    }
    final rows = await db.query(
      'payments',
      columns: const ['repair_id', 'invoice_id'],
      where: 'id=?',
      whereArgs: [cheque.sourceId],
      limit: 1,
    );
    if (rows.isEmpty) return const <String, Object?>{};
    return <String, Object?>{
      'repair_id': rows.first['repair_id'],
      'invoice_id': rows.first['invoice_id'],
    };
  }

  static Future<int?> _postStatusAccounting({
    required Transaction txn,
    required Cheque cheque,
    required ChequeStatus newStatus,
    required DateTime date,
    String? reason,
  }) async {
    final incomingId = await _requiredAccount(txn, '1020');
    final outgoingId = await _requiredAccount(txn, '1030');
    final bankId = await _requiredAccount(txn, '1010');
    final paymentDimensions = await _paymentDimensionsOnTxn(txn, cheque);

    List<Map<String, Object?>>? lines;

    if (newStatus == ChequeStatus.deposited ||
        newStatus == ChequeStatus.delivered) {
      return null;
    }

    // An endorsed customer cheque is not an own outgoing cheque.
    // Endorsement already posted Dr supplier AP / Cr incoming cheques.
    if (cheque.isEndorsed == 1) {
      if (newStatus == ChequeStatus.collected) {
        // Supplier successfully collected the third-party cheque:
        // no additional workshop GL event.
        return null;
      }

      if (newStatus == ChequeStatus.returned) {
        final clientId = cheque.clientId;
        final supplierId = int.tryParse(cheque.supplierPid ?? '');

        if (clientId == null ||
            clientId <= 0 ||
            supplierId == null ||
            supplierId <= 0) {
          throw StateError(
            'Returned endorsed cheque requires both client and supplier.',
          );
        }

        final arId = await _ensureClientAr(txn, clientId);
        final apId = await _ensureSupplierAp(txn, supplierId);

        lines = [
          {
            'account_id': arId,
            'debit': cheque.amount,
            'credit': 0.0,
            'party_type': 'CLIENT',
            'party_id': clientId.toString(),
            'repair_id': paymentDimensions['repair_id'],
            'invoice_id': paymentDimensions['invoice_id'],
            'cheque_id': cheque.id,
          },
          {
            'account_id': apId,
            'debit': 0.0,
            'credit': cheque.amount,
            'party_type': 'SUPPLIER',
            'party_id': supplierId.toString(),
            'cheque_id': cheque.id,
          },
        ];
      }
    }

    if (lines == null && newStatus == ChequeStatus.collected) {
      if (cheque.chequeType == ChequeType.incoming) {
        lines = [
          {
            'account_id': bankId,
            'debit': cheque.amount,
            'credit': 0.0,
            'cheque_id': cheque.id,
          },
          {
            'account_id': incomingId,
            'debit': 0.0,
            'credit': cheque.amount,
            'cheque_id': cheque.id,
          },
        ];
      } else {
        lines = [
          {
            'account_id': outgoingId,
            'debit': cheque.amount,
            'credit': 0.0,
            'cheque_id': cheque.id,
          },
          {
            'account_id': bankId,
            'debit': 0.0,
            'credit': cheque.amount,
            'cheque_id': cheque.id,
          },
        ];
      }
    }

    if (lines == null &&
        (newStatus == ChequeStatus.returned ||
            newStatus == ChequeStatus.cancelled)) {
      if (cheque.chequeType == ChequeType.incoming) {
        final clientId = cheque.clientId;
        if (clientId == null || clientId <= 0) {
          throw StateError(
            'Incoming cheque return/cancellation requires a client.',
          );
        }
        final arId = await _ensureClientAr(txn, clientId);
        lines = [
          {
            'account_id': arId,
            'debit': cheque.amount,
            'credit': 0.0,
            'party_type': 'CLIENT',
            'party_id': clientId.toString(),
            'repair_id': paymentDimensions['repair_id'],
            'invoice_id': paymentDimensions['invoice_id'],
            'cheque_id': cheque.id,
          },
          {
            'account_id': incomingId,
            'debit': 0.0,
            'credit': cheque.amount,
            'cheque_id': cheque.id,
          },
        ];
      } else {
        final restoreId = await _outgoingRestoreAccount(txn, cheque);
        lines = [
          {
            'account_id': outgoingId,
            'debit': cheque.amount,
            'credit': 0.0,
            'cheque_id': cheque.id,
          },
          {
            'account_id': restoreId,
            'debit': 0.0,
            'credit': cheque.amount,
            'party_type': cheque.supplierPid != null ? 'SUPPLIER' : null,
            'party_id': cheque.supplierPid,
            'invoice_id': paymentDimensions['invoice_id'],
            'cheque_id': cheque.id,
          },
        ];
      }
    }

    if (lines == null) return null;

    return DBService.postEntryGLOn(
      ex: txn,
      date: date,
      source: 'CHEQUE_STATUS',
      sourceId: '${cheque.id}:${newStatus.name}',
      note: 'Cheque ${newStatus.name}${reason == null ? '' : ' — $reason'}',
      lines: lines,
    );
  }

  static Future<int> _outgoingRestoreAccount(
    Transaction txn,
    Cheque cheque,
  ) async {
    final supplierId = int.tryParse(cheque.supplierPid ?? '');
    if (supplierId != null && supplierId > 0) {
      return _ensureSupplierAp(txn, supplierId);
    }

    if ((cheque.sourceType ?? '').toUpperCase() == 'VOUCHER' &&
        (cheque.sourceId ?? '').trim().isNotEmpty) {
      final rows = await txn.rawQuery(r'''
        SELECT l.account_id
        FROM gl_entries e
        JOIN gl_lines l ON l.entry_id=e.id
        WHERE e.source='VOUCHER'
          AND e.source_id=?
          AND l.debit > 0
        ORDER BY l.id
        LIMIT 1
      ''', [cheque.sourceId]);

      if (rows.isNotEmpty) {
        return _asInt(rows.first['account_id']);
      }
    }

    throw StateError(
      'Cannot determine the account to restore for this outgoing cheque.',
    );
  }

  static void _assertTransition(Cheque cheque, ChequeStatus next) {
    final current = cheque.status;

    if (cheque.isEndorsed == 1) {
      final allowedEndorsed = current == ChequeStatus.delivered &&
          (next == ChequeStatus.collected || next == ChequeStatus.returned);
      if (!allowedEndorsed) {
        throw StateError(
          'Endorsed cheque can only be collected or returned.',
        );
      }
      return;
    }

    final allowed = cheque.chequeType == ChequeType.incoming
        ? <ChequeStatus, Set<ChequeStatus>>{
            ChequeStatus.pending: {
              ChequeStatus.deposited,
              ChequeStatus.collected,
              ChequeStatus.returned,
              ChequeStatus.cancelled,
            },
            ChequeStatus.deposited: {
              ChequeStatus.collected,
              ChequeStatus.returned,
              ChequeStatus.cancelled,
            },
          }
        : <ChequeStatus, Set<ChequeStatus>>{
            ChequeStatus.pending: {
              ChequeStatus.delivered,
              ChequeStatus.collected,
              ChequeStatus.returned,
              ChequeStatus.cancelled,
            },
            ChequeStatus.delivered: {
              ChequeStatus.collected,
              ChequeStatus.returned,
              ChequeStatus.cancelled,
            },
          };

    if (!(allowed[current]?.contains(next) ?? false)) {
      throw StateError(
        'Invalid cheque status transition: ${current.name} -> ${next.name}',
      );
    }
  }

  static DateTime _parseDate(Object? value, String field) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) throw StateError('Invalid cheque $field.');
    return parsed;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) throw StateError('Invalid integer value: $value');
    return parsed;
  }

  static Future<int> _requiredAccount(
    DatabaseExecutor db,
    String code,
  ) async {
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Missing account $code.');
    return _asInt(rows.first['id']);
  }

  static Future<int> _ensureSupplierAp(
    DatabaseExecutor db,
    int supplierId,
  ) async {
    final supplier = await db.query(
      'suppliers',
      columns: ['name'],
      where: 'id=?',
      whereArgs: [supplierId],
      limit: 1,
    );
    if (supplier.isEmpty) throw StateError('Supplier $supplierId not found.');

    final code = '2200.S${supplierId.toString().padLeft(4, '0')}';
    final existing = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (existing.isNotEmpty) return _asInt(existing.first['id']);

    return SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              'accounts',
              {
                'code': code,
                'name': supplier.first['name']?.toString() ??
                    'Supplier $supplierId',
                'type': 'LIABILITY',
                'normal_balance': 'CREDIT',
                'created_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            ));
  }

  static Future<int> _ensureClientAr(
    DatabaseExecutor db,
    int clientId,
  ) async {
    final client = await db.query(
      'clients',
      columns: ['name'],
      where: 'id=?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (client.isEmpty) throw StateError('Client $clientId not found.');

    final code = '1200.C$clientId';
    final existing = await db.query(
      'accounts',
      columns: ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (existing.isNotEmpty) return _asInt(existing.first['id']);

    return SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              'accounts',
              {
                'code': code,
                'name': 'عميل: ${client.first['name']}',
                'type': 'ASSET',
                'normal_balance': 'DEBIT',
                'created_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            ));
  }

  static Future<void> _event(
    DatabaseExecutor db, {
    required int chequeId,
    required String type,
    String? fromStatus,
    String? toStatus,
    int? glEntryId,
    String? note,
    DateTime? eventDate,
  }) async {
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              'cheque_events',
              {
                'cheque_id': chequeId,
                'event_type': type,
                'from_status': fromStatus,
                'to_status': toStatus,
                'event_date': (eventDate ?? DateTime.now()).toIso8601String(),
                'gl_entry_id': glEntryId,
                'note': note,
                'created_at': DateTime.now().toIso8601String(),
              },
            ));
  }
}
