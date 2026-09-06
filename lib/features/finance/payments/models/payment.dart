// 📁 lib/features/finance/payments/models/payment.dart
//
// FINAL CLEAN VERSION — بدون party_id نهائيًا
// متوافق 100% مع جدول payments الجديد

class Payment {
  final String id;
  final int? receiptNumber;
  final String? reversalOfPaymentId;

  // دفعات القبض فقط
  final int? clientId;
  final String? repairId;
  final String? invoiceId;

  // ارتباط إضافي للملفات القديمة
  final String? relatedRepairId;

  // المبلغ والتاريخ
  final double amount;
  final DateTime date;

  // وسيلة الدفع
  final String method; // cash / bank / cheque / transfer
  final String? accountName;

  // حالة الدفع
  final String status; // confirmed | pending | cancelled

  // إضافات
  final String? notes;
  final String? attachments;

  // GL Entry
  final int? glEntryId;

  // للسندات المالية "صرف"
  final int? chequeId; // إذا الدفع بشيك
  final bool isIncome; // true = قبض ، false = صرف

  const Payment({
    required this.id,
    this.receiptNumber,
    this.reversalOfPaymentId,
    this.clientId,
    this.repairId,
    this.invoiceId,
    this.relatedRepairId,
    required this.amount,
    required this.date,
    required this.method,
    this.accountName,
    required this.status,
    this.notes,
    this.attachments,
    this.glEntryId,
    this.chequeId,
    required this.isIncome,
  });

  // --------------------------
  // Helpers
  // --------------------------
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime(1970);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.tryParse(v.toString()) ?? DateTime(1970);
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  static String? _str(dynamic v) => v?.toString();

  // --------------------------
  // fromMap
  // --------------------------
  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: _str(map['id']) ?? '',
      receiptNumber: _int(map['receipt_number']),
      reversalOfPaymentId: _str(map['reversal_of_payment_id']),
      clientId: _int(map['client_id']),
      repairId: _str(map['repair_id']),
      invoiceId: _str(map['invoice_id']),
      relatedRepairId: _str(map['relatedRepairId']),
      amount: _toDouble(map['amount']),
      date: _parseDate(map['date']),
      method: _str(map['method']) ?? '',
      accountName: _str(map['accountName']),
      status: _str(map['status']) ?? '',
      notes: _str(map['notes']),
      attachments: _str(map['attachments']),
      glEntryId: _int(map['gl_entry_id']),
      chequeId: _int(map['cheque_id']),
      isIncome: (map['isIncome'] == 1),
    );
  }

  // --------------------------
  // toMap
  // --------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_number': receiptNumber,
      'reversal_of_payment_id': reversalOfPaymentId,
      'client_id': clientId,
      'repair_id': repairId,
      'invoice_id': invoiceId,
      'relatedRepairId': relatedRepairId,
      'amount': amount,
      'date': date.toIso8601String(),
      'method': method,
      'accountName': accountName,
      'status': status,
      'notes': notes,
      'attachments': attachments,
      'gl_entry_id': glEntryId,
      'cheque_id': chequeId,
      'isIncome': isIncome ? 1 : 0,
    };
  }

  Payment copyWith({
    String? id,
    int? receiptNumber,
    String? reversalOfPaymentId,
    int? clientId,
    String? repairId,
    String? invoiceId,
    String? relatedRepairId,
    double? amount,
    DateTime? date,
    String? method,
    String? accountName,
    String? status,
    String? notes,
    String? attachments,
    int? glEntryId,
    int? chequeId,
    bool? isIncome,
  }) {
    return Payment(
      id: id ?? this.id,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      reversalOfPaymentId: reversalOfPaymentId ?? this.reversalOfPaymentId,
      clientId: clientId ?? this.clientId,
      repairId: repairId ?? this.repairId,
      invoiceId: invoiceId ?? this.invoiceId,
      relatedRepairId: relatedRepairId ?? this.relatedRepairId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      method: method ?? this.method,
      accountName: accountName ?? this.accountName,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      glEntryId: glEntryId ?? this.glEntryId,
      chequeId: chequeId ?? this.chequeId,
      isIncome: isIncome ?? this.isIncome,
    );
  }
}
