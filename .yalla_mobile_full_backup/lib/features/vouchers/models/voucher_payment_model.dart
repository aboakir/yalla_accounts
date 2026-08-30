// -----------------------------------------------------------------------------
// 📁 voucher_payment_model.dart
// نموذج سند ERP موحّد — يدعم:
// PAYMENT / RECEIPT / PURCHASE / EXPENSE / OTHER
// CASH / BANK / CHEQUE / TRANSFER
// يدعم GL + الشيكات + الموردين + الموظفين + العملاء + المشتريات
// -----------------------------------------------------------------------------

class VoucherPayment {
  final String id;

  // نوع السند
  final String voucherType; // PAYMENT | RECEIPT | PURCHASE | EXPENSE | OTHER

  // أرقام السندات
  final String? voucherNumber;
  final String? voucherCode;

  // الطرف
  final String? partyType; // SUPPLIER | EMPLOYEE | CLIENT | EXPENSE | OTHER
  final String? partyId;

  // بيانات مالية
  final double amount;
  final String currency;
  final DateTime date;

  // طريقة الدفع
  final String method; // CASH | BANK | CHEQUE | TRANSFER
  final String? chequeId;

  // مرجع خارجي — فاتورة / إصلاح / إلخ
  final String? reference;
  final String? source;
  final String? sourceId;

  // الربط المحاسبي
  final int? glEntryId;
  final bool isPosted;
  final String? postedBy;
  final String? postedAt;

  // الملاحظات والمرفقات
  final String? notes;
  final String? attachments;

  // الطوابع الزمنية
  final String? createdAt;
  final String? updatedAt;

  const VoucherPayment({
    required this.id,
    required this.voucherType,
    this.voucherNumber,
    this.voucherCode,
    this.partyType,
    this.partyId,
    required this.amount,
    required this.currency,
    required this.date,
    required this.method,
    this.chequeId,
    this.reference,
    this.source,
    this.sourceId,
    this.glEntryId,
    this.isPosted = false,
    this.postedBy,
    this.postedAt,
    this.notes,
    this.attachments,
    this.createdAt,
    this.updatedAt,
  });

  // ---------------------------------------------------------------------------
  // fromMap
  // ---------------------------------------------------------------------------
  factory VoucherPayment.fromMap(Map<String, dynamic> map) {
    final glEntryId = map['gl_entry_id'] is int
        ? map['gl_entry_id'] as int
        : int.tryParse("${map['gl_entry_id'] ?? ''}");

    return VoucherPayment(
      id: map['id'] ?? '',
      voucherType: map['voucher_type'] ?? 'PAYMENT',
      voucherNumber: map['voucher_number'],
      voucherCode: map['voucher_code'],
      partyType: map['party_type'],
      partyId: map['party_id'],
      amount: (map['amount'] is num)
          ? (map['amount'] as num).toDouble()
          : double.tryParse("${map['amount']}") ?? 0.0,
      currency: map['currency'] ?? 'ILS',
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
      method: map['method'] ?? 'CASH',
      chequeId: map['cheque_id']?.toString(),
      reference: map['reference'],
      source: map['source'],
      sourceId: map['source_id'],
      glEntryId: glEntryId,
      // P0.003 — do not trust legacy is_posted as accounting truth.
      // The GL link is synchronized from the authoritative GL.
      isPosted: glEntryId != null && glEntryId != 0,
      postedBy: map['posted_by'],
      postedAt: map['posted_at'],
      notes: map['notes'],
      attachments: map['attachments'],
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
    );
  }

  // ---------------------------------------------------------------------------
  // toMap
  // ---------------------------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucher_type': voucherType,
      'voucher_number': voucherNumber,
      'voucher_code': voucherCode,
      'party_type': partyType,
      'party_id': partyId,
      'amount': amount,
      'currency': currency,
      'date': date.toIso8601String(),
      'method': method,
      'cheque_id': chequeId,
      'reference': reference,
      'source': source,
      'source_id': sourceId,
      'gl_entry_id': glEntryId,
      'is_posted': isPosted ? 1 : 0,
      'posted_by': postedBy,
      'posted_at': postedAt,
      'notes': notes,
      'attachments': attachments,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
    };
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------
  VoucherPayment copyWith({
    String? id,
    String? voucherType,
    String? voucherNumber,
    String? voucherCode,
    String? partyType,
    String? partyId,
    double? amount,
    String? currency,
    DateTime? date,
    String? method,
    String? chequeId,
    String? reference,
    String? source,
    String? sourceId,
    int? glEntryId,
    bool? isPosted,
    String? postedBy,
    String? postedAt,
    String? notes,
    String? attachments,
    String? createdAt,
    String? updatedAt,
  }) {
    return VoucherPayment(
      id: id ?? this.id,
      voucherType: voucherType ?? this.voucherType,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      voucherCode: voucherCode ?? this.voucherCode,
      partyType: partyType ?? this.partyType,
      partyId: partyId ?? this.partyId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      date: date ?? this.date,
      method: method ?? this.method,
      chequeId: chequeId ?? this.chequeId,
      reference: reference ?? this.reference,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      glEntryId: glEntryId ?? this.glEntryId,
      isPosted: isPosted ?? this.isPosted,
      postedBy: postedBy ?? this.postedBy,
      postedAt: postedAt ?? this.postedAt,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
