// 📁 lib/features/employees/screens/attendance_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/attendance_database_service.dart';
import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/employees/providers/salary_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  // حالات موحّدة:
  static const stPresent = 'حضور';
  static const stAbsent = 'غياب';
  static const stPaidLeave = 'إجازة_مدفوعة';
  static const stUnpaidLeave = 'إجازة_غير_مدفوعة';
  static const stHoliday = 'عطلة_رسمية';

  Employee? selectedEmployee;
  DateTime selectedMonth = DateTime.now();
  List<Attendance> records = [];
  bool isLoading = false;
  String? loadError;

  TimeOfDay? startTime;
  TimeOfDay? endTime;
  double workHours = 0; // تُحمَّل من إعدادات الورشة

  static const int _graceInMinutes = 10; // سماح تأخير
  static const int _graceOutMinutes = 10; // سماح خروج

  // KPIs
  int kpiPresentDays = 0;
  int kpiAbsentDays = 0;
  int kpiPaidLeaveDays = 0;
  int kpiUnpaidLeaveDays = 0;
  int kpiHolidayDays = 0;
  int kpiLateMinutes = 0;
  double kpiOvertimeHours = 0.0;
  double kpiPayableHours = 0.0;
  double kpiPayableDays = 0.0;

  @override
  void initState() {
    super.initState();

    _loadWorkshopSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final emps = ref.read(employeeProvider).employees;
      if (emps.isNotEmpty) {
        setState(() => selectedEmployee = emps.first);
        _loadAttendance();
      }
    });
  }

  Future<void> _loadWorkshopSettings() async {
    final ws = await WorkshopSettingsService.instance.getOrDefaults();

    startTime = (ws.workStart == null || ws.workStart!.isEmpty)
        ? null
        : _parseHHMM(ws.workStart!);

    endTime = (ws.workEnd == null || ws.workEnd!.isEmpty)
        ? null
        : _parseHHMM(ws.workEnd!);

    workHours = ws.dailyHours ?? 0;

    if (mounted) setState(() {});
  }

  TimeOfDay _parseHHMM(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final m = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (h == null || m == null) return const TimeOfDay(hour: 0, minute: 0);
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  Future<void> _loadAttendance() async {
    if (selectedEmployee == null) return;
    setState(() {
      isLoading = true;
      loadError = null;
    });
    try {
      final from = DateTime(selectedMonth.year, selectedMonth.month, 1);
      final to = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
      final result = await AttendanceDatabaseService.getAttendanceForEmployee(
        employeeId: selectedEmployee!.id,
        from: from,
        to: to,
      );
      setState(() => records = result);
      _recomputeKPIs();
    } catch (e) {
      setState(() => loadError = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'اختر شهرًا',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => selectedMonth = picked);
      await _loadAttendance();
    }
  }

  Future<void> _markTodayAsPresent() async {
    if (selectedEmployee == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final already = records.any((r) => _isSameDate(r.date, today));
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل حضور هذا اليوم مسبقًا.')),
      );
      return;
    }

    final inHmm = _fmtHmm(_stdStart());

    final outHmm = _fmtHmm(_stdEnd());
    final hours = _calcWorkedHours(inHmm, outHmm);

    final id =
        '${selectedEmployee!.id}_${DateFormat('yyyyMMdd').format(today)}';
    final rec = Attendance(
      id: id,
      employeeId: selectedEmployee!.id,
      date: today,
      status: stPresent,
      checkIn: inHmm,
      checkOut: outHmm,
      hoursWorked: hours,
      notes: null,
    );

    await AttendanceDatabaseService.insertAttendance(rec);
    await _loadAttendance();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل حضور اليوم')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const currentRoute = '/employees/attendance';
    final user = ref.watch(currentUserProvider); // ← تم التصحيح
    final empState = ref.watch(employeeProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    if (selectedEmployee != null &&
        !empState.employees.any((e) => e.id == selectedEmployee!.id)) {
      selectedEmployee = null;
      records = [];
    }

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      body: Row(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: currentRoute),
            ),
          Expanded(
            child: Column(
              children: [
                _buildAppBar(user),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(empState.employees),
                        const SizedBox(height: 12),
                        _buildWorkshopTimes(),
                        const SizedBox(height: 12),
                        if (empState.isLoading)
                          const Expanded(
                              child: Center(child: CircularProgressIndicator()))
                        else if (empState.error != null)
                          Expanded(
                              child: Center(
                                  child:
                                      Text('خطأ الموظفين: ${empState.error}')))
                        else if (empState.employees.isEmpty)
                          const Expanded(
                              child: Center(child: Text('لا يوجد موظفون')))
                        else if (selectedEmployee == null)
                          const Expanded(
                              child: Center(child: Text('اختر موظفًا')))
                        else if (loadError != null)
                          Expanded(
                              child: Center(child: Text('خطأ: $loadError')))
                        else if (isLoading)
                          const Expanded(
                              child: Center(child: CircularProgressIndicator()))
                        else ...[
                          _buildKPIsBar(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.calculate),
                                label: const Text('احتساب الراتب لهذا الشهر'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                ),
                                onPressed: () async {
                                  if (selectedEmployee == null) return;

                                  final totalDays = DateUtils.getDaysInMonth(
                                    selectedMonth.year,
                                    selectedMonth.month,
                                  );

                                  final salary = await ref
                                      .read(salaryProvider.notifier)
                                      .calculateAndReturn(
                                        employeeId: selectedEmployee!.id,
                                        baseSalary:
                                            selectedEmployee!.baseSalary,
                                        totalWorkDaysInMonth: totalDays,
                                        attendanceRecords: records,
                                        payOfficialHolidays: true,
                                      );

                                  if (!mounted) return;

                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('📊 الراتب المحسوب'),
                                      content: Text(
                                        'راتب ${selectedEmployee!.fullName} هو: ${MoneyFormatter.format(salary)}',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('حسنًا'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('كشف دوام شهري'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color.fromARGB(255, 217, 211, 227),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                ),
                                onPressed: _exportMonthlyAttendancePdf,
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'اليوم الحالي: ${DateFormat('EEEE، d MMM yyyy', 'ar').format(DateTime.now())}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'تحديث',
                                    onPressed: isLoading
                                        ? null
                                        : () => _loadAttendance(),
                                    icon: isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.refresh),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.check),
                                    label: const Text('تسجيل حضور اليوم'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 12),
                                    ),
                                    onPressed: _markTodayAsPresent,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: SingleChildScrollView(
                              child: ExpansionTile(
                                initiallyExpanded: true,
                                title: const Text('تفاصيل أيام الشهر'),
                                children: [_buildAttendanceTable()],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── UI parts ─────────────

  ImageProvider<Object>? _resolveUserLogo(dynamic user) {
    final rawPath = user?.workshopLogoPath?.toString().trim();
    if (rawPath == null || rawPath.isEmpty) return null;

    final file = File(rawPath);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  Widget _buildAppBar(user) {
    final logoImage = _resolveUserLogo(user);

    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.access_time_filled, color: Colors.white),
          const SizedBox(width: 12),
          const Text('الحضور والانصراف',
              style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          if (user != null)
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: logoImage,
                  child: logoImage == null ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 8),
                Text(user.name, style: const TextStyle(color: Colors.white)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<Employee> employees) {
    return Row(
      children: [
        Expanded(child: _buildDropdown(employees)),
        const SizedBox(width: 16),
        TextButton.icon(
          icon: const Icon(Icons.calendar_month),
          label: Text(DateFormat('yyyy-MM').format(selectedMonth)),
          onPressed: _pickMonth,
        ),
      ],
    );
  }

  Widget _buildDropdown(List<Employee> employees) {
    return DropdownButtonFormField<Employee>(
      decoration: InputDecoration(
          labelText: 'اختر موظفًا', border: OutlineInputBorder()),
      value: selectedEmployee,
      items: employees
          .map((e) =>
              DropdownMenuItem<Employee>(value: e, child: Text(e.fullName)))
          .toList(),
      onChanged: (val) async {
        setState(() {
          selectedEmployee = val;
          records = [];
        });
        await _loadAttendance();
      },
    );
  }

  Widget _buildWorkshopTimes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'وقت الدوام: ${startTime != null ? startTime!.format(context) : '--'}'
          ' إلى ${endTime != null ? endTime!.format(context) : '--'}',
        ),
        const SizedBox(height: 4),
        Text('عدد ساعات الدوام: ${workHours.toStringAsFixed(2)} ساعة'),
      ],
    );
  }

  Widget _buildKPIsBar() {
    final totalDays =
        DateUtils.getDaysInMonth(selectedMonth.year, selectedMonth.month);
    final percent =
        totalDays == 0 ? 0 : (kpiPresentDays / totalDays * 100).round();

    Chip chip(String label, String value, Color c, {bool bold = false}) => Chip(
          label: Text('$label: $value',
              style: TextStyle(
                  color: c,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          side: BorderSide(color: c.withOpacity(0.35)),
          backgroundColor: c.withOpacity(0.06),
        );

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip('أيام الحضور', '$kpiPresentDays', Colors.green),
        chip('أيام الغياب', '$kpiAbsentDays', Colors.red),
        chip('إجازات مدفوعة', '$kpiPaidLeaveDays', Colors.blue),
        chip('إجازات غير مدفوعة', '$kpiUnpaidLeaveDays', Colors.orange),
        chip('عطل رسمية', '$kpiHolidayDays', Colors.teal),
        chip('التأخير', '$kpiLateMinutesد', Colors.purple),
        chip('الإضافي', '${kpiOvertimeHours.toStringAsFixed(2)}س',
            Colors.indigo),
        chip('ساعات مدفوعة', '${kpiPayableHours.toStringAsFixed(2)}س',
            Colors.brown),
        chip('أيام مدفوعة', '${kpiPayableDays.toStringAsFixed(2)}ي',
            Colors.black87,
            bold: true),
        chip('نسبة الحضور', '$percent%', Colors.blueGrey),
      ],
    );
  }

  Widget _buildAttendanceTable() {
    final totalDays =
        DateUtils.getDaysInMonth(selectedMonth.year, selectedMonth.month);
    final today = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == today.year && selectedMonth.month == today.month;

    final days = List.generate(
      totalDays,
      (i) => DateTime(selectedMonth.year, selectedMonth.month, i + 1),
    )..sort((a, b) {
        if (!isCurrentMonth) {
          // لو مش الشهر الحالي: ترتيب تنازلي يطلع آخر يوم فوق
          return b.compareTo(a);
        }

        // لو الشهر الحالي:
        if (_isSameDate(a, today)) return -1; // اليوم أولًا
        if (_isSameDate(b, today)) return 1;
        return b.compareTo(a); // الباقي تنازلي
      });

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final match = records.firstWhere(
          (r) => _isSameDate(r.date, day),
          orElse: () => Attendance(
            employeeId: selectedEmployee!.id,
            date: day,
            status: stAbsent,
            id: '',
          ),
        );

        final subtitle = switch (match.status) {
          stPresent => [
              if (match.checkIn != null) 'دخول: ${match.checkIn}',
              if (match.checkOut != null) 'خروج: ${match.checkOut}',
              if (match.hoursWorked != null)
                'ساعات: ${match.hoursWorked!.toStringAsFixed(2)}',
              ..._renderLateOverFor(match),
            ].join(' • '),
          stPaidLeave => 'إجازة مدفوعة',
          stUnpaidLeave => 'إجازة غير مدفوعة',
          stHoliday => 'عطلة رسمية',
          _ => (match.notes ?? ''),
        };

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(_iconForStatus(match.status),
                color: _colorForStatus(match.status)),
            title: Text(DateFormat('EEEE، dd MMM yyyy', 'ar').format(day)),
            subtitle: Text(subtitle),
            trailing: Text(match.status,
                style: TextStyle(
                    color: _colorForStatus(match.status),
                    fontWeight: FontWeight.bold)),
            onTap: () => _openEditDialog(match),
          ),
        );
      },
    );
  }

  Future<void> _openEditDialog(Attendance record) async {
    final df = DateFormat('yyyy-MM-dd');
    final isExisting = record.id.isNotEmpty;

    String status = record.status.isEmpty ? stAbsent : record.status;
    String? checkIn = record.checkIn;
    String? checkOut = record.checkOut;
    String? notes = record.notes;

    final ctrlIn = TextEditingController(text: checkIn ?? '');
    final ctrlOut = TextEditingController(text: checkOut ?? '');
    final ctrlNotes = TextEditingController(text: notes ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل ${df.format(record.date)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: status,
              items: const [
                DropdownMenuItem(value: stPresent, child: Text('حضور')),
                DropdownMenuItem(value: stAbsent, child: Text('غياب')),
                DropdownMenuItem(
                    value: stPaidLeave, child: Text('إجازة مدفوعة')),
                DropdownMenuItem(
                    value: stUnpaidLeave, child: Text('إجازة غير مدفوعة')),
                DropdownMenuItem(value: stHoliday, child: Text('عطلة رسمية')),
              ],
              onChanged: (v) => status = v ?? stAbsent,
              decoration: InputDecoration(labelText: 'الحالة'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: ctrlIn,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'وقت الدخول (HH:mm)',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.access_time),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _initialTimeOf(ctrlIn.text) ??
                                startTime ??
                                TimeOfDay.now(),
                          );
                          if (picked != null) {
                            final m = _toMinutes(picked);
                            if (m != null) {
                              ctrlIn.text = _fmtHmm(m);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: ctrlOut,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'وقت الخروج (HH:mm)',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.access_time),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _initialTimeOf(ctrlOut.text) ??
                                (endTime ??
                                    const TimeOfDay(hour: 17, minute: 0)),
                          );
                          if (picked != null) {
                            ctrlOut.text =
                                _fmtHmm(_toMinutes(picked) ?? 17 * 60);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: ctrlNotes,
              decoration: InputDecoration(labelText: 'ملاحظات'),
            ),
            const SizedBox(height: 8),
            if (status == stPresent)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'سيتم احتساب ساعات العمل مع خصم التأخير/المغادرة المبكرة.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
        actions: [
          if (isExisting)
            TextButton(
              onPressed: () async {
                await AttendanceDatabaseService.deleteAttendance(record.id);
                if (mounted) Navigator.pop(context, true);
              },
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ')),
        ],
      ),
    );

    if (ok == true && selectedEmployee != null) {
      final id = record.id.isNotEmpty
          ? record.id
          : '${selectedEmployee!.id}_${DateFormat('yyyyMMdd').format(record.date)}';

      final inStr = ctrlIn.text.trim().isEmpty ? null : ctrlIn.text.trim();
      final outStr = ctrlOut.text.trim().isEmpty ? null : ctrlOut.text.trim();
      final notesFinal =
          ctrlNotes.text.trim().isEmpty ? null : ctrlNotes.text.trim();

      double? hours;
      if (status == stPresent) {
        hours = (inStr == null || outStr == null)
            ? workHours
            : _calcWorkedHours(inStr, outStr);
      } else {
        hours = null;
      }

      final updated = Attendance(
        id: id,
        employeeId: selectedEmployee!.id,
        date: DateTime(record.date.year, record.date.month, record.date.day),
        status: status,
        checkIn: status == stPresent ? inStr : null,
        checkOut: status == stPresent ? outStr : null,
        hoursWorked: hours,
        notes: notesFinal,
      );

      if (record.id.isEmpty) {
        await AttendanceDatabaseService.insertAttendance(updated);
      } else {
        await AttendanceDatabaseService.updateAttendance(updated);
      }
      await _loadAttendance();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم الحفظ')));
    }
  }

  // ───────────── KPI math ─────────────

  void _recomputeKPIs() {
    final stdStart = _stdStart();
    final stdEnd = _stdEnd();
    final dayMinutes =
        (workHours > 0 ? (workHours * 60).round() : (stdEnd - stdStart))
            .clamp(0, 24 * 60);

    int present = 0, absent = 0, paidLv = 0, unpLv = 0, hol = 0;
    int lateMin = 0;
    double otHours = 0.0, payableH = 0.0;

    for (final r in records) {
      final st = r.status.trim();
      if (st == stPresent) {
        present++;
        final wh = _workedHoursOf(r);
        if ((r.checkIn ?? '').isNotEmpty) {
          final acMin = _parseHmm(r.checkIn!);
          if (acMin != null) {
            final graceStart = stdStart + _graceInMinutes;
            lateMin += acMin > graceStart ? (acMin - graceStart) : 0;
          }
        }
        final baseH = dayMinutes / 60.0;
        if (wh > baseH) {
          otHours += _round2(wh - baseH);
          payableH += baseH;
        } else {
          payableH += wh;
        }
      } else if (st == stPaidLeave) {
        paidLv++;
        payableH += dayMinutes / 60.0;
      } else if (st == stUnpaidLeave) {
        unpLv++;
      } else if (st == stHoliday) {
        hol++;
        payableH += dayMinutes / 60.0;
      } else if (st == stAbsent) {
        absent++;
      }
    }

    final payableD =
        (dayMinutes > 0) ? _round2(payableH / (dayMinutes / 60.0)) : 0.0;

    setState(() {
      kpiPresentDays = present;
      kpiAbsentDays = absent;
      kpiPaidLeaveDays = paidLv;
      kpiUnpaidLeaveDays = unpLv;
      kpiHolidayDays = hol;
      kpiLateMinutes = lateMin;
      kpiOvertimeHours = _round2(otHours);
      kpiPayableHours = _round2(payableH);
      kpiPayableDays = payableD;
    });
  }

  // ───────────── Helpers ─────────────

  double _calcWorkedHours(String inHmm, String outHmm) {
    final stdStart = _stdStart();
    final stdEnd = _stdEnd();

    if (stdStart == 0 || stdEnd == 0 || workHours <= 0) return 0.0;

    final inMin = _parseHmm(inHmm);
    final outMin = _parseHmm(outHmm);

    if (inMin == null || outMin == null || outMin <= inMin) {
      return 0.0;
    }
// دوام كامل بدون أي خصم
    if (inMin == stdStart && outMin == stdEnd) {
      return _round2(workHours);
    }

    // سماح الدخول
    final effectiveIn = inMin <= stdStart + _graceInMinutes ? stdStart : inMin;

    // سماح الخروج
    final effectiveOut = outMin >= stdEnd - _graceOutMinutes ? stdEnd : outMin;

    int workedMinutes = effectiveOut - effectiveIn;
    if (workedMinutes < 0) workedMinutes = 0;

    final maxMinutes = (workHours * 60).round();
    if (workedMinutes > maxMinutes) workedMinutes = maxMinutes;

    return _round2(workedMinutes / 60.0);
  }

  double _workedHoursOf(Attendance r) {
    if ((r.hoursWorked ?? 0) > 0) return _round2(r.hoursWorked!);
    if ((r.checkIn ?? '').isEmpty || (r.checkOut ?? '').isEmpty) return 0.0;

    final ci = _parseHmm(r.checkIn!);
    final co = _parseHmm(r.checkOut!);

    if (ci == null || co == null || co <= ci) return 0.0;

    return _round2((co - ci) / 60.0);
  }

  List<String> _renderLateOverFor(Attendance r) {
    final wh = _workedHoursOf(r);
    final baseH = workHours > 0 ? workHours : 8.0;

    final ot = wh > baseH ? _round2(wh - baseH) : 0.0;

    int late = 0;
    if ((r.checkIn ?? '').isNotEmpty) {
      final acMin = _parseHmm(r.checkIn!);
      if (acMin != null) {
        final graceStart = _stdStart() + _graceInMinutes;
        late = acMin > graceStart ? (acMin - graceStart) : 0;
      }
    }

    return [
      if (late > 0) 'تأخير: $lateد',
      if (ot > 0) 'إضافي: ${ot.toStringAsFixed(2)}س',
    ];
  }

  int _stdStart() => _toMinutes(startTime) ?? 0;
  int _stdEnd() => _toMinutes(endTime) ?? 0;

  int? _parseHmm(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  String _fmtHmm(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay? _initialTimeOf(String s) {
    final t = _parseHmm(s);
    if (t == null) return null;
    return TimeOfDay(hour: t ~/ 60, minute: t % 60);
  }

  int? _toMinutes(TimeOfDay? t) => t == null ? null : t.hour * 60 + t.minute;

  IconData _iconForStatus(String status) {
    switch (status) {
      case stPresent:
        return Icons.check_circle;
      case stAbsent:
        return Icons.cancel;
      case stPaidLeave:
        return Icons.beach_access;
      case stUnpaidLeave:
        return Icons.beach_access_outlined;
      case stHoliday:
        return Icons.flag;
      default:
        return Icons.help_outline;
    }
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case stPresent:
        return Colors.green;
      case stAbsent:
        return Colors.red;
      case stPaidLeave:
        return Colors.blue;
      case stUnpaidLeave:
        return Colors.orange;
      case stHoliday:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  double _round2(num x) => double.parse(x.toStringAsFixed(2));

  Future<void> _exportMonthlyAttendancePdf() async {
    if (selectedEmployee == null) return;

    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات لهذا الشهر')),
      );
      return;
    }

    // -------------------------------
    // 1) تجهيز صفوف الجدول
    // -------------------------------
    final rows = records.map((r) {
      return {
        'date': DateFormat('yyyy-MM-dd').format(r.date),
        'in': r.checkIn ?? '-',
        'out': r.checkOut ?? '-',
        'hours': r.hoursWorked?.toStringAsFixed(2) ?? '-',
        'status': r.status,
      };
    }).toList();

    // -------------------------------
    // 2) المجاميع (من الـ KPIs الجاهزة)
    // -------------------------------
    final totalHours = kpiPayableHours;
    final totalDays = kpiPayableDays;

    // -------------------------------
    // 3) حساب الراتب (نفس منطق الزر)
    // -------------------------------
    final totalWorkDays = DateUtils.getDaysInMonth(
      selectedMonth.year,
      selectedMonth.month,
    );

    final totalSalary =
        await ref.read(salaryProvider.notifier).calculateAndReturn(
              employeeId: selectedEmployee!.id,
              baseSalary: selectedEmployee!.baseSalary,
              totalWorkDaysInMonth: totalWorkDays,
              attendanceRecords: records,
              payOfficialHolidays: true,
            );

    if (!mounted) return;

    // -------------------------------
    // 4) توليد PDF
    // -------------------------------
    await YallaPdfService.generateMonthlyAttendancePdf(
      employeeName: selectedEmployee!.fullName,
      month: selectedMonth,
      rows: rows,
      totalHours: totalHours,
      totalDays: totalDays,
      totalSalary: totalSalary,
    );
  }
}
