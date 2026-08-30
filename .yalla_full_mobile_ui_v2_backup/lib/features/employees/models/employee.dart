// 📁 lib/features/employees/models/employee.dart
//
// Employee Model — Monthly / Weekly / Daily / Contract
// يدعم snake_case وcamelCase + مفاتيح تراثية. متوافق مع الشاشات الحالية.
// ✅ Backward compatible: baseSalary يُعتبر الراتب الشهري الافتراضي.
// ✅ أنواع التعاقد الأربعة + حقولها الاختيارية.
// ✅ Parsers موحدة + تطبيع طرق الدفع + تقريب مالي.
// ✅ Getters مساعدة لمعرفة نوع التعاقد والسعر الأساس حسب النوع.

import 'package:flutter/foundation.dart';

/// نوع التعاقد Contract Type
enum EmployeeContractType { monthly, weekly, daily, contract }

/// حالة المقاولة Contract Status
enum ContractStatus { newTask, inProgress, ready, approved, paid }

@immutable
class Employee {
  // -------------------- المعلومات الأساسية | Basic Info --------------------
  final String id;
  final String fullName;
  final String employeeCode;
  final String jobTitle;
  final DateTime hireDate;
  final String phone;
  final String email;
  final String address;
  final String status; // active | inactive | terminated

  // -------------------- إعدادات التعاقد | Contract Settings ----------------
  final EmployeeContractType
      contractType; // MONTHLY | WEEKLY | DAILY | CONTRACT
  final double baseSalary; // يُستخدم للـ MONTHLY (متوافق قديمًا)
  final double? weeklyRate; // WEEKLY
  final double? dailyRate; // DAILY
  final double? contractAmount; // CONTRACT fixed fee
  final String? contractDesc; // وصف المهمة
  final DateTime? contractDueDate; // تاريخ التسليم
  final ContractStatus? contractStatus; // حالة المقاولة
  final DateTime? cycleAnchor; // مرجع بدء الأسابيع للأسبوعي

  // -------------------- البيانات المالية العامة | Financial ----------------
  final double allowances;
  final double deductions;
  final double advances;

  // -------------------- الحضور | Attendance -------------------------------
  final int totalWorkDays;
  final double totalHours;
  final int absences;
  final int lateDays;

  // -------------------- ملفات وملاحظات | Files & Notes ---------------------
  final String notes;
  final String? photoUrl;
  final String? contractUrl;

  // -------------------- تواريخ | Dates -------------------------------------
  final DateTime? lastSalaryPaidDate;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // -------------------- دفع وروتين عمل | Payment & Routine -----------------
  final String paymentMethod; // cash | bank | transfer | cheque
  final int workDaysPerWeek; // افتراضي 6
  final int hoursPerDay; // افتراضي 8

  const Employee({
    required this.id,
    required this.fullName,
    required this.employeeCode,
    required this.jobTitle,
    required this.hireDate,
    required this.phone,
    required this.email,
    required this.address,
    required this.status,
    // Contract core
    required this.contractType,
    required this.baseSalary,
    this.weeklyRate,
    this.dailyRate,
    this.contractAmount,
    this.contractDesc,
    this.contractDueDate,
    this.contractStatus,
    this.cycleAnchor,
    // Financial
    required this.allowances,
    required this.deductions,
    required this.advances,
    // Attendance
    required this.totalWorkDays,
    required this.totalHours,
    required this.absences,
    required this.lateDays,
    // Notes/Files
    required this.notes,
    this.photoUrl,
    this.contractUrl,
    // Dates
    this.lastSalaryPaidDate,
    required this.createdAt,
    this.updatedAt,
    // Payment/Routine
    required this.paymentMethod,
    required this.workDaysPerWeek,
    required this.hoursPerDay,
  });

  // -------------------- Helpers | أدوات مساعدة -----------------------------

  // صافي تقديري سريع: Quick net preview
  double get netSalary =>
      baseSalaryForType + allowances - deductions - advances;

  // هل هو نوع محدد؟
  bool get isMonthly => contractType == EmployeeContractType.monthly;
  bool get isWeekly => contractType == EmployeeContractType.weekly;
  bool get isDaily => contractType == EmployeeContractType.daily;
  bool get isContract => contractType == EmployeeContractType.contract;

  // الراتب/الأجر الأساسي حسب النوع (للعرض والحسابات الأولية)
  double get baseSalaryForType {
    if (isWeekly) return (weeklyRate ?? 0.0);
    if (isDaily) return (dailyRate ?? 0.0);
    if (isContract) return (contractAmount ?? 0.0);
    return baseSalary; // monthly
  }

  // ===== Parsers & Normalizers =====
  static double _fix2(num x) => double.parse(x.toStringAsFixed(2));

  static String _rs(Map m, List<String> keys, {String fallback = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return fallback;
  }

  static double _rd(Map m, List<String> keys, {double fallback = 0.0}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final d = double.tryParse(v.toString());
      if (d != null) return d;
    }
    return fallback;
  }

  static double? _rdOrNull(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final d = double.tryParse(v.toString());
      if (d != null) return d;
    }
    return null;
  }

  static int _ri(Map m, List<String> keys, {int fallback = 0}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final i = int.tryParse(v.toString());
      if (i != null) return i;
    }
    return fallback;
  }

  static DateTime _rdt(Map m, List<String> keys, {DateTime? fallback}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is DateTime) return v;
      final d = DateTime.tryParse(v.toString());
      if (d != null) return d;
    }
    return fallback ?? DateTime.now();
  }

  static DateTime? _rdtOrNull(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is DateTime) return v;
      final d = DateTime.tryParse(v.toString());
      if (d != null) return d;
    }
    return null;
  }

  static String _normalizeMethod(String? m) {
    final s = (m ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'cash';
    if (s.contains('bank')) return 'bank';
    if (s.contains('transfer') || s.contains('تحويل')) return 'transfer';
    if (s.contains('cheque') || s.contains('check') || s.contains('شيك')) {
      return 'cheque';
    }
    return 'cash';
  }

  static EmployeeContractType _parseContractType(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.contains('week')) return EmployeeContractType.weekly;
    if (s.contains('day') || s.contains('daily') || s.contains('mya')) {
      return EmployeeContractType.daily;
    }
    if (s.contains('contract') || s.contains('مقاول') || s.contains('مقاولة')) {
      return EmployeeContractType.contract;
    }
    // default monthly
    return EmployeeContractType.monthly;
  }

  static ContractStatus? _parseContractStatus(String? v) {
    if (v == null) return null;
    final s = v.trim().toLowerCase();
    if (s.contains('paid') || s.contains('صرف')) return ContractStatus.paid;
    if (s.contains('approved') || s.contains('اعتماد')) {
      return ContractStatus.approved;
    }
    if (s.contains('ready') || s.contains('جاه')) return ContractStatus.ready;
    if (s.contains('progress') || s.contains('جاري')) {
      return ContractStatus.inProgress;
    }
    if (s.contains('new')) return ContractStatus.newTask;
    return null;
  }

  // -------------------- Clone | نسخة معدّلة -------------------------------
  Employee copyWith({
    String? id,
    String? fullName,
    String? employeeCode,
    String? jobTitle,
    DateTime? hireDate,
    String? phone,
    String? email,
    String? address,
    String? status,
    EmployeeContractType? contractType,
    double? baseSalary,
    double? weeklyRate,
    double? dailyRate,
    double? contractAmount,
    String? contractDesc,
    DateTime? contractDueDate,
    ContractStatus? contractStatus,
    DateTime? cycleAnchor,
    double? allowances,
    double? deductions,
    double? advances,
    int? totalWorkDays,
    double? totalHours,
    int? absences,
    int? lateDays,
    String? notes,
    String? photoUrl,
    String? contractUrl,
    DateTime? lastSalaryPaidDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? paymentMethod,
    int? workDaysPerWeek,
    int? hoursPerDay,
  }) {
    return Employee(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      employeeCode: employeeCode ?? this.employeeCode,
      jobTitle: jobTitle ?? this.jobTitle,
      hireDate: hireDate ?? this.hireDate,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      status: status ?? this.status,
      contractType: contractType ?? this.contractType,
      baseSalary: baseSalary ?? this.baseSalary,
      weeklyRate: weeklyRate ?? this.weeklyRate,
      dailyRate: dailyRate ?? this.dailyRate,
      contractAmount: contractAmount ?? this.contractAmount,
      contractDesc: contractDesc ?? this.contractDesc,
      contractDueDate: contractDueDate ?? this.contractDueDate,
      contractStatus: contractStatus ?? this.contractStatus,
      cycleAnchor: cycleAnchor ?? this.cycleAnchor,
      allowances: allowances ?? this.allowances,
      deductions: deductions ?? this.deductions,
      advances: advances ?? this.advances,
      totalWorkDays: totalWorkDays ?? this.totalWorkDays,
      totalHours: totalHours ?? this.totalHours,
      absences: absences ?? this.absences,
      lateDays: lateDays ?? this.lateDays,
      notes: notes ?? this.notes,
      photoUrl: photoUrl ?? this.photoUrl,
      contractUrl: contractUrl ?? this.contractUrl,
      lastSalaryPaidDate: lastSalaryPaidDate ?? this.lastSalaryPaidDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      workDaysPerWeek: workDaysPerWeek ?? this.workDaysPerWeek,
      hoursPerDay: hoursPerDay ?? this.hoursPerDay,
    );
  }

  // -------------------- fromMap | قراءة -------------------------------
  factory Employee.fromMap(Map<String, dynamic> map) {
    final id = _rs(map, ['id']);
    final fullName = _rs(map, ['full_name', 'fullName', 'name']);
    final employeeCode = _rs(map, ['employee_code', 'employeeCode', 'code']);
    final jobTitle = _rs(map, ['job_title', 'jobTitle']);
    final hireDate =
        _rdt(map, ['hire_date', 'hireDate'], fallback: DateTime.now());

    final phone = _rs(map, ['phone']);
    final email = _rs(map, ['email']);
    final address = _rs(map, ['address']);
    final status = _rs(map, ['status'], fallback: 'active');

    final contractType = _parseContractType(
        _rs(map, ['contract_type', 'contractType'], fallback: 'monthly'));

    final baseSalary = _rd(map, ['base_salary', 'baseSalary', 'salary']);
    final weeklyRate = _rdOrNull(map, ['weekly_rate', 'weeklyRate']);
    final dailyRate = _rdOrNull(map, ['daily_rate', 'dailyRate']);
    final contractAmount =
        _rdOrNull(map, ['contract_amount', 'contractAmount', 'fee']);
    final contractDesc = _rs(map, ['contract_desc', 'contractDesc']);
    final contractDueDate =
        _rdtOrNull(map, ['contract_due_date', 'contractDueDate']);
    final contractStatus =
        _parseContractStatus(_rs(map, ['contract_status', 'contractStatus']));
    final cycleAnchor = _rdtOrNull(map, ['cycle_anchor', 'cycleAnchor']);

    final allowances = _rd(map, ['allowances', 'allowance', 'allow']);
    final deductions = _rd(map, ['deductions', 'deduct']);
    final advances = _rd(map, ['advances', 'advance']);

    final totalWorkDays = _ri(map, ['total_work_days', 'totalWorkDays']);
    final totalHours = _rd(map, ['total_hours', 'totalHours']);
    final absences = _ri(map, ['absences']);
    final lateDays = _ri(map, ['late_days', 'lateDays']);

    final notes = _rs(map, ['notes', 'note']);
    final photoUrl =
        map['photo_url']?.toString() ?? map['photoUrl']?.toString();
    final contractUrl =
        map['contract_url']?.toString() ?? map['contractUrl']?.toString();

    final lastSalaryPaidDate =
        _rdtOrNull(map, ['last_salary_paid_date', 'lastSalaryPaidDate']);

    final createdAt =
        _rdt(map, ['created_at', 'createdAt'], fallback: DateTime.now());
    final updatedAt = _rdtOrNull(map, ['updated_at', 'updatedAt']);

    final paymentMethod = _normalizeMethod(
        _rs(map, ['payment_method', 'paymentMethod'], fallback: 'cash'));

    final workDaysPerWeek =
        _ri(map, ['work_days_per_week', 'workDaysPerWeek'], fallback: 6);
    final hoursPerDay = _ri(map, ['hours_per_day', 'hoursPerDay'], fallback: 8);

    return Employee(
      id: id,
      fullName: fullName,
      employeeCode: employeeCode,
      jobTitle: jobTitle,
      hireDate: hireDate,
      phone: phone,
      email: email,
      address: address,
      status: status,
      contractType: contractType,
      baseSalary: baseSalary,
      weeklyRate: weeklyRate,
      dailyRate: dailyRate,
      contractAmount: contractAmount,
      contractDesc: contractDesc,
      contractDueDate: contractDueDate,
      contractStatus: contractStatus,
      cycleAnchor: cycleAnchor,
      allowances: allowances,
      deductions: deductions,
      advances: advances,
      totalWorkDays: totalWorkDays,
      totalHours: totalHours,
      absences: absences,
      lateDays: lateDays,
      notes: notes,
      photoUrl: photoUrl,
      contractUrl: contractUrl,
      lastSalaryPaidDate: lastSalaryPaidDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      paymentMethod: paymentMethod,
      workDaysPerWeek: workDaysPerWeek,
      hoursPerDay: hoursPerDay,
    );
  }

  // -------------------- toMap | كتابة -------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'employee_code': employeeCode,
      'job_title': jobTitle,
      'hire_date': hireDate.toIso8601String(),
      'phone': phone,
      'email': email,
      'address': address,
      'status': status,
      'contract_type': contractType.name, // monthly/weekly/daily/contract
      'base_salary': _fix2(baseSalary),
      'weekly_rate': weeklyRate == null ? null : _fix2(weeklyRate!),
      'daily_rate': dailyRate == null ? null : _fix2(dailyRate!),
      'contract_amount': contractAmount == null ? null : _fix2(contractAmount!),
      'contract_desc': contractDesc,
      'contract_due_date': contractDueDate?.toIso8601String(),
      'contract_status': contractStatus?.name,
      'cycle_anchor': cycleAnchor?.toIso8601String(),
      'allowances': _fix2(allowances),
      'deductions': _fix2(deductions),
      'advances': _fix2(advances),
      'total_work_days': totalWorkDays,
      'total_hours': double.parse(totalHours.toString()),
      'absences': absences,
      'late_days': lateDays,
      'notes': notes,
      'photo_url': photoUrl,
      'contract_url': contractUrl,
      'last_salary_paid_date': lastSalaryPaidDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'payment_method': paymentMethod,
      'work_days_per_week': workDaysPerWeek,
      'hours_per_day': hoursPerDay,
    };
  }

  @override
  String toString() =>
      'Employee(id:$id, name:$fullName, type:${contractType.name}, base:${_fix2(baseSalaryForType)})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Employee &&
        other.id == id &&
        other.fullName == fullName &&
        other.employeeCode == employeeCode &&
        other.jobTitle == jobTitle &&
        other.hireDate == hireDate &&
        other.phone == phone &&
        other.email == email &&
        other.address == address &&
        other.status == status &&
        other.contractType == contractType &&
        other.baseSalary == baseSalary &&
        other.weeklyRate == weeklyRate &&
        other.dailyRate == dailyRate &&
        other.contractAmount == contractAmount &&
        other.contractDesc == contractDesc &&
        other.contractDueDate == contractDueDate &&
        other.contractStatus == contractStatus &&
        other.cycleAnchor == cycleAnchor &&
        other.allowances == allowances &&
        other.deductions == deductions &&
        other.advances == advances &&
        other.totalWorkDays == totalWorkDays &&
        other.totalHours == totalHours &&
        other.absences == absences &&
        other.lateDays == lateDays &&
        other.notes == notes &&
        other.photoUrl == photoUrl &&
        other.contractUrl == contractUrl &&
        other.lastSalaryPaidDate == lastSalaryPaidDate &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.paymentMethod == paymentMethod &&
        other.workDaysPerWeek == workDaysPerWeek &&
        other.hoursPerDay == hoursPerDay;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      fullName.hashCode ^
      employeeCode.hashCode ^
      jobTitle.hashCode ^
      hireDate.hashCode ^
      phone.hashCode ^
      email.hashCode ^
      address.hashCode ^
      status.hashCode ^
      contractType.hashCode ^
      baseSalary.hashCode ^
      (weeklyRate?.hashCode ?? 0) ^
      (dailyRate?.hashCode ?? 0) ^
      (contractAmount?.hashCode ?? 0) ^
      (contractDesc?.hashCode ?? 0) ^
      (contractDueDate?.hashCode ?? 0) ^
      (contractStatus?.hashCode ?? 0) ^
      (cycleAnchor?.hashCode ?? 0) ^
      allowances.hashCode ^
      deductions.hashCode ^
      advances.hashCode ^
      totalWorkDays.hashCode ^
      totalHours.hashCode ^
      absences.hashCode ^
      lateDays.hashCode ^
      notes.hashCode ^
      (photoUrl?.hashCode ?? 0) ^
      (contractUrl?.hashCode ?? 0) ^
      (lastSalaryPaidDate?.hashCode ?? 0) ^
      createdAt.hashCode ^
      (updatedAt?.hashCode ?? 0) ^
      paymentMethod.hashCode ^
      workDaysPerWeek.hashCode ^
      hoursPerDay.hashCode;
}
