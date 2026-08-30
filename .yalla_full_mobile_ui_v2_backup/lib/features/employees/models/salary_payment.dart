// 📁 lib/features/employees/models/salary_payment.dart

class SalaryPayment {
  final String id;
  final String employeeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double baseSalary;
  final double allowances;
  final double deductions;
  final double advances;
  final double totalPaid;
  final String method; // "نقدي" / "تحويل بنكي" / "شيك"
  final DateTime paymentDate;
  final String? note;

  SalaryPayment({
    required this.id,
    required this.employeeId,
    required this.periodStart,
    required this.periodEnd,
    required this.baseSalary,
    required this.allowances,
    required this.deductions,
    required this.advances,
    required this.totalPaid,
    required this.method,
    required this.paymentDate,
    this.note,
  });

  /// الراتب الصافي قبل الدفع
  double get netSalary => baseSalary + allowances - deductions - advances;

  factory SalaryPayment.fromMap(Map<String, dynamic> map) {
    return SalaryPayment(
      id: map['id'] ?? '',
      employeeId: map['employeeId'] ?? '',
      periodStart:
          DateTime.tryParse(map['periodStart'] ?? '') ?? DateTime.now(),
      periodEnd: DateTime.tryParse(map['periodEnd'] ?? '') ?? DateTime.now(),
      baseSalary: (map['baseSalary'] as num?)?.toDouble() ?? 0.0,
      allowances: (map['allowances'] as num?)?.toDouble() ?? 0.0,
      deductions: (map['deductions'] as num?)?.toDouble() ?? 0.0,
      advances: (map['advances'] as num?)?.toDouble() ?? 0.0,
      totalPaid: (map['totalPaid'] as num?)?.toDouble() ?? 0.0,
      method: map['method'] ?? 'نقدي',
      paymentDate:
          DateTime.tryParse(map['paymentDate'] ?? '') ?? DateTime.now(),
      note: map['note'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'periodStart': periodStart.toIso8601String(),
      'periodEnd': periodEnd.toIso8601String(),
      'baseSalary': baseSalary,
      'allowances': allowances,
      'deductions': deductions,
      'advances': advances,
      'totalPaid': totalPaid,
      'method': method,
      'paymentDate': paymentDate.toIso8601String(),
      'note': note,
    };
  }

  SalaryPayment copyWith({
    String? id,
    String? employeeId,
    DateTime? periodStart,
    DateTime? periodEnd,
    double? baseSalary,
    double? allowances,
    double? deductions,
    double? advances,
    double? totalPaid,
    String? method,
    DateTime? paymentDate,
    String? note,
  }) {
    return SalaryPayment(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      baseSalary: baseSalary ?? this.baseSalary,
      allowances: allowances ?? this.allowances,
      deductions: deductions ?? this.deductions,
      advances: advances ?? this.advances,
      totalPaid: totalPaid ?? this.totalPaid,
      method: method ?? this.method,
      paymentDate: paymentDate ?? this.paymentDate,
      note: note ?? this.note,
    );
  }
}
