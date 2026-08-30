// 📁 lib/features/employees/providers/employee_form_provider.dart
//
// EmployeeFormProvider — يدعم 4 أنماط تعاقد: شهري/أسبوعي/مياومة/مقاولة
// - حقول ديناميكية حسب النوع (weeklyRate/dailyRate/contractAmount/...)
// - حساب صافي معاينة يعتمد على النوع الحالي (baseForType + allowances - deductions)
// - تحميل/حفظ متوافق مع EmployeeDatabaseService و Employee model المحدث
// - نسخ صورة الموظف إلى مجلد app docs/employee_images
//
// ملاحظات:
// - لا بيانات وهمية. الحقول الافتراضية آمنة فقط.
// - التحقق validation حساس للنوع. يمنع الحفظ إذا نقص أساس الدفع حسب النوع.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/employee.dart';
import '../services/employee_database_service.dart';

class EmployeeFormData {
  // معرف
  String id;

  // أساسي
  String fullName;
  String employeeCode;
  String jobTitle;
  DateTime hireDate;
  String phone;
  String email;
  String status; // نشط/موقوف/منتهي
  String paymentMethod; // cash/bank/transfer/cheque
  String notes;

  // الروتين
  int hoursPerDay;
  int workDaysPerWeek;
  String shiftType; // صباحي/مسائي ... (احتياطي للواجهة)

  // نوع التعاقد
  EmployeeContractType contractType;

  // أساس الأجر حسب النوع
  double baseSalary; // شهري
  double? weeklyRate; // أسبوعي
  double? dailyRate; // مياومة
  double? contractAmount; // مقاولة
  String? contractDesc; // وصف المهمة
  DateTime? contractDueDate;
  ContractStatus? contractStatus;
  DateTime? cycleAnchor; // مرجع بدء الأسابيع للأسبوعي

  // المالي العام
  double advances; // سلف مستحقة التطبيق
  double allowances; // بدلات
  double deductions; // خصومات
  double netSalary; // معاينة سريعة (غير مُرحّلة)

  // مرفقات
  String? imagePath;

  EmployeeFormData({
    String? id,
    // أساسي
    this.fullName = '',
    this.employeeCode = '',
    this.jobTitle = '',
    DateTime? hireDate,
    this.phone = '',
    this.email = '',
    this.status = 'نشط',
    this.paymentMethod = 'cash',
    this.notes = '',
    // الروتين
    this.hoursPerDay = 8,
    this.workDaysPerWeek = 6,
    this.shiftType = 'صباحي',
    // النوع
    this.contractType = EmployeeContractType.monthly,
    // أساس الأجر
    this.baseSalary = 0.0,
    this.weeklyRate,
    this.dailyRate,
    this.contractAmount,
    this.contractDesc,
    this.contractDueDate,
    this.contractStatus,
    this.cycleAnchor,
    // المالي العام
    this.advances = 0.0,
    this.allowances = 0.0,
    this.deductions = 0.0,
    double? netSalary,
    // مرفقات
    this.imagePath,
  })  : id = id ?? const Uuid().v4(),
        hireDate = hireDate ?? DateTime.now(),
        netSalary = netSalary ?? 0.0;

  // Getters قديمة لتوافق واجهات محتملة
  String get idNumber => employeeCode;
  double get salary => baseSalary;

  // أساس النوع الحالي للمعاينة
  double get baseForType {
    switch (contractType) {
      case EmployeeContractType.weekly:
        return (weeklyRate ?? 0.0);
      case EmployeeContractType.daily:
        return (dailyRate ?? 0.0);
      case EmployeeContractType.contract:
        return (contractAmount ?? 0.0);
      case EmployeeContractType.monthly:
      return baseSalary;
    }
  }

  EmployeeFormData copyWith({
    String? id,
    String? fullName,
    String? employeeCode,
    String? jobTitle,
    DateTime? hireDate,
    String? phone,
    String? email,
    String? status,
    String? paymentMethod,
    String? notes,
    int? hoursPerDay,
    int? workDaysPerWeek,
    String? shiftType,
    EmployeeContractType? contractType,
    double? baseSalary,
    double? weeklyRate,
    double? dailyRate,
    double? contractAmount,
    String? contractDesc,
    DateTime? contractDueDate,
    ContractStatus? contractStatus,
    DateTime? cycleAnchor,
    double? advances,
    double? allowances,
    double? deductions,
    double? netSalary,
    String? imagePath,
  }) {
    return EmployeeFormData(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      employeeCode: employeeCode ?? this.employeeCode,
      jobTitle: jobTitle ?? this.jobTitle,
      hireDate: hireDate ?? this.hireDate,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      hoursPerDay: hoursPerDay ?? this.hoursPerDay,
      workDaysPerWeek: workDaysPerWeek ?? this.workDaysPerWeek,
      shiftType: shiftType ?? this.shiftType,
      contractType: contractType ?? this.contractType,
      baseSalary: baseSalary ?? this.baseSalary,
      weeklyRate: weeklyRate ?? this.weeklyRate,
      dailyRate: dailyRate ?? this.dailyRate,
      contractAmount: contractAmount ?? this.contractAmount,
      contractDesc: contractDesc ?? this.contractDesc,
      contractDueDate: contractDueDate ?? this.contractDueDate,
      contractStatus: contractStatus ?? this.contractStatus,
      cycleAnchor: cycleAnchor ?? this.cycleAnchor,
      advances: advances ?? this.advances,
      allowances: allowances ?? this.allowances,
      deductions: deductions ?? this.deductions,
      netSalary: netSalary ?? this.netSalary,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  // تحويل إلى كائن Employee (متوافق مع الموديل المحدث)
  Employee toEmployee() {
    return Employee(
      id: id,
      fullName: fullName,
      employeeCode: employeeCode,
      jobTitle: jobTitle,
      hireDate: hireDate,
      phone: phone,
      email: email,
      address: '', // لم تزود حاليًا من الواجهة
      status: _normalizeStatus(status),
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
      totalWorkDays: 0,
      totalHours: 0,
      absences: 0,
      lateDays: 0,
      notes: notes,
      photoUrl: imagePath,
      contractUrl: null,
      lastSalaryPaidDate: null,
      createdAt: DateTime.now(),
      updatedAt: null,
      paymentMethod: _normalizeMethod(paymentMethod),
      workDaysPerWeek: workDaysPerWeek,
      hoursPerDay: hoursPerDay,
    );
  }

  // تطبيع
  String _normalizeStatus(String s) {
    final v = s.trim().toLowerCase();
    if (v.contains('inactive') || v.contains('موقوف')) return 'inactive';
    if (v.contains('terminated') || v.contains('منتهي')) return 'terminated';
    return 'active';
  }

  String _normalizeMethod(String? m) {
    final s = (m ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'cash';
    if (s.contains('bank') || s.contains('بنك')) return 'bank';
    if (s.contains('transfer') || s.contains('تحويل')) return 'transfer';
    if (s.contains('cheque') || s.contains('check') || s.contains('شيك')) {
      return 'cheque';
    }
    return 'cash';
  }
}

class EmployeeFormNotifier extends StateNotifier<EmployeeFormData> {
  EmployeeFormNotifier() : super(EmployeeFormData());

  // ===== تحديثات عامة =====
  void updateFullName(String v) => state = state.copyWith(fullName: v);
  void updateEmployeeCode(String v) => state = state.copyWith(employeeCode: v);
  void updateJobTitle(String v) => state = state.copyWith(jobTitle: v);
  void updateHireDate(DateTime v) => state = state.copyWith(hireDate: v);
  void updatePhone(String v) => state = state.copyWith(phone: v);
  void updateEmail(String v) => state = state.copyWith(email: v);
  void updateStatus(String v) => state = state.copyWith(status: v);
  void updatePaymentMethod(String v) =>
      state = state.copyWith(paymentMethod: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);

  // روتين العمل
  void updateShiftType(String v) => state = state.copyWith(shiftType: v);
  void updateHoursPerDay(int v) => state = state.copyWith(hoursPerDay: v);
  void updateWorkDaysPerWeek(int v) =>
      state = state.copyWith(workDaysPerWeek: v);

  // النوع
  void updateContractType(EmployeeContractType t) {
    state = state.copyWith(contractType: t);
    // تحديث الصافي للمعاينة
    updateNetSalary();
  }

  // أساس الأجر حسب النوع
  void updateBaseSalary(double v) {
    state = state.copyWith(baseSalary: v);
    updateNetSalary();
  }

  void updateWeeklyRate(double? v) {
    state = state.copyWith(weeklyRate: v);
    updateNetSalary();
  }

  void updateDailyRate(double? v) {
    state = state.copyWith(dailyRate: v);
    updateNetSalary();
  }

  void updateContractAmount(double? v) {
    state = state.copyWith(contractAmount: v);
    updateNetSalary();
  }

  void updateContractDesc(String? v) => state = state.copyWith(contractDesc: v);

  void updateContractDueDate(DateTime? v) =>
      state = state.copyWith(contractDueDate: v);

  void updateContractStatus(ContractStatus? st) =>
      state = state.copyWith(contractStatus: st);

  void updateCycleAnchor(DateTime? v) => state = state.copyWith(cycleAnchor: v);

  // المالي العام
  void updateAdvances(double v) {
    state = state.copyWith(advances: v);
    updateNetSalary();
  }

  void updateAllowances(double v) {
    state = state.copyWith(allowances: v);
    updateNetSalary();
  }

  void updateDeductions(double v) {
    state = state.copyWith(deductions: v);
    updateNetSalary();
  }

  // الصافي للمعاينة
  void updateNetSalary() {
    final base = state.baseForType;
    final net = base + state.allowances - state.deductions - state.advances;
    state = state.copyWith(netSalary: net);
  }

  // صورة
  void updateImage(String? path) => state = state.copyWith(imagePath: path);
  void removeImage() => state = state.copyWith(imagePath: null);

  // توافق قديم
  void updateIdNumber(String text) => updateEmployeeCode(text);
  void updateSalary(double salary) => updateBaseSalary(salary);

  // إعادة تعيين
  void resetForm() => state = EmployeeFormData();

  // تحميل موظف للتعديل
  void loadEmployee(Employee e) {
    state = EmployeeFormData(
      id: e.id,
      fullName: e.fullName,
      employeeCode: e.employeeCode,
      jobTitle: e.jobTitle,
      hireDate: e.hireDate,
      phone: e.phone,
      email: e.email,
      status: e.status,
      paymentMethod: e.paymentMethod,
      notes: e.notes,
      hoursPerDay: e.hoursPerDay,
      workDaysPerWeek: e.workDaysPerWeek,
      // النوع
      contractType: e.contractType,
      baseSalary: e.baseSalary,
      weeklyRate: e.weeklyRate,
      dailyRate: e.dailyRate,
      contractAmount: e.contractAmount,
      contractDesc: e.contractDesc,
      contractDueDate: e.contractDueDate,
      contractStatus: e.contractStatus,
      cycleAnchor: e.cycleAnchor,
      // المالي
      advances: e.advances,
      allowances: e.allowances,
      deductions: e.deductions,
      // مرفقات
      imagePath: e.photoUrl,
      // الصافي معاينة
      netSalary: e.baseSalaryForType + e.allowances - e.deductions - e.advances,
    );
  }

  // حفظ صورة ضمن مجلد التطبيق
  Future<String?> _saveImage(String? imagePath) async {
    if (imagePath == null) return null;
    try {
      final original = File(imagePath);
      if (await original.exists()) {
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(p.join(appDir.path, 'employee_images'));
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        final fileName = '${const Uuid().v4()}${p.extension(original.path)}';
        final newPath = p.join(imagesDir.path, fileName);
        await original.copy(newPath);
        debugPrint('📁 تم نسخ صورة الموظف إلى $newPath');
        return newPath;
      }
    } catch (e) {
      debugPrint('❌ خطأ في حفظ الصورة: $e');
    }
    return null;
  }

  // حفظ موظف جديد
  Future<bool> saveEmployee() async {
    try {
      debugPrint('📝 حفظ الموظف بدأ...');
      if (!_validateRequired()) return false;

      // حفظ الصورة إن وُجدت
      final savedImagePath = await _saveImage(state.imagePath);

      // بناء Employee
      final employee = state.toEmployee().copyWith(photoUrl: savedImagePath);

      await EmployeeDatabaseService.insert(employee);
      debugPrint('✅ تم الحفظ في قاعدة البيانات');

      resetForm();
      return true;
    } catch (e) {
      debugPrint('❌ فشل حفظ الموظف: $e');
      return false;
    }
  }

  // تحديث موظف قائم
  Future<bool> updateEmployee() async {
    try {
      debugPrint('📝 تحديث الموظف بدأ...');
      if (!_validateRequired()) return false;

      final savedImagePath = await _saveImage(state.imagePath);

      final updatedEmployee = state.toEmployee().copyWith(
            photoUrl: savedImagePath,
            updatedAt: DateTime.now(),
          );

      await EmployeeDatabaseService.update(updatedEmployee);
      debugPrint('✅ تم التحديث');
      return true;
    } catch (e) {
      debugPrint('❌ فشل تحديث الموظف: $e');
      return false;
    }
  }

  // تحقق أساسي عام + تحقق خاص بالنوع
  bool _validateRequired() {
    if (state.fullName.trim().isEmpty) {
      debugPrint('❌ الاسم الكامل مطلوب');
      return false;
    }
    if (state.employeeCode.trim().isEmpty) {
      debugPrint('❌ كود الموظف مطلوب');
      return false;
    }

    switch (state.contractType) {
      case EmployeeContractType.monthly:
        if (state.baseSalary < 0) {
          debugPrint('❌ الراتب الشهري غير صالح');
          return false;
        }
        break;
      case EmployeeContractType.weekly:
        if ((state.weeklyRate ?? -1) < 0) {
          debugPrint('❌ الأجر الأسبوعي غير صالح');
          return false;
        }
        break;
      case EmployeeContractType.daily:
        if ((state.dailyRate ?? -1) < 0) {
          debugPrint('❌ الأجر اليومي غير صالح');
          return false;
        }
        break;
      case EmployeeContractType.contract:
        if ((state.contractAmount ?? -1) < 0) {
          debugPrint('❌ قيمة المقاولة غير صالحة');
          return false;
        }
        break;
    }
    return true;
  }

  // تحقق مختصر للواجهات
  bool validateForm() => _validateRequired();

  // صافي معاينة بسيط
  double calculateNetSalary() {
    final base = state.baseForType;
    return base + state.allowances - state.deductions - state.advances;
  }
}

// Provider الرئيسي
final employeeFormProvider =
    StateNotifierProvider<EmployeeFormNotifier, EmployeeFormData>(
  (ref) => EmployeeFormNotifier(),
);

// Validators مساعدة
final employeeFormValidatorProvider = Provider<bool>((ref) {
  final s = ref.watch(employeeFormProvider);
  // مختصر: الاسم + الكود + أساس النوع
  if (s.fullName.trim().isEmpty || s.employeeCode.trim().isEmpty) return false;
  switch (s.contractType) {
    case EmployeeContractType.monthly:
      return s.baseSalary >= 0;
    case EmployeeContractType.weekly:
      return (s.weeklyRate ?? -1) >= 0;
    case EmployeeContractType.daily:
      return (s.dailyRate ?? -1) >= 0;
    case EmployeeContractType.contract:
      return (s.contractAmount ?? -1) >= 0;
  }
});

// صافي المعاينة
final employeeNetSalaryProvider = Provider<double>((ref) {
  final s = ref.watch(employeeFormProvider);
  return s.baseForType + s.allowances - s.deductions - s.advances;
});
