// 📁 lib/features/employees/providers/employee_provider.dart
//
// Employees Provider — يدعم أنواع التعاقد الأربعة + البحث + الإحصاءات الخفيفة
// - الحالة العامة: قائمة الموظفين + التحميل + الخطأ
// - عمليات CRUD عبر EmployeeDatabaseService
// - مزوّدات إضافية:
//     • employeesByTypeProvider: فلترة حسب نوع التعاقد
//     • employeesSearchProvider: بحث نصي بسيط (الاسم/الكود/المسمى)
//     • employeesCountsProvider: عدادات حسب النوع
//     • employeeByIdProvider: جلب موظف واحد بالمعرّف
// - حضور موظف لفترة: attendanceProvider (بدون تغيير)
//
// ملاحظة: لا بيانات وهمية، كل شيء مبني على قاعدة البيانات الفعلية.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import '../models/attendance.dart';

import '../services/employee_database_service.dart';
import '../services/attendance_database_service.dart';

/// ======================= الحالة العامة | Global State =======================
class EmployeeState {
  final List<Employee> employees;
  final bool isLoading;
  final String? error;

  const EmployeeState({
    this.employees = const [],
    this.isLoading = false,
    this.error,
  });

  bool get isEmpty => employees.isEmpty;
  int get length => employees.length;
  Employee operator [](int index) => employees[index];

  EmployeeState copyWith({
    List<Employee>? employees,
    bool? isLoading,
    String? error,
  }) {
    return EmployeeState(
      employees: employees ?? this.employees,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// ======================== المزود الرئيسي | Main Provider ====================
final employeeProvider =
    StateNotifierProvider<EmployeeNotifier, EmployeeState>((ref) {
  return EmployeeNotifier();
});

/// ======================== المتحكم الرئيسي | Notifier ========================
class EmployeeNotifier extends StateNotifier<EmployeeState> {
  EmployeeNotifier() : super(const EmployeeState()) {
    loadEmployees();
  }

  Future<void> loadEmployees() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await EmployeeDatabaseService.getAllEmployees();
      state = state.copyWith(employees: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> addEmployee(Employee employee) async {
    try {
      await EmployeeDatabaseService.insert(employee);
      await loadEmployees();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateEmployee(Employee employee) async {
    try {
      await EmployeeDatabaseService.update(employee);
      await loadEmployees();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteEmployee(String id) async {
    try {
      await EmployeeDatabaseService.delete(id);
      await loadEmployees();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Employee? findById(String id) {
    try {
      return state.employees.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// ======================== حضور موظف لفترة | Attendance ======================
class AttendanceRequest {
  final String employeeId;
  final DateTime from;
  final DateTime to;

  AttendanceRequest({
    required this.employeeId,
    required this.from,
    required this.to,
  });
}

final attendanceProvider =
    FutureProvider.autoDispose.family<List<Attendance>, AttendanceRequest>(
  (ref, req) async {
    return await AttendanceDatabaseService.getAttendanceForEmployee(
      employeeId: req.employeeId,
      from: req.from,
      to: req.to,
    );
  },
);

/// ===================== مزودات مساعدة | Helper Providers ====================

/// فلترة الموظفين حسب نوع التعاقد (شهري/أسبوعي/مياومة/مقاولة)
// Filter employees by contract type
final employeesByTypeProvider =
    Provider.family<List<Employee>, EmployeeContractType>((ref, type) {
  final state = ref.watch(employeeProvider);
  if (state.isLoading || state.employees.isEmpty) return const [];
  return state.employees.where((e) => e.contractType == type).toList();
});

/// بحث نصي بسيط في الاسم/الكود/المسمى الوظيفي
// Simple text search over fullName / employeeCode / jobTitle
final employeesSearchProvider =
    Provider.family<List<Employee>, String>((ref, query) {
  final state = ref.watch(employeeProvider);
  if (state.isLoading || state.employees.isEmpty) return const [];
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return state.employees;
  return state.employees.where((e) {
    return e.fullName.toLowerCase().contains(q) ||
        e.employeeCode.toLowerCase().contains(q) ||
        e.jobTitle.toLowerCase().contains(q);
  }).toList();
});

/// عدادات حسب النوع (للـ KPI في الشاشة)
// Counts per contract type for KPIs
class EmployeesCounts {
  final int monthly;
  final int weekly;
  final int daily;
  final int contractBased;
  const EmployeesCounts({
    required this.monthly,
    required this.weekly,
    required this.daily,
    required this.contractBased,
  });
}

final employeesCountsProvider = Provider<EmployeesCounts>((ref) {
  final state = ref.watch(employeeProvider);
  if (state.isLoading || state.employees.isEmpty) {
    return const EmployeesCounts(
        monthly: 0, weekly: 0, daily: 0, contractBased: 0);
  }
  int m = 0, w = 0, d = 0, c = 0;
  for (final e in state.employees) {
    switch (e.contractType) {
      case EmployeeContractType.monthly:
        m++;
        break;
      case EmployeeContractType.weekly:
        w++;
        break;
      case EmployeeContractType.daily:
        d++;
        break;
      case EmployeeContractType.contract:
        c++;
        break;
    }
  }
  return EmployeesCounts(monthly: m, weekly: w, daily: d, contractBased: c);
});

/// جلب موظف واحد عبر المعرف (Reactive)
// Single employee by id (reactive)
final employeeByIdProvider = Provider.family<Employee?, String>((ref, id) {
  final state = ref.watch(employeeProvider);
  if (state.isLoading || state.employees.isEmpty) return null;
  try {
    return state.employees.firstWhere((e) => e.id == id);
  } catch (_) {
    return null;
  }
});
