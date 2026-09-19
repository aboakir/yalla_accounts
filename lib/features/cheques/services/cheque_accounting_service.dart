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
    String? instrumentKey,
    int? receiptVoucherId,
    String? paymentVoucherId,
    String? sourcePartyType,
    String? sourcePartyId,
    int? bankAccountId,
    String? chequeBookId,
    String? createdBy,
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
    final uuid = (draft['uuid'] ?? '').toString().trim().isNotEmpty
        ? draft['uuid'].toString().trim()
        : 'chq-${DateTime.now().microsecondsSinceEpoch}';
    final canonicalInstrumentKey =
        (instrumentKey ?? draft['instrument_key']?.toString() ?? uuid).trim();
    if (canonicalInstrumentKey.isEmpty) {
      throw StateError('Cheque instrument key is required.');
    }

    final existing = await txn.query(
      'cheques',
      columns: ['id', 'amount', 'cheque_type'],
      where: 'source_type=? AND source_id=? AND instrument_key=?',
      whereArgs: [sourceType.toUpperCase(), sourceId, canonicalInstrumentKey],
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

    final canonicalBankAccountId = bankAccountId ??
        (draft['bank_account_id'] is num
            ? (draft['bank_account_id'] as num).toInt()
            : int.tryParse('${draft['bank_account_id'] ?? ''}'));
    final canonicalChequeBookId =
        (chequeBookId ?? draft['cheque_book_id']?.toString())?.trim();
    if (type == ChequeType.outgoing && canonicalBankAccountId == null) {
      throw StateError('Outgoing cheque requires a bank account.');
    }

    final now = DateTime.now().toIso8601String();
    final linkedPayments =
        sourceType.toUpperCase() == 'PAYMENT' ? jsonEncode([sourceId]) : '[]';
    final direction = type == ChequeType.outgoing ? 'ISSUED' : 'RECEIVED';
    final initialStatus = type == ChequeType.outgoing
        ? ChequeStatus.issued.name
        : ChequeStatus.received.name;

    final id = await txn.insert(
        'cheques',
        {
          'uuid': uuid,
          'cheque_no': chequeNo,
          'cheque_type': type.name,
          'direction': direction,
          'status': initialStatus,
          'instrument_key': canonicalInstrumentKey,
          'drawer_name': drawerName,
          'bank_name': bankName,
          'bank_branch': bankBranch,
          'amount': amount,
          'currency': currency.trim().isEmpty ? 'ILS' : currency.trim(),
          'issue_date': issueDate.toIso8601String(),
          'due_date': dueDate.toIso8601String(),
          'source_type': sourceType.toUpperCase(),
          'source_id': sourceId,
          'receipt_voucher_id': receiptVoucherId,
          'payment_voucher_id': paymentVoucherId,
          'source_party_type': sourcePartyType,
          'source_party_id': sourcePartyId,
          'bank_account_id': canonicalBankAccountId,
          'cheque_book_id': canonicalChequeBookId,
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
          'created_by': createdBy,
          'created_at': now,
          'updated_at': now,

          // Compatibility aliases.
          'supplier_id': int.tryParse(supplierPid ?? ''),
          'payment_id': sourceType.toUpperCase() == 'PAYMENT' ? sourceId : null,
          'date': issueDate.toIso8601String(),
          'bank': bankName,
          'number': chequeNo,
        },
        conflictAlgorithm: ConflictAlgorithm.abort);

    await _event(
      txn,
      chequeId: id,
      type: 'registered',
      fromStatus: null,
      toStatus: initialStatus,
      note: '$sourceType/$sourceId',
    );

    return id;
  }

  static Future<void> linkChequeToVoucherOnTxn({
    required Transaction txn,
    required int chequeId,
    required String voucherType,
    required String voucherId,
    required String instrumentKey,
    required double amount,
  }) async {
    await ChequeTables.ensureChequesSchema(txn);
    final canonicalType = voucherType.trim().toUpperCase();
    if (!const {'RECEIPT', 'PAYMENT'}.contains(canonicalType)) {
      throw StateError('Unsupported cheque voucher type: ' + voucherType);
    }

    final existing = await txn.query(
      'cheque_voucher_links',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final same = existing.first['voucher_type'] == canonicalType &&
          existing.first['voucher_id'].toString() == voucherId &&
          existing.first['instrument_key'].toString() == instrumentKey &&
          (((existing.first['amount'] as num?)?.toDouble() ?? 0) - amount)
                  .abs() <=
              0.005;
      if (!same) {
        throw StateError('Cheque is already linked to a different voucher.');
      }
      return;
    }

    await txn.insert(
        'cheque_voucher_links',
        {
          'cheque_id': chequeId,
          'voucher_type': canonicalType,
          'voucher_id': voucherId,
          'instrument_key': instrumentKey,
          'amount': amount,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort);

    await txn.update(
      'cheques',
      canonicalType == 'RECEIPT'
          ? {'receipt_voucher_id': int.tryParse(voucherId)}
          : {'payment_voucher_id': voucherId},
      where: 'id=?',
      whereArgs: [chequeId],
    );

    await _event(
      txn,
      chequeId: chequeId,
      type: 'linked_to_voucher',
      note: canonicalType + '/' + voucherId,
    );
  }

  static Future<void> allocateChequeOnTxn({
    required Transaction txn,
    required int chequeId,
    required String voucherType,
    required String voucherId,
    required String allocationType,
    String? targetId,
    required double amount,
  }) async {
    if (amount <= 0.005) {
      throw StateError('Cheque allocation amount must be positive.');
    }
    final canonicalType = voucherType.trim().toUpperCase();
    final canonicalAllocationType = allocationType.trim().toUpperCase();
    final target = targetId?.trim();

    final existing = await txn.query(
      'cheque_allocations',
      where:
          "cheque_id=? AND voucher_type=? AND voucher_id=? AND allocation_type=? "
          "AND COALESCE(target_id,'')=COALESCE(?,'')",
      whereArgs: [
        chequeId,
        canonicalType,
        voucherId,
        canonicalAllocationType,
        target,
      ],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final oldAmount = (existing.first['amount'] as num?)?.toDouble() ?? 0;
      if ((oldAmount - amount).abs() > 0.005) {
        throw StateError('Existing cheque allocation has a different amount.');
      }
      return;
    }

    await txn.insert(
        'cheque_allocations',
        {
          'cheque_id': chequeId,
          'voucher_type': canonicalType,
          'voucher_id': voucherId,
          'allocation_type': canonicalAllocationType,
          'target_id': target,
          'amount': amount,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort);

    await _event(
      txn,
      chequeId: chequeId,
      type: 'allocated',
      note: canonicalType +
          '/' +
          voucherId +
          ' • ' +
          canonicalAllocationType +
          '/' +
          (target ?? '') +
          ' • ' +
          amount.toStringAsFixed(2),
    );
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
      final rows = await txn.query(
        'cheques',
        columns: const ['status'],
        where: 'id=?',
        whereArgs: [chequeId],
        limit: 1,
      );
      final status = rows.isEmpty ? null : rows.first['status']?.toString();
      await _event(
        txn,
        chequeId: chequeId,
        type: 'initial_accounting',
        fromStatus: status,
        toStatus: status,
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
    final p16Actor = await AuthorizationGuard.require(
      PermissionKeys.chequeManage,
    );
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
        actorUserId: p16Actor?.id,
      ),
    );
    if (beforeStatus == result.status.name) {
      return result;
    }
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
    String? actorUserId,
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

    final lifecycleFields = <String, Object?>{
      'status': newStatus.name,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (newStatus == ChequeStatus.deposited) {
      lifecycleFields['deposited_at'] = when.toIso8601String();
    } else if (newStatus == ChequeStatus.collected) {
      lifecycleFields['collection_date'] = when.toIso8601String();
    } else if (newStatus == ChequeStatus.delivered) {
      lifecycleFields['delivered_at'] = when.toIso8601String();
    } else if (newStatus == ChequeStatus.presented) {
      lifecycleFields['presented_at'] = when.toIso8601String();
    } else if (newStatus == ChequeStatus.cleared) {
      lifecycleFields['cleared_at'] = when.toIso8601String();
    } else if (newStatus == ChequeStatus.returned) {
      lifecycleFields['returned_at'] = when.toIso8601String();
      lifecycleFields['return_reason'] = reason;
    } else if (newStatus == ChequeStatus.cancelled) {
      lifecycleFields['cancelled_at'] = when.toIso8601String();
      lifecycleFields['cancelled_by'] = actorUserId;
      lifecycleFields['cancellation_reason'] = reason;
      lifecycleFields['return_reason'] = reason;
    }

    await txn.update(
      'cheques',
      lifecycleFields,
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
    final p16Actor = await AuthorizationGuard.require(
      PermissionKeys.chequeManage,
    );
    final db = await DBService.database;

    final result = await SyncFoundationService.transaction<Cheque>(db, (
      txn,
    ) async {
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
      if (cheque.direction != ChequeDirection.received ||
          !const {
            ChequeStatus.received,
            ChequeStatus.held,
          }.contains(cheque.status)) {
        throw StateError(
          'Only a received/held incoming cheque can be endorsed.',
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

      final supplierRows = await txn.query(
        'suppliers',
        columns: const ['name'],
        where: 'id=?',
        whereArgs: [supplierId],
        limit: 1,
      );
      final supplierName = supplierRows.isEmpty
          ? 'Supplier $supplierId'
          : supplierRows.first['name']?.toString() ?? 'Supplier $supplierId';
      final sequence = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(MAX(sequence_no),0)+1 '
              'FROM cheque_endorsements WHERE cheque_id=?',
              [chequeId],
            ),
          ) ??
          1;
      await txn.insert(
          'cheque_endorsements',
          {
            'id': 'END-$chequeId-$sequence',
            'cheque_id': chequeId,
            'sequence_no': sequence,
            'from_party_type': 'CLIENT',
            'from_party_id': cheque.clientId?.toString(),
            'from_party_name': cheque.drawerName,
            'to_party_type': 'SUPPLIER',
            'to_party_id': supplierId.toString(),
            'to_party_name': supplierName,
            'amount': cheque.amount,
            'purpose': 'SUPPLIER_PAYMENT',
            'source_obligation_type': 'SUPPLIER',
            'source_obligation_id': supplierId.toString(),
            'event_date': endorsementDate.toIso8601String(),
            'created_by': p16Actor?.id,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      await txn.update(
        'cheques',
        {
          'status': ChequeStatus.endorsed.name,
          'supplier_pid': supplierId.toString(),
          'supplier_id': supplierId,
          'recipient_type': 'SUPPLIER',
          'recipient_id': supplierId.toString(),
          'recipient_name': supplierName,
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
        toStatus: ChequeStatus.endorsed.name,
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
        'direction': ChequeDirection.received.name,
        'status': 'received_or_held',
      },
      after: {
        'direction': result.direction.name,
        'status': result.status.name,
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
      final rows = await db.query(
        'vouchers',
        columns: ['reference'],
        where: 'id=?',
        whereArgs: [cheque.sourceId],
        limit: 1,
      );
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

  static Future<String?> _invoiceForRepair(
    DatabaseExecutor db,
    String repairId,
  ) async {
    final rows = await db.query(
      'invoices',
      columns: const ['id'],
      where: 'repair_id=?',
      whereArgs: [repairId],
      orderBy: 'date DESC, rowid DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id']?.toString();
  }

  static Future<List<Map<String, Object?>>> _receivedReopenLines(
    Transaction txn,
    Cheque cheque,
  ) async {
    final clientId = cheque.clientId;
    if (clientId == null || clientId <= 0) {
      throw StateError(
        'Received cheque return/cancellation requires a client.',
      );
    }
    final arId = await _ensureClientAr(txn, clientId);
    final allocations = await txn.query(
      'cheque_allocations',
      where: 'cheque_id=?',
      whereArgs: [cheque.id],
      orderBy: 'id ASC',
    );

    if (allocations.isEmpty) {
      final dimensions = await _paymentDimensionsOnTxn(txn, cheque);
      return [
        {
          'account_id': arId,
          'debit': cheque.amount,
          'credit': 0.0,
          'party_type': 'CLIENT',
          'party_id': clientId.toString(),
          'repair_id': dimensions['repair_id'],
          'invoice_id': dimensions['invoice_id'],
          'cheque_id': cheque.id,
        },
      ];
    }

    final lines = <Map<String, Object?>>[];
    var total = 0.0;
    for (final allocation in allocations) {
      final amount = (allocation['amount'] as num?)?.toDouble() ??
          double.tryParse('${allocation['amount']}') ??
          0.0;
      if (amount <= 0.005) continue;
      total += amount;
      final type =
          (allocation['allocation_type'] ?? '').toString().toUpperCase();
      final targetId = allocation['target_id']?.toString();
      final repairId =
          type == 'REPAIR' && targetId != null && targetId.trim().isNotEmpty
              ? targetId.trim()
              : null;
      final invoiceId =
          repairId == null ? null : await _invoiceForRepair(txn, repairId);
      lines.add({
        'account_id': arId,
        'debit': amount,
        'credit': 0.0,
        'party_type': 'CLIENT',
        'party_id': clientId.toString(),
        'repair_id': repairId,
        'invoice_id': invoiceId,
        'cheque_id': cheque.id,
      });
    }

    if ((total - cheque.amount).abs() > 0.01) {
      throw StateError(
        'Cheque allocation total does not equal cheque amount; '
        'reconciliation is required before reversal.',
      );
    }
    return lines;
  }

  static Future<int> _bankAccountForCheque(
    DatabaseExecutor db,
    Cheque cheque,
  ) async {
    final id = cheque.bankAccountId;
    if (id == null || id <= 0) {
      throw StateError(
        'Cheque lifecycle event requires a selected bank account.',
      );
    }
    final rows = await db.query(
      'accounts',
      columns: const ['id'],
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Cheque bank account does not exist.');
    }
    return id;
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

    if (const {
      ChequeStatus.held,
      ChequeStatus.deposited,
      ChequeStatus.delivered,
      ChequeStatus.presented,
      ChequeStatus.endorsed,
    }.contains(newStatus)) {
      return null;
    }

    List<Map<String, Object?>>? lines;

    if (cheque.isEndorsed == 1) {
      if (newStatus == ChequeStatus.collected) {
        return null;
      }
      if (newStatus == ChequeStatus.returned) {
        final supplierId = int.tryParse(cheque.supplierPid ?? '');
        if (supplierId == null || supplierId <= 0) {
          throw StateError('Returned endorsed cheque requires a supplier.');
        }
        final apId = await _ensureSupplierAp(txn, supplierId);
        final reopen = await _receivedReopenLines(txn, cheque);
        lines = [
          ...reopen,
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
      if (cheque.direction != ChequeDirection.received) {
        throw StateError('Only a received cheque can be collected.');
      }
      final bankId = await _bankAccountForCheque(txn, cheque);
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
    }

    if (lines == null && newStatus == ChequeStatus.cleared) {
      if (cheque.direction != ChequeDirection.issued) {
        throw StateError('Only an issued cheque can be cleared.');
      }
      final bankId = await _bankAccountForCheque(txn, cheque);
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

    if (lines == null &&
        (newStatus == ChequeStatus.returned ||
            newStatus == ChequeStatus.cancelled)) {
      if (cheque.direction == ChequeDirection.received) {
        final reopen = await _receivedReopenLines(txn, cheque);
        lines = [
          ...reopen,
          {
            'account_id': incomingId,
            'debit': 0.0,
            'credit': cheque.amount,
            'cheque_id': cheque.id,
          },
        ];
      } else {
        final restoreId = await _outgoingRestoreAccount(txn, cheque);
        final dimensions = await _paymentDimensionsOnTxn(txn, cheque);
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
            'invoice_id': dimensions['invoice_id'],
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
      final rows = await txn.rawQuery(
        r'''
        SELECT l.account_id
        FROM gl_entries e
        JOIN gl_lines l ON l.entry_id=e.id
        WHERE e.source='VOUCHER'
          AND e.source_id=?
          AND l.debit > 0
        ORDER BY l.id
        LIMIT 1
      ''',
        [cheque.sourceId],
      );

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

    if (cheque.isEndorsed == 1 || current == ChequeStatus.endorsed) {
      final allowed = current == ChequeStatus.endorsed &&
          (next == ChequeStatus.collected || next == ChequeStatus.returned);
      if (!allowed) {
        throw StateError('Endorsed cheque can only be collected or returned.');
      }
      return;
    }

    final receivedTransitions = <ChequeStatus, Set<ChequeStatus>>{
      ChequeStatus.pending: {
        ChequeStatus.held,
        ChequeStatus.deposited,
        ChequeStatus.returned,
        ChequeStatus.cancelled,
      },
      ChequeStatus.received: {
        ChequeStatus.held,
        ChequeStatus.deposited,
        ChequeStatus.returned,
        ChequeStatus.cancelled,
      },
      ChequeStatus.held: {
        ChequeStatus.deposited,
        ChequeStatus.returned,
        ChequeStatus.cancelled,
      },
      ChequeStatus.deposited: {ChequeStatus.collected, ChequeStatus.returned},
    };

    final issuedTransitions = <ChequeStatus, Set<ChequeStatus>>{
      ChequeStatus.pending: {ChequeStatus.delivered, ChequeStatus.cancelled},
      ChequeStatus.issued: {ChequeStatus.delivered, ChequeStatus.cancelled},
      ChequeStatus.delivered: {
        ChequeStatus.presented,
        ChequeStatus.cleared,
        ChequeStatus.returned,
        ChequeStatus.cancelled,
      },
      ChequeStatus.presented: {
        ChequeStatus.cleared,
        ChequeStatus.returned,
        ChequeStatus.cancelled,
      },
    };

    final allowed = cheque.direction == ChequeDirection.received
        ? receivedTransitions
        : issuedTransitions;
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

  static Future<int> _requiredAccount(DatabaseExecutor db, String code) async {
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
            'name':
                supplier.first['name']?.toString() ?? 'Supplier $supplierId',
            'type': 'LIABILITY',
            'normal_balance': 'CREDIT',
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.abort),
    );
  }

  static Future<int> _ensureClientAr(DatabaseExecutor db, int clientId) async {
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
          conflictAlgorithm: ConflictAlgorithm.abort),
    );
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
      (syncTxn) => syncTxn.insert('cheque_events', {
        'cheque_id': chequeId,
        'event_type': type,
        'from_status': fromStatus,
        'to_status': toStatus,
        'event_date': (eventDate ?? DateTime.now()).toIso8601String(),
        'gl_entry_id': glEntryId,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      }),
    );
  }
}
