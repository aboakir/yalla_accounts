// 📁 lib/features/finance/models/invoice.dart
//
// Invoice Model — متوافق مع v30/31
// الحقول المدعومة: id, repairId, date, subtotal, vat, total, paid, status, notes, note, method, glEntryId, clientId
// - status داخليًا: "paid" / "partial" / "unpaid"
// - displayStatus عربي للواجهة
// - بدون أي قيم مختلَقة

class Invoice {
  final String id;
  final String repairId;
  final DateTime date;

  /// إن وُجدت في القاعدة. يمكن أن تكون null.
  final double? subtotal;

  /// إن وُجدت في القاعدة. يمكن أن تكون null.
  final double? vat;

  /// الإجمالي كما هو مخزّن في القاعدة.
  final double total;

  /// المبلغ المدفوع كما هو مخزّن في القاعدة.
  final double paid;

  /// internal: paid / partial / unpaid
  final String status;

  /// ملاحظات طويلة إن وُجدت.
  final String? notes;

  /// ملاحظة مختصرة إن وُجدت (حقل note).
  final String? note;

  /// طريقة الدفع المرفقة بالفاتورة إن وُجدت: cash | bank | credit | null
  final String? method;

  /// gl_entries(id) المرتبط بالفاتورة إن تم نشر GL.
  final int? glEntryId;

  /// معرف العميل المرتبط بالإصلاح إن وُجد.
  final int? clientId;

  const Invoice({
    required this.id,
    required this.repairId,
    required this.date,
    required this.total,
    required this.paid,
    required this.status,
    this.subtotal,
    this.vat,
    this.notes,
    this.note,
    this.method,
    this.glEntryId,
    this.clientId,
  });

  double get remaining => total - paid;
  bool get isPaid => status == InvoiceStatus.paid;

  /// للعرض بالعربي
  String get displayStatus {
    switch (status) {
      case InvoiceStatus.paid:
        return 'مسدد';
      case InvoiceStatus.partial:
        return 'مسدد جزئي';
      case InvoiceStatus.unpaid:
      default:
        return 'غير مسدد';
    }
  }

  /// إن كانت subtotal و vat متاحتين، نحسب مجموعهما بدون فرضية على total.
  double? get computedTotalFromParts {
    if (subtotal == null && vat == null) return null;
    final s = (subtotal ?? 0.0);
    final v = (vat ?? 0.0);
    return _round(s + v);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'repair_id': repairId,
        'date': date.toIso8601String(),
        'subtotal': subtotal,
        'vat': vat,
        'total': total,
        'paid': paid,
        'status': status, // internal english
        'notes': notes,
        'note': note,
        'method': method,
        'gl_entry_id': glEntryId,
        'client_id': clientId,
      };

  factory Invoice.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final repairId = map['repair_id']?.toString();
    final rawDate = map['date']?.toString();

    if (id == null || id.isEmpty) {
      throw FormatException('Invoice.fromMap: missing id');
    }
    if (repairId == null || repairId.isEmpty) {
      throw FormatException('Invoice.fromMap: missing repair_id');
    }
    if (rawDate == null || rawDate.isEmpty) {
      throw FormatException('Invoice.fromMap: missing date');
    }

    final parsedDate = DateTime.tryParse(rawDate);
    if (parsedDate == null) {
      throw FormatException('Invoice.fromMap: invalid date "$rawDate"');
    }

    final totalNum = _asDouble(map['total']);
    final paidNum = _asDouble(map['paid']);
    if (totalNum == null) {
      throw FormatException('Invoice.fromMap: missing total');
    }
    if (paidNum == null) {
      throw FormatException('Invoice.fromMap: missing paid');
    }

    final statusRaw = (map['status']?.toString() ?? '').trim();
    final status = InvoiceStatus.isValid(statusRaw)
        ? statusRaw
        : InvoiceStatus.normalize(statusRaw);
    if (!InvoiceStatus.isValid(status)) {
      throw FormatException('Invoice.fromMap: invalid status "$statusRaw"');
    }

    final subtotal = _asDouble(map['subtotal']);
    final vat = _asDouble(map['vat']);

    // اختياريّات إضافية
    final glEntryId = _asInt(map['gl_entry_id']);
    final clientId = _asInt(map['client_id']);

    return Invoice(
      id: id,
      repairId: repairId,
      date: parsedDate,
      subtotal: subtotal,
      vat: vat,
      total: totalNum,
      paid: paidNum,
      status: status,
      notes: map['notes']?.toString(),
      note: map['note']?.toString(),
      method: map['method']?.toString(),
      glEntryId: glEntryId,
      clientId: clientId,
    );
  }

  Invoice copyWith({
    String? id,
    String? repairId,
    DateTime? date,
    double? subtotal,
    double? vat,
    double? total,
    double? paid,
    String? status,
    String? notes,
    String? note,
    String? method,
    int? glEntryId,
    int? clientId,
  }) {
    return Invoice(
      id: id ?? this.id,
      repairId: repairId ?? this.repairId,
      date: date ?? this.date,
      subtotal: subtotal ?? this.subtotal,
      vat: vat ?? this.vat,
      total: total ?? this.total,
      paid: paid ?? this.paid,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      note: note ?? this.note,
      method: method ?? this.method,
      glEntryId: glEntryId ?? this.glEntryId,
      clientId: clientId ?? this.clientId,
    );
  }

  // ===== Helpers =====
  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}

class InvoiceStatus {
  static const String paid = 'paid';
  static const String partial = 'partial';
  static const String unpaid = 'unpaid';

  static bool isValid(String s) => s == paid || s == partial || s == unpaid;

  /// يسمح بمدخلات عربية قديمة ويحوّلها للإنجليزي
  static String normalize(String s) {
    switch (s.trim()) {
      case 'مسدد':
        return paid;
      case 'مسدد جزئي':
        return partial;
      case 'غير مسدد':
        return unpaid;
      default:
        return s.trim().toLowerCase();
    }
  }
}
