// 📁 lib/features/employees/models/salary.dart
//
// Salary — نموذج موحّد ومتوافق خلفيًا (v29b+)
// يدعم جلب البيانات من جدول salaries الحالي:
// (employeeId, month, employeeName, base, advance, total, paid, due,
//  gl_accrual_id, gl_payment_id, created_at, updated_at)
// وكذلك الشكل الأحدث (snake_case).

class Salary {
  // === الشكل المعتمد حديثًا ===
  final String id; // UUID (TEXT) — اختياري في بعض الجداول
  final String employeeId; // Employee ID
  final String? month; // 'YYYY-MM'
  final DateTime date; // Approval date (fallback الآن)

  final double gross; // إجمالي الراتب
  final double advancesApplied; // سلف مستهلكة ضمن هذا الراتب
  final double deductions; // خصومات أخرى
  final double net; // الصافي

  final double? amountPaid;
  final String status; // 'approved' | 'paid' | 'void'
  final String? note;
  final int? glEntryIdApproval; // قيد الاعتماد
  final int? glEntryIdPayment; // قيد الدفع
  final DateTime? paymentDate; // تاريخ الدفع

  // === حقول اختيارية لدعم شاشات قديمة ===
  final String? employeeName; // للعرض فقط
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Salary({
    required this.id,
    required this.employeeId,
    required this.month,
    required this.date,
    required this.gross,
    required this.advancesApplied,
    required this.deductions,
    required this.net,
    required this.status,
    this.amountPaid,
    this.note,
    this.glEntryIdApproval,
    this.glEntryIdPayment,
    this.paymentDate,
    this.employeeName,
    this.createdAt,
    this.updatedAt,
  });

  // ===== Backward-compat getters =====
  double get base => gross;
  double get advance => advancesApplied;
  double get total => net;
  double get paid => amountPaid ?? (status.toLowerCase() == 'paid' ? net : 0.0);
  double get due => (net - paid).clamp(0.0, double.infinity);

  // ===== Utils =====
  static double _fix2(num x) => double.parse(x.toStringAsFixed(2));

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Salary copyWith({
    String? id,
    String? employeeId,
    String? month,
    DateTime? date,
    double? gross,
    double? advancesApplied,
    double? deductions,
    double? net,
    String? status,
    double? amountPaid,
    String? note,
    int? glEntryIdApproval,
    int? glEntryIdPayment,
    DateTime? paymentDate,
    String? employeeName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Salary(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      month: month ?? this.month,
      date: date ?? this.date,
      gross: gross ?? this.gross,
      advancesApplied: advancesApplied ?? this.advancesApplied,
      deductions: deductions ?? this.deductions,
      net: net ?? this.net,
      status: status ?? this.status,
      amountPaid: amountPaid ?? this.amountPaid,
      note: note ?? this.note,
      glEntryIdApproval: glEntryIdApproval ?? this.glEntryIdApproval,
      glEntryIdPayment: glEntryIdPayment ?? this.glEntryIdPayment,
      paymentDate: paymentDate ?? this.paymentDate,
      employeeName: employeeName ?? this.employeeName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'employee_id': employeeId,
      'month': month,
      'date': date.toIso8601String(),
      'gross': _fix2(gross),
      'advances_applied': _fix2(advancesApplied),
      'deductions': _fix2(deductions),
      'net': _fix2(net),
      'status': status,
      'amount_paid': paid,
      'note': note,
      'gl_entry_id_approval': glEntryIdApproval,
      'gl_entry_id_payment': glEntryIdPayment,
      'payment_date': paymentDate?.toIso8601String(),
      'employee_name': employeeName,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// من خريطة DB. يدعم مفاتيح الجدول الحالي ومفاتيح قديمة/حديثة.
  factory Salary.fromMap(Map<String, Object?> m) {
    double rd(String k) {
      final v = m[k];
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    String rs(String a, [String? b]) {
      final va = m[a];
      if (va != null && va.toString().isNotEmpty) return va.toString();
      if (b != null) {
        final vb = m[b];
        if (vb != null && vb.toString().isNotEmpty) return vb.toString();
      }
      return '';
    }

    DateTime rdt(String k, {DateTime? fallback}) {
      return _parseDate(m[k]) ?? fallback ?? DateTime.now();
    }

    int? ri(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v == null) continue;
        if (v is int) return v;
        if (v is num) return v.toInt();
        final p = int.tryParse(v.toString());
        if (p != null) return p;
      }
      return null;
    }

    // دعم خرائط قديمة: base/advance/total/paid/due
    final legacyBase = rd('base');
    final legacyAdvance = rd('advance');
    final legacyTotal = rd('total');
    final hasLegacy = legacyBase > 0 || legacyAdvance > 0 || legacyTotal > 0;

    final gross = hasLegacy ? legacyBase : rd('gross');
    final advancesApplied = hasLegacy ? legacyAdvance : rd('advances_applied');
    final net = hasLegacy ? legacyTotal : rd('net');

    // GL ids: دعم gl_accrual_id/gl_payment_id بالإضافة للأسماء الحديثة
    final glApproval = ri(['gl_entry_id_approval', 'gl_accrual_id']);
    final glPayment = ri(['gl_entry_id_payment', 'gl_payment_id']);

    // id قد لا يوجد في جدول snapshots الحالي
    final idVal = rs('id');
    final fallbackId = '${rs('employee_id', 'employeeId')}@${m['month'] ?? ''}';

    return Salary(
      id: idVal.isEmpty ? fallbackId : idVal,
      employeeId: rs('employee_id', 'employeeId'),
      month: m['month']?.toString(),
      date:
          rdt('date', fallback: _parseDate(m['created_at']) ?? DateTime.now()),
      gross: gross,
      advancesApplied: advancesApplied,
      deductions: rd('deductions'),
      net: net,
      amountPaid: m['amount_paid'] != null
          ? rd('amount_paid')
          : (m['paid'] != null ? rd('paid') : null),
      status: rs('status').isEmpty ? 'approved' : rs('status'),
      note: m['note']?.toString(),
      glEntryIdApproval: glApproval,
      glEntryIdPayment: glPayment,
      paymentDate: _parseDate(m['payment_date']),
      employeeName: rs('employee_name', 'employeeName'),
      createdAt: _parseDate(m['created_at']),
      updatedAt: _parseDate(m['updated_at']),
    );
  }

  /// خريطة متوافقة مع الشاشات القديمة التي تتوقع base/advance/total/paid/due.
  Map<String, Object?> toLegacyMap() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName ?? '',
      'month': month ?? '',
      'base': _fix2(base),
      'advance': _fix2(advance),
      'total': _fix2(total),
      'paid': _fix2(paid),
      'due': _fix2(due),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  @override
  String toString() =>
      'Salary(id:$id emp:$employeeId month:$month net:$net status:$status)';
}
