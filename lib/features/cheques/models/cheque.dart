// 📁 lib/features/cheques/models/cheque.dart
//
// Cheque Model — FINAL + Recipient Support
// -------------------------------------------------------
// • يدعم recipients (WORKSHOP / OWNER / SUPPLIER / EMPLOYEE / OTHER)
// • متوافق 100% مع جدول cheques (v43)
// • يدعم linkedRepairIds + linkedPaymentIds
// • JSON-safe
// -------------------------------------------------------

import 'package:flutter/foundation.dart';
import 'dart:convert';

enum ChequeType {
  incoming,
  outgoing,

  /// Legacy only. Collection is a lifecycle event, never a new direction.
  collection,
}

enum ChequeDirection {
  received,
  issued,
}

enum ChequeStatus {
  /// Legacy pre-v78 status. New records use received/issued.
  pending,
  received,
  held,
  deposited,
  collected,
  endorsed,
  issued,
  delivered,
  presented,
  cleared,
  returned,
  cancelled,
}

class Cheque {
  final int? id;
  final String uuid;

  final String chequeNo;
  final ChequeType chequeType;
  final ChequeDirection direction;
  final ChequeStatus status;

  /// Stable instrument key inside the source voucher. Multiple cheques may
  /// belong to one voucher as long as every instrument key is unique.
  final String? instrumentKey;

  final String drawerName;
  final String bankName;
  final String bankBranch;

  final double amount;
  final String currency;

  final DateTime issueDate;
  final DateTime dueDate;

  // Canonical source/voucher links.
  final String? sourceType;
  final String? sourceId;
  final int? receiptVoucherId;
  final String? paymentVoucherId;
  final String? sourcePartyType;
  final String? sourcePartyId;
  final int? bankAccountId;
  final String? chequeBookId;

  // Supplier (اختياري)
  final String? supplierPid;

  // Client (اختياري)
  final int? clientId;

  // Recipient (NEW)
  final String? recipientType; // WORKSHOP / OWNER / SUPPLIER / EMPLOYEE / OTHER
  final String? recipientId; // ID of the recipient
  final String? recipientName; // الاسم النهائي للطرف المستلم

  // Multi-Payments
  final List<String> linkedPaymentIds;

  // Multi-Repairs
  final List<String> linkedRepairIds;

  // GL
  final int? glEntryId;

  final String? notes;

  final String? createdBy;
  final DateTime? depositedAt;
  final DateTime? collectionDate;
  final DateTime? deliveredAt;
  final DateTime? presentedAt;
  final DateTime? clearedAt;
  final DateTime? returnedAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;

  final DateTime createdAt;
  final DateTime updatedAt;

  final String? originChequeId;
  final int isEndorsed;
  final String? endorsedAt;

  // Endorsement
  final String? lastEndorserName;

  // Auto return
  final DateTime? autoReturnDate;
  final String? returnReason;

  // P0.008 — historical row recovered without original cheque metadata.
  final int isLegacyIncomplete;

  Cheque({
    this.id,
    required this.uuid,
    required this.chequeNo,
    required this.chequeType,
    ChequeDirection? direction,
    required this.status,
    this.instrumentKey,
    required this.drawerName,
    required this.bankName,
    required this.bankBranch,
    required this.amount,
    required this.currency,
    required this.issueDate,
    required this.dueDate,
    this.sourceType,
    this.sourceId,
    this.receiptVoucherId,
    this.paymentVoucherId,
    this.sourcePartyType,
    this.sourcePartyId,
    this.bankAccountId,
    this.chequeBookId,
    this.supplierPid,
    this.clientId,
    this.recipientType,
    this.recipientId,
    this.recipientName,
    this.glEntryId,
    this.notes,
    this.createdBy,
    this.depositedAt,
    this.collectionDate,
    this.deliveredAt,
    this.presentedAt,
    this.clearedAt,
    this.returnedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    required this.createdAt,
    required this.updatedAt,
    this.originChequeId,
    this.isEndorsed = 0,
    this.endorsedAt,
    this.lastEndorserName,
    this.linkedPaymentIds = const [],
    this.linkedRepairIds = const [],
    this.autoReturnDate,
    this.returnReason,
    this.isLegacyIncomplete = 0,
  }) : direction = direction ??
            (chequeType == ChequeType.outgoing
                ? ChequeDirection.issued
                : ChequeDirection.received);

  // -------------------------------------------------------
  // fromMap
  // -------------------------------------------------------
  factory Cheque.fromMap(Map<String, dynamic> m) {
    List<String> repairIds = [];
    List<String> paymentIds = [];

    try {
      final txt = m['linked_repair_ids'];
      if (txt != null && txt.toString().trim().isNotEmpty) {
        repairIds = List<String>.from(json.decode(txt.toString()));
      }
    } catch (_) {}

    try {
      final txt = m['linked_payment_ids'];
      if (txt != null && txt.toString().trim().isNotEmpty) {
        paymentIds = List<String>.from(json.decode(txt.toString()));
      }
    } catch (_) {}

    final type = _parseType(m['cheque_type']);

    return Cheque(
      id: m['id'] as int?,
      uuid: (m['uuid'] ?? DateTime.now().millisecondsSinceEpoch.toString())
          .toString(),
      chequeNo: (m['cheque_no'] ?? m['number'] ?? '').toString(),
      chequeType: type,
      direction: _parseDirection(m['direction'], type),
      status: _parseStatus(m['status'], type),
      instrumentKey: m['instrument_key']?.toString(),
      drawerName: m['drawer_name'] ?? '',
      bankName: (m['bank_name'] ?? m['bank'] ?? '').toString(),
      bankBranch: m['bank_branch'] ?? '',
      amount: double.tryParse((m['amount'] ?? '0').toString()) ?? 0.0,
      currency: m['currency'] ?? 'ILS',
      issueDate: DateTime.tryParse(
            (m['issue_date'] ?? m['date'] ?? m['due_date'] ?? '').toString(),
          ) ??
          DateTime(1970),
      dueDate: DateTime.tryParse(
            (m['due_date'] ?? m['issue_date'] ?? m['date'] ?? '').toString(),
          ) ??
          DateTime(1970),
      sourceType: m['source_type'],
      sourceId: m['source_id'],
      receiptVoucherId: int.tryParse('${m['receipt_voucher_id'] ?? ''}'),
      paymentVoucherId: m['payment_voucher_id']?.toString(),
      sourcePartyType: m['source_party_type']?.toString(),
      sourcePartyId: m['source_party_id']?.toString(),
      bankAccountId: int.tryParse('${m['bank_account_id'] ?? ''}'),
      chequeBookId: m['cheque_book_id']?.toString(),
      supplierPid: m['supplier_pid'],
      clientId: m['client_id'] as int?,
      recipientType: m['recipient_type'],
      recipientId: m['recipient_id'],
      recipientName: m['recipient_name'],
      glEntryId: m['gl_entry_id'] as int?,
      notes: m['notes'],
      createdBy: m['created_by']?.toString(),
      depositedAt: _tryDate(m['deposited_at']),
      collectionDate: _tryDate(m['collection_date']),
      deliveredAt: _tryDate(m['delivered_at']),
      presentedAt: _tryDate(m['presented_at']),
      clearedAt: _tryDate(m['cleared_at']),
      returnedAt: _tryDate(m['returned_at']),
      cancelledAt: _tryDate(m['cancelled_at']),
      cancelledBy: m['cancelled_by']?.toString(),
      cancellationReason: m['cancellation_reason']?.toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()) ??
          DateTime(1970),
      updatedAt: DateTime.tryParse((m['updated_at'] ?? '').toString()) ??
          DateTime(1970),
      originChequeId: (m['origin_cheque_id'] ?? '').toString().isEmpty
          ? null
          : m['origin_cheque_id'].toString(),
      isEndorsed: int.tryParse((m['is_endorsed'] ?? '0').toString()) ?? 0,
      endorsedAt: m['endorsed_at']?.toString(),
      lastEndorserName: m['last_endorser_name'],
      linkedRepairIds: repairIds,
      linkedPaymentIds: paymentIds,
      autoReturnDate: m['auto_return_date'] != null
          ? DateTime.parse(m['auto_return_date'])
          : null,
      returnReason: m['return_reason'],
      isLegacyIncomplete:
          int.tryParse((m['is_legacy_incomplete'] ?? '0').toString()) ?? 0,
    );
  }

  // -------------------------------------------------------
  // toMap
  // -------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'cheque_no': chequeNo,
      'cheque_type': describeEnum(chequeType),
      'direction':
          direction == ChequeDirection.received ? 'RECEIVED' : 'ISSUED',
      'status': describeEnum(status),
      'instrument_key': instrumentKey,
      'drawer_name': drawerName,
      'bank_name': bankName,
      'bank_branch': bankBranch,
      'amount': amount,
      'currency': currency,
      'issue_date': issueDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'source_type': sourceType,
      'source_id': sourceId,
      'receipt_voucher_id': receiptVoucherId,
      'payment_voucher_id': paymentVoucherId,
      'source_party_type': sourcePartyType,
      'source_party_id': sourcePartyId,
      'bank_account_id': bankAccountId,
      'cheque_book_id': chequeBookId,
      'supplier_pid': supplierPid,
      'client_id': clientId,
      'recipient_type': recipientType,
      'recipient_id': recipientId,
      'recipient_name': recipientName,
      'gl_entry_id': glEntryId,
      'notes': notes,
      'created_by': createdBy,
      'deposited_at': depositedAt?.toIso8601String(),
      'collection_date': collectionDate?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'presented_at': presentedAt?.toIso8601String(),
      'cleared_at': clearedAt?.toIso8601String(),
      'returned_at': returnedAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancelled_by': cancelledBy,
      'cancellation_reason': cancellationReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'origin_cheque_id': originChequeId,
      'is_endorsed': isEndorsed,
      'endorsed_at': endorsedAt,
      'last_endorser_name': lastEndorserName,
      'linked_repair_ids': jsonEncode(linkedRepairIds),
      'linked_payment_ids': jsonEncode(linkedPaymentIds),
      'auto_return_date': autoReturnDate?.toIso8601String(),
      'return_reason': returnReason,
      'is_legacy_incomplete': isLegacyIncomplete,
      // Compatibility aliases.
      'number': chequeNo,
      'bank': bankName,
      'date': issueDate.toIso8601String(),
      'supplier_id': int.tryParse(supplierPid ?? ''),
      'payment_id': sourceType?.toUpperCase() == 'PAYMENT' ? sourceId : null,
    };
  }

  // -------------------------------------------------------
  // copyWith
  // -------------------------------------------------------
  Cheque copyWith({
    int? id,
    String? uuid,
    String? chequeNo,
    ChequeType? chequeType,
    ChequeDirection? direction,
    ChequeStatus? status,
    String? instrumentKey,
    String? drawerName,
    String? bankName,
    String? bankBranch,
    double? amount,
    String? currency,
    DateTime? issueDate,
    DateTime? dueDate,
    String? sourceType,
    String? sourceId,
    int? receiptVoucherId,
    String? paymentVoucherId,
    String? sourcePartyType,
    String? sourcePartyId,
    int? bankAccountId,
    String? chequeBookId,
    String? supplierPid,
    int? clientId,
    String? recipientType,
    String? recipientId,
    String? recipientName,
    int? glEntryId,
    String? notes,
    String? createdBy,
    DateTime? depositedAt,
    DateTime? collectionDate,
    DateTime? deliveredAt,
    DateTime? presentedAt,
    DateTime? clearedAt,
    DateTime? returnedAt,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? cancellationReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? originChequeId,
    int? isEndorsed,
    String? endorsedAt,
    String? lastEndorserName,
    List<String>? linkedRepairIds,
    List<String>? linkedPaymentIds,
    DateTime? autoReturnDate,
    String? returnReason,
    int? isLegacyIncomplete,
  }) {
    return Cheque(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      chequeNo: chequeNo ?? this.chequeNo,
      chequeType: chequeType ?? this.chequeType,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      instrumentKey: instrumentKey ?? this.instrumentKey,
      drawerName: drawerName ?? this.drawerName,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      receiptVoucherId: receiptVoucherId ?? this.receiptVoucherId,
      paymentVoucherId: paymentVoucherId ?? this.paymentVoucherId,
      sourcePartyType: sourcePartyType ?? this.sourcePartyType,
      sourcePartyId: sourcePartyId ?? this.sourcePartyId,
      bankAccountId: bankAccountId ?? this.bankAccountId,
      chequeBookId: chequeBookId ?? this.chequeBookId,
      supplierPid: supplierPid ?? this.supplierPid,
      clientId: clientId ?? this.clientId,
      recipientType: recipientType ?? this.recipientType,
      recipientId: recipientId ?? this.recipientId,
      recipientName: recipientName ?? this.recipientName,
      glEntryId: glEntryId ?? this.glEntryId,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      depositedAt: depositedAt ?? this.depositedAt,
      collectionDate: collectionDate ?? this.collectionDate,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      presentedAt: presentedAt ?? this.presentedAt,
      clearedAt: clearedAt ?? this.clearedAt,
      returnedAt: returnedAt ?? this.returnedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      originChequeId: originChequeId ?? this.originChequeId,
      isEndorsed: isEndorsed ?? this.isEndorsed,
      endorsedAt: endorsedAt ?? this.endorsedAt,
      lastEndorserName: lastEndorserName ?? this.lastEndorserName,
      linkedRepairIds: linkedRepairIds ?? this.linkedRepairIds,
      linkedPaymentIds: linkedPaymentIds ?? this.linkedPaymentIds,
      autoReturnDate: autoReturnDate ?? this.autoReturnDate,
      returnReason: returnReason ?? this.returnReason,
      isLegacyIncomplete: isLegacyIncomplete ?? this.isLegacyIncomplete,
    );
  }

  // -------------------------------------------------------
  // Helpers
  // -------------------------------------------------------
  static ChequeType _parseType(String? v) {
    switch ((v ?? '').toLowerCase()) {
      case 'incoming':
        return ChequeType.incoming;
      case 'outgoing':
        return ChequeType.outgoing;
      case 'collection':
        return ChequeType.collection;
      default:
        return ChequeType.outgoing;
    }
  }

  static ChequeDirection _parseDirection(
    Object? value,
    ChequeType type,
  ) {
    final raw = (value ?? '').toString().trim().toUpperCase();
    if (raw == 'RECEIVED') return ChequeDirection.received;
    if (raw == 'ISSUED') return ChequeDirection.issued;
    return type == ChequeType.outgoing
        ? ChequeDirection.issued
        : ChequeDirection.received;
  }

  static ChequeStatus _parseStatus(String? v, ChequeType type) {
    switch ((v ?? '').toLowerCase()) {
      case 'pending':
        return ChequeStatus.pending;
      case 'received':
        return ChequeStatus.received;
      case 'held':
        return ChequeStatus.held;
      case 'deposited':
        return ChequeStatus.deposited;
      case 'collected':
        return ChequeStatus.collected;
      case 'endorsed':
        return ChequeStatus.endorsed;
      case 'issued':
        return ChequeStatus.issued;
      case 'delivered':
        return ChequeStatus.delivered;
      case 'presented':
      case 'due':
        return ChequeStatus.presented;
      case 'cleared':
        return ChequeStatus.cleared;
      case 'returned':
        return ChequeStatus.returned;
      case 'cancelled':
        return ChequeStatus.cancelled;
      default:
        return type == ChequeType.outgoing
            ? ChequeStatus.issued
            : ChequeStatus.received;
    }
  }

  static DateTime? _tryDate(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
