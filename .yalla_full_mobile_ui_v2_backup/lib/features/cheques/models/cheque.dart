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
  collection,
}

enum ChequeStatus {
  pending,
  collected,
  returned,
  cancelled,
  delivered,
  deposited,
}

class Cheque {
  final int? id;
  final String uuid;

  final String chequeNo;
  final ChequeType chequeType;
  final ChequeStatus status;

  final String drawerName;
  final String bankName;
  final String bankBranch;

  final double amount;
  final String currency;

  final DateTime issueDate;
  final DateTime dueDate;

  // مصادر الربط
  final String? sourceType;
  final String? sourceId;

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
    required this.status,
    required this.drawerName,
    required this.bankName,
    required this.bankBranch,
    required this.amount,
    required this.currency,
    required this.issueDate,
    required this.dueDate,
    this.sourceType,
    this.sourceId,
    this.supplierPid,
    this.clientId,
    this.recipientType,
    this.recipientId,
    this.recipientName,
    this.glEntryId,
    this.notes,
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
  });

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

    return Cheque(
      id: m['id'] as int?,
      uuid: (m['uuid'] ?? DateTime.now().millisecondsSinceEpoch.toString())
          .toString(),
      chequeNo: (m['cheque_no'] ?? m['number'] ?? '').toString(),
      chequeType: _parseType(m['cheque_type']),
      status: _parseStatus(m['status']),
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
      supplierPid: m['supplier_pid'],
      clientId: m['client_id'] as int?,
      recipientType: m['recipient_type'],
      recipientId: m['recipient_id'],
      recipientName: m['recipient_name'],
      glEntryId: m['gl_entry_id'] as int?,
      notes: m['notes'],
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
      'status': describeEnum(status),
      'drawer_name': drawerName,
      'bank_name': bankName,
      'bank_branch': bankBranch,
      'amount': amount,
      'currency': currency,
      'issue_date': issueDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'source_type': sourceType,
      'source_id': sourceId,
      'supplier_pid': supplierPid,
      'client_id': clientId,
      'recipient_type': recipientType,
      'recipient_id': recipientId,
      'recipient_name': recipientName,
      'gl_entry_id': glEntryId,
      'notes': notes,
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
    ChequeStatus? status,
    String? drawerName,
    String? bankName,
    String? bankBranch,
    double? amount,
    String? currency,
    DateTime? issueDate,
    DateTime? dueDate,
    String? sourceType,
    String? sourceId,
    String? supplierPid,
    int? clientId,
    String? recipientType,
    String? recipientId,
    String? recipientName,
    int? glEntryId,
    String? notes,
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
      status: status ?? this.status,
      drawerName: drawerName ?? this.drawerName,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      supplierPid: supplierPid ?? this.supplierPid,
      clientId: clientId ?? this.clientId,
      recipientType: recipientType ?? this.recipientType,
      recipientId: recipientId ?? this.recipientId,
      recipientName: recipientName ?? this.recipientName,
      glEntryId: glEntryId ?? this.glEntryId,
      notes: notes ?? this.notes,
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

  static ChequeStatus _parseStatus(String? v) {
    switch ((v ?? '').toLowerCase()) {
      case 'pending':
        return ChequeStatus.pending;
      case 'collected':
        return ChequeStatus.collected;
      case 'returned':
        return ChequeStatus.returned;
      case 'cancelled':
        return ChequeStatus.cancelled;
      case 'delivered':
        return ChequeStatus.delivered;
      case 'deposited':
        return ChequeStatus.deposited;
      default:
        return ChequeStatus.pending;
    }
  }
}
