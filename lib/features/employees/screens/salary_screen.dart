// 📁 lib/features/employees/screens/salary_screen.dart
//
// SalaryScreen — إدارة رواتب شهرية + GL
// - Snapshot شهري من الحضور.
// - قفل/فتح شهر الرواتب.
// - إثبات/صرف/عكس رواتب مع GL.
// - حماية Dropdown طريقة الدفع من التكرار أو قيمة غير موجودة.
// - السايدبار يمين دائمًا بدون استخدام RTL أو LTR.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/employees/models/salary.dart';
import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';
import 'package:yalla_accounts/features/employees/providers/salary_provider.dart';

// Services
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/services/salary_database_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';

// Settings
import 'package:yalla_accounts/features/settings/providers/workshop_settings_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class SalaryScreen extends ConsumerStatefulWidget {
  const SalaryScreen({super.key});

  @override
  ConsumerState<SalaryScreen> createState() => _SalaryScreenState();
}

class _SalaryScreenState extends ConsumerState<SalaryScreen> {
  DateTime _selectedMonth = DateTime.now();
  String _searchQuery = '';

  final Map<String, double> _netByEmployee = {};
  bool _calculating = false;
  String? _calcError;

  bool _isLocked = false;
  bool _togglingLock = false;

  // ===== Helpers =====
  String _monthKey() => DateFormat('yyyy-MM', 'en').format(_selectedMonth);
  String _snapId(String empId, String monthKey) => 'SNAP-$empId-$monthKey';
  DateTime _periodDate() =>
      DateTime(_selectedMonth.year, _selectedMonth.month, 1);

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  Future<void> _reloadAll() async {
    await _recalcAll();
    await _refreshLockFlag();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2022, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'اختر شهر الراتب',
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
      await _reloadAll();
    }
  }

  Future<void> _refreshLockFlag() async {
    final y = _selectedMonth.year;
    final m = _selectedMonth.month;
    final locked = await PayrollPeriodsService.isLocked(y, m);
    if (mounted) setState(() => _isLocked = locked);
  }

  Future<void> _toggleLock() async {
    if (_togglingLock) return;
    setState(() => _togglingLock = true);
    try {
      final y = _selectedMonth.year;
      final m = _selectedMonth.month;
      if (_isLocked) {
        await PayrollPeriodsService.unlockPeriod(y, m);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم فتح الشهر')),
        );
      } else {
        await PayrollPeriodsService.lockPeriod(y, m);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم قفل الشهر')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تبديل القفل: $e')),
      );
    } finally {
      await _refreshLockFlag();
      if (mounted) setState(() => _togglingLock = false);
    }
  }

  Future<void> _recalcAll() async {
    setState(() {
      _calculating = true;
      _calcError = null;
      _netByEmployee.clear();
    });

    try {
      final empState = ref.read(employeeProvider);
      final employees = empState.employees;

      final from = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final to = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final totalDaysInMonth = to.difference(from).inDays + 1;
      final monthKey = _monthKey();

      for (final employee in employees) {
        final attendanceRecords =
            await AttendanceDatabaseService.getAttendanceForEmployee(
          employeeId: employee.id,
          from: from,
          to: to,
        );

        await ref.read(salaryProvider.notifier).calculateSalaryFromAttendance(
              employeeId: employee.id,
              baseSalary: employee.baseSalary,
              totalWorkDaysInMonth: totalDaysInMonth,
              attendanceRecords: attendanceRecords,
            );

        final netSalary =
            ref.read(salaryProvider.notifier).getSalary(employee.id);

        await SalaryDatabaseService.upsertSalary(
          Salary(
            id: _snapId(employee.id, monthKey),
            employeeId: employee.id,
            month: monthKey,
            date: _periodDate(),
            gross: netSalary,
            advancesApplied: 0.0,
            deductions: 0.0,
            net: netSalary,
            status: 'approved',
            note: 'Attendance snapshot',
            employeeName: employee.fullName,
          ),
        );

        _netByEmployee[employee.id] = netSalary;
      }
    } catch (e) {
      _calcError = e.toString();
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _postAccrualForEmployee({
    required String employeeId,
    required String employeeName,
    required double amount,
  }) async {
    try {
      await SalaryDatabaseService.postMonthlyAccrual(
        employeeId: employeeId,
        employeeName: employeeName,
        month: _monthKey(),
        amount: amount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم إثبات راتب $employeeName لشهر ${_monthKey()}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الإثبات: $e')),
      );
    }
  }

  Future<void> _reverseAccrualForEmployee({required String employeeId}) async {
    try {
      await SalaryDatabaseService.reverseAccrual(
        employeeId: employeeId,
        month: _monthKey(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم عكس قيد الإثبات')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل عكس الإثبات: $e')),
      );
    }
  }

  // ===== Payment =====
  String _normalizeMethod(String? v) => (v ?? 'cash').toLowerCase().trim();

  T? _safeValue<T>(T? v, List<DropdownMenuItem<T>> items) {
    if (v == null) return null;
    final count = items.where((e) => e.value == v).length;
    if (count == 1) return v;
    return null;
  }

  Future<void> _paySalaryForEmployee({
    required String employeeId,
    required String employeeName,
  }) async {
    final controller = TextEditingController(
      text: (_netByEmployee[employeeId] ?? 0).toStringAsFixed(2),
    );

    final raw = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'cash', child: Text('نقدي')),
      const DropdownMenuItem(value: 'bank', child: Text('بنك')),
      const DropdownMenuItem(value: 'cheque', child: Text('شيك')),
      const DropdownMenuItem(value: 'transfer', child: Text('تحويل')),
    ];
    final methodItems =
        {for (final it in raw) it.value!: it}.values.toList(growable: false);

    String method = 'cash';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('صرف راتب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ',
                prefixText: '${MoneyFormatter.symbol} ',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _safeValue(method, methodItems),
              items: methodItems,
              onChanged: (v) => method = _normalizeMethod(v),
              decoration: InputDecoration(labelText: 'طريقة الدفع'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('صرف')),
        ],
      ),
    );

    if (ok != true) return;

    final amount = double.tryParse(controller.text.trim()) ?? 0.0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ غير صالح')),
      );
      return;
    }

    await SalaryDatabaseService.paySalary(
      employeeId: employeeId,
      employeeName: employeeName,
      month: _monthKey(),
      amount: amount,
      method: _normalizeMethod(method),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم صرف الراتب وربط GL')),
    );
  }

  Future<void> _reversePaymentForEmployee({required String employeeId}) async {
    try {
      await SalaryDatabaseService.reversePayment(
        employeeId: employeeId,
        month: _monthKey(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم عكس قيد الصرف')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل عكس الصرف: $e')),
      );
    }
  }

  // ===== Sidebar on mobile: custom right panel =====
  Future<void> _openSidebarPanel() async {
    await showGeneralDialog(
      context: context,
      barrierLabel: 'sidebar',
      barrierDismissible: true,
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              height: MediaQuery.of(context).size.height,
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const YallaSidebar(currentRoute: '/employees/salary'),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final offset = Tween<Offset>(
                begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        return SlideTransition(position: offset, child: child);
      },
    );
  }

  Widget _settingsBanner(BuildContext context) {
    final wsAsync = ref.watch(workshopSettingsProvider);
    return wsAsync.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('تعذّر تحميل إعدادات الورشة: $e',
            style: const TextStyle(color: Colors.red, fontSize: 12)),
      ),
      data: (ws) {
        final start = ws.workStart ?? '09:00';
        final end = ws.workEnd ?? '17:00';
        final hours = (ws.dailyHours ?? 8).toString();
        final brk = (ws.breakMinutes ?? 0).toString();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: AppColors.primary.withOpacity(0.06),
            border: Border.all(color: AppColors.primary.withOpacity(0.15)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.schedule, size: 18),
              _chip('الدوام: $start → $end'),
              _chip('ساعات اليوم: $hours'),
              _chip('استراحة: $brk دقيقة'),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final empState = ref.watch(employeeProvider);
    final isDesktop = Responsive.isDesktop(context);

    final filteredEmployees = empState.employees
        .where((e) =>
            e.fullName.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    final appBar = YallaAppBar(
      workshopName: user?.name ?? '',
      logoPath: user?.workshopLogoPath ?? '',
      showThemeToggle: true,
      showUserAvatar: true,
      showSearch: false,
      showNotifications: false,
      leading: isDesktop
          ? null
          : IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: _openSidebarPanel,
            ),
      extraActions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: TextButton.icon(
            onPressed: (_togglingLock || _calculating) ? null : _toggleLock,
            icon: _togglingLock
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_isLocked ? Icons.lock : Icons.lock_open,
                    color: Colors.white),
            label: Text(
              _isLocked ? 'الشهر مقفول' : 'الشهر مفتوح',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        IconButton(
          tooltip: 'إعادة حساب الجميع',
          onPressed: _calculating ? null : _recalcAll,
          icon: const Icon(Icons.refresh, color: Colors.white),
        ),
      ],
    );

    // ===== المحتوى الرئيسي =====
    final content = Column(
      children: [
        const Divider(height: 1),
        _settingsBanner(context),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _calculating ? null : _pickMonth,
                icon: const Icon(Icons.calendar_month),
                label:
                    Text(DateFormat('MMMM yyyy', 'ar').format(_selectedMonth)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
              ),
              const SizedBox(width: 12),
              if (_calculating)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_calcError != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'خطأ في الحساب: $_calcError',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              ],
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: '...ابحث باسم الموظف',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (empState.isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (empState.error != null)
          Expanded(child: Center(child: Text('خطأ: ${empState.error}')))
        else if (filteredEmployees.isEmpty)
          const Expanded(child: Center(child: Text('لا توجد بيانات موظفين')))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredEmployees.length,
              itemBuilder: (_, i) {
                final employee = filteredEmployees[i];
                final net = _netByEmployee[employee.id];

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.employeePayroll,
                        arguments: employee,
                      );
                    },
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      foregroundColor: AppColors.primary,
                      child: Text(employee.fullName.isNotEmpty
                          ? employee.fullName[0]
                          : '?'),
                    ),
                    title: Text(employee.fullName),
                    subtitle: Text(
                      [
                        'الوظيفة: ${employee.jobTitle}',
                        if (net != null)
                          'الراتب الصافي: ${MoneyFormatter.format(net)}'
                        else if (_calculating)
                          '...يتم الحساب'
                        else
                          '—',
                      ].join('\n'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        IconButton(
                          tooltip: _isLocked
                              ? 'الشهر مقفول'
                              : 'إثبات راتب لهذا الموظف',
                          onPressed: (_isLocked || net == null)
                              ? null
                              : () => _postAccrualForEmployee(
                                    employeeId: employee.id,
                                    employeeName: employee.fullName,
                                    amount: net,
                                  ),
                          icon: const Icon(Icons.playlist_add_check),
                        ),
                        IconButton(
                          tooltip:
                              _isLocked ? 'الشهر مقفول' : 'عكس قيد الإثبات',
                          onPressed: _isLocked
                              ? null
                              : () => _reverseAccrualForEmployee(
                                  employeeId: employee.id),
                          icon: const Icon(Icons.undo),
                        ),
                        IconButton(
                          tooltip: _isLocked ? 'الشهر مقفول' : 'صرف راتب',
                          onPressed: _isLocked
                              ? null
                              : () => _paySalaryForEmployee(
                                    employeeId: employee.id,
                                    employeeName: employee.fullName,
                                  ),
                          icon: const Icon(Icons.payments),
                        ),
                        IconButton(
                          tooltip: _isLocked ? 'الشهر مقفول' : 'عكس قيد الصرف',
                          onPressed: _isLocked
                              ? null
                              : () => _reversePaymentForEmployee(
                                  employeeId: employee.id),
                          icon: const Icon(Icons.settings_backup_restore),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: appBar,
      ),
      // لا drawer ولا endDrawer. نتحكم بنفسنا.
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (!isDesktop) {
            // موبايل: محتوى فقط. السايدبار يفتح بزر ويظهر كلوح منزلق يمين.
            return content;
          }
          // ديسكتوب: السايدبار مثبت يمين عبر Stack.
          const sidebarWidth = 260.0;
          return Stack(
            children: [
              // المحتوى مع مساحة يمين ثابتة للسايدبار
              Padding(
                padding: const EdgeInsets.only(right: sidebarWidth),
                child: content,
              ),
              // السايدبار مثبت يمين
              const Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: sidebarWidth,
                child: Material(
                  elevation: 2,
                  child: YallaSidebar(currentRoute: '/employees/salary'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
