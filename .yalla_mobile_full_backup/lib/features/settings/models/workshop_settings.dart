// 📁 lib/features/settings/models/workshop_settings.dart
//
// WorkshopSettings — النموذج الكامل الجديد (سجل واحد)
// -----------------------------------------------------
// يشمل:
// - بيانات الورشة: الاسم التجاري، العنوان، الهاتف، المدينة، البريد، الشعار
// - بيانات الدوام: start/end, dailyHours, breakMinutes, weekWorkdays
// - معدلات الرواتب والعقوبات
// -----------------------------------------------------

class WorkshopSettings {
  final int? id; // ثابت 1

  // ==========================
  // بيانات الورشة (للترويسة)
  // ==========================
  final String? workshopName; // اسم الورشة أو الاسم التجاري
  final String? address; // العنوان الكامل
  final String? city; // المدينة / البلد
  final String? phone1; // الهاتف الأساسي
  final String? phone2; // هاتف إضافي
  final String? email; // بريد إلكتروني (اختياري)
  final String? logoPath; // مسار الشعار

  // ==========================
  // إعدادات الدوام
  // ==========================
  final String? workStart; // HH:mm
  final String? workEnd; // HH:mm
  final double? dailyHours; // عدد ساعات الدوام اليومية
  final int? breakMinutes; // الاستراحة بالدقائق
  final String? weekWorkdays; // "1,2,3,4,5,6"

  // ==========================
  // معدلات الرواتب والعقوبات
  // ==========================
  final double? hourlyRate; // سعر الساعة العادي
  final double? overtimeRate; // إضافي
  final double? latePenalty; // خصم التأخير
  final double? earlyLeavePenalty; // خصم المغادرة المبكرة

  const WorkshopSettings({
    this.id,
    this.workshopName,
    this.address,
    this.city,
    this.phone1,
    this.phone2,
    this.email,
    this.logoPath,
    this.workStart,
    this.workEnd,
    this.dailyHours,
    this.breakMinutes,
    this.weekWorkdays,
    this.hourlyRate,
    this.overtimeRate,
    this.latePenalty,
    this.earlyLeavePenalty,
  });

  // ==========================
  // copyWith
  // ==========================
  WorkshopSettings copyWith({
    int? id,
    String? workshopName,
    String? address,
    String? city,
    String? phone1,
    String? phone2,
    String? email,
    String? logoPath,
    String? workStart,
    String? workEnd,
    double? dailyHours,
    int? breakMinutes,
    String? weekWorkdays,
    double? hourlyRate,
    double? overtimeRate,
    double? latePenalty,
    double? earlyLeavePenalty,
  }) {
    return WorkshopSettings(
      id: id ?? this.id,
      workshopName: workshopName ?? this.workshopName,
      address: address ?? this.address,
      city: city ?? this.city,
      phone1: phone1 ?? this.phone1,
      phone2: phone2 ?? this.phone2,
      email: email ?? this.email,
      logoPath: logoPath ?? this.logoPath,
      workStart: workStart ?? this.workStart,
      workEnd: workEnd ?? this.workEnd,
      dailyHours: dailyHours ?? this.dailyHours,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      weekWorkdays: weekWorkdays ?? this.weekWorkdays,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      latePenalty: latePenalty ?? this.latePenalty,
      earlyLeavePenalty: earlyLeavePenalty ?? this.earlyLeavePenalty,
    );
  }

  // ==========================
  // toMap
  // ==========================
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'workshopName': workshopName,
      'address': address,
      'city': city,
      'phone1': phone1,
      'phone2': phone2,
      'email': email,
      'logoPath': logoPath,
      'workStart': workStart,
      'workEnd': workEnd,
      'dailyHours': dailyHours,
      'breakMinutes': breakMinutes,
      'weekWorkdays': weekWorkdays,
      'hourlyRate': hourlyRate,
      'overtimeRate': overtimeRate,
      'latePenalty': latePenalty,
      'earlyLeavePenalty': earlyLeavePenalty,
    };
  }

  // ==========================
  // fromMap
  // ==========================
  factory WorkshopSettings.fromMap(Map<String, Object?> map) {
    double? toD(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

    int? toI(dynamic v) =>
        v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));

    return WorkshopSettings(
      id: toI(map['id']),
      workshopName: map['workshopName'] as String?,
      address: map['address'] as String?,
      city: map['city'] as String?,
      phone1: map['phone1'] as String?,
      phone2: map['phone2'] as String?,
      email: map['email'] as String?,
      logoPath: map['logoPath'] as String?,
      workStart: map['workStart'] as String?,
      workEnd: map['workEnd'] as String?,
      dailyHours: toD(map['dailyHours']),
      breakMinutes: toI(map['breakMinutes']),
      weekWorkdays: map['weekWorkdays'] as String?,
      hourlyRate: toD(map['hourlyRate']),
      overtimeRate: toD(map['overtimeRate']),
      latePenalty: toD(map['latePenalty']),
      earlyLeavePenalty: toD(map['earlyLeavePenalty']),
    );
  }

  // ==========================
  // defaults
  // ==========================
  static WorkshopSettings defaults() => const WorkshopSettings(
        id: 1,
        workStart: '09:00',
        workEnd: '17:00',
        dailyHours: 8.0,
        breakMinutes: 0,
      );
}
