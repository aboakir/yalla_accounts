import 'package:yalla_accounts/features/vouchers/screens/payment_voucher_screen.dart';
// 📁 lib/features/employees/screens/payroll_screen.dart
//
// PayrollScreen — شاشة إدارة استحقاق وصرف راتب موظف واحد
// متوافقة مع payrollProvider و PayrollDatabaseService.
// أزرار قفل/فك قفل شهر الرواتب و"تحديث" حالة القفل.
// تمرير تعديلات الحضور ضمن البدلات والخصومات في accrue().

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart'; // PayrollRun
import 'package:yalla_accounts/features/employees/providers/payroll_provider.dart';
import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_entitlement_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PayrollScreen extends ConsumerStatefulWidget {
  final Employee employee;
  const PayrollScreen({super.key, required this.employee});

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  final _formKey = GlobalKey<FormState>();

  final _grossCtrl = TextEditingController();
  final _allowCtrl = TextEditingController(text: '0');
  final _deductCtrl = TextEditingController(text: '0');
  final _advApplyCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();

  // تعديلات الحضور
  final _overtimeCtrl = TextEditingController(text: '0'); // زيادة
  final _latePenaltyCtrl = TextEditingController(text: '0'); // خصم
  final _unpaidAbsPenaltyCtrl = TextEditingController(text: '0'); // خصم
  final _paidHolidayCtrl = TextEditingController(text: '0'); // زيادة

  DateTime _periodStart =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _periodEnd =
      DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  DateTime _accrualDate = DateTime.now();
  String _suggestedMethod = 'cash';

  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _grossCtrl.text = widget.employee.baseSalaryForType.toStringAsFixed(2);
    _allowCtrl.text = widget.employee.allowances.toStringAsFixed(2);
    _deductCtrl.text = widget.employee.deductions.toStringAsFixed(2);
    final configuredMethod = widget.employee.paymentMethod.toLowerCase().trim();
    _suggestedMethod =
        const {'cash', 'bank', 'transfer'}.contains(configuredMethod)
            ? configuredMethod
            : 'cash';
    Future.microtask(() async {
      await ref.read(payrollProvider.notifier).load(widget.employee.id);
      await _ensurePeriodRow();
      await _refreshLock();
    });
  }

  @override
  void dispose() {
    _grossCtrl.dispose();
    _allowCtrl.dispose();
    _deductCtrl.dispose();
    _advApplyCtrl.dispose();
    _noteCtrl.dispose();
    _overtimeCtrl.dispose();
    _latePenaltyCtrl.dispose();
    _unpaidAbsPenaltyCtrl.dispose();
    _paidHolidayCtrl.dispose();
    super.dispose();
  }

  String _monthKey() => DateFormat('yyyy-MM').format(_periodStart);

  Future<void> _ensurePeriodRow() async {
    final y = _periodStart.year;
    final m = _periodStart.month;
    await PayrollPeriodsService.ensurePeriodRow(y, m);
  }

  Future<void> _refreshLock() async {
    final y = _periodStart.year;
    final m = _periodStart.month;
    final locked = await PayrollPeriodsService.isLocked(y, m);
    if (mounted) setState(() => _isLocked = locked);
  }

  Future<void> _lockMonth() async {
    try {
      final y = _periodStart.year;
      final m = _periodStart.month;
      await PayrollPeriodsService.lockPeriod(y, m);
      await _refreshLock();
      _toast('تم قفل شهر ${_monthKey()}');
    } catch (e) {
      _toast('تعذّر القفل: $e');
    }
  }

  Future<void> _unlockMonth() async {
    try {
      final y = _periodStart.year;
      final m = _periodStart.month;
      await PayrollPeriodsService.unlockPeriod(y, m);
      await _refreshLock();
      _toast('تم فك قفل شهر ${_monthKey()}');
    } catch (e) {
      _toast('تعذّر فك القفل: $e');
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: _periodStart, end: _periodEnd),
    );
    if (picked != null) {
      setState(() {
        _periodStart = DateTime(picked.start.year, picked.start.month, 1);
        _periodEnd = DateTime(picked.end.year, picked.end.month, 0);
        _accrualDate = DateTime.now();
      });
      await _ensurePeriodRow();
      await _refreshLock();
    }
  }

  Future<void> _pickAccrualDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _accrualDate,
      firstDate: DateTime(_periodStart.year, _periodStart.month, 1),
      lastDate: DateTime(_periodEnd.year, _periodEnd.month, _periodEnd.day),
    );
    if (picked != null) setState(() => _accrualDate = picked);
  }

  bool _nonNegValidator(String? v) {
    final x = double.tryParse((v ?? '').trim());
    return x != null && x >= 0;
  }

  Future<void> _submitAccrual() async {
    if (_isLocked) {
      _toast('الفترة مقفلة. افتحها من شاشة الرواتب.');
      return;
    }

    try {
      final calculation = await PayrollEntitlementService.calculate(
        employee: widget.employee,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );

      if (mounted) {
        setState(() {
          _grossCtrl.text = calculation.baseEarned.toStringAsFixed(2);
          _allowCtrl.text = calculation.allowances.toStringAsFixed(2);
          _deductCtrl.text = calculation.fixedDeductions.toStringAsFixed(2);
          _overtimeCtrl.text = calculation.overtimePay.toStringAsFixed(2);
          _latePenaltyCtrl.text = calculation.lateDeduction.toStringAsFixed(2);
          _unpaidAbsPenaltyCtrl.text =
              calculation.earlyExitDeduction.toStringAsFixed(2);
          _paidHolidayCtrl.text =
              calculation.attendance.payableDays.toStringAsFixed(2);
        });
      }

      await PayrollEntitlementService.accrueFromAttendance(
        employee: widget.employee,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        accrualDate: _accrualDate,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      await ref.read(payrollProvider.notifier).load(widget.employee.id);
      _toast(
        'تم إنشاء استحقاق الراتب من الحضور: ${MoneyFormatter.format(calculation.netBeforeAdvances)}',
      );
    } catch (e) {
      _toast('فشل احتساب الاستحقاق: $e');
    }
  }

  Future<void> _openPayDialog(PayrollRun run) async {
    if (_isLocked) {
      _toast('الفترة مقفلة. افتحها أولاً.');
      return;
    }

    final remain = (run.net - run.amountPaid);
    if (remain <= 0) return;

    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PaymentVoucherScreen(
            employeeId: run.employeeId,
            employeeName: widget.employee.fullName,
            payrollRun: run,
            presetAmount: remain)));
    if (mounted)
      await ref.read(payrollProvider.notifier).load(widget.employee.id);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final runs = ref
        .watch(payrollProvider)
        .where((r) => r.employeeId == widget.employee.id)
        .toList();

    final totalNet = runs.fold<double>(0, (s, r) => s + r.net);
    final totalPaid = runs.fold<double>(0, (s, r) => s + r.amountPaid);
    final totalRemain = totalNet - totalPaid;

    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/employees/payroll'),
            ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName: 'الرواتب',
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8.0),
              child: Chip(
                label: Text(
                  _isLocked
                      ? 'الشهر مقفول (${_monthKey()})'
                      : 'الشهر مفتوح (${_monthKey()})',
                  style: TextStyle(
                    color: _isLocked ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                side: BorderSide(
                  color:
                      (_isLocked ? Colors.red : Colors.green).withOpacity(0.4),
                ),
                backgroundColor:
                    (_isLocked ? Colors.red : Colors.green).withOpacity(0.06),
              ),
            ),
            IconButton(
              tooltip: 'تحديث حالة القفل',
              onPressed: _refreshLock,
              icon: const Icon(Icons.refresh),
            ),
            if (_isLocked)
              IconButton(
                tooltip: 'فك قفل الشهر',
                onPressed: _unlockMonth,
                icon: const Icon(Icons.lock_open),
              )
            else
              IconButton(
                tooltip: 'قفل الشهر',
                onPressed: _lockMonth,
                icon: const Icon(Icons.lock),
              ),
          ],
        ),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/employees/payroll'),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      Text(
                        'الموظف: ${widget.employee.fullName}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      _kpi('إجمالي صافي المستحق', totalNet),
                      _kpi('المدفوع', totalPaid),
                      _kpi('المتبقي', totalRemain, emphasized: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isLocked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: AdaptiveRow(
                        children: const [
                          Icon(Icons.lock, color: Colors.red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'هذا الشهر مقفول. لا يمكن إنشاء استحقاق أو دفع ضمنه من هذه الشاشة.',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Form(
                    key: _formKey,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(
                          width: 260,
                          child: InkWell(
                            onTap: _pickDateRange,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'الفترة',
                                border: OutlineInputBorder(),
                              ),
                              child: AdaptiveRow(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${df.format(_periodStart)} → ${df.format(_periodEnd)}',
                                  ),
                                  const Icon(Icons.date_range),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: InkWell(
                            onTap: _pickAccrualDate,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'تاريخ الاستحقاق',
                                border: OutlineInputBorder(),
                              ),
                              child: AdaptiveRow(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(df.format(_accrualDate)),
                                  const Icon(Icons.event),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _grossCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'الأساس المستحق من الحضور',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final x = double.tryParse((v ?? '').trim());
                              if (x == null || x <= 0) {
                                return 'أدخل رقمًا صحيحًا > 0';
                              }
                              return null;
                            },
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _allowCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'بدلات',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _nonNegValidator(v) ? null : '≥ 0',
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _deductCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'خصومات',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _nonNegValidator(v) ? null : '≥ 0',
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _advApplyCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'سلف مستخدمة',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _nonNegValidator(v) ? null : '≥ 0',
                          ),
                        ),
                        // تعديلات الحضور
                        SizedBox(
                          width: 160,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _overtimeCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'إضافي محسوب',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _nonNegValidator(v) ? null : '≥ 0',
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _latePenaltyCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'تأخير محسوب',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _nonNegValidator(v) ? null : '≥ 0',
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _unpaidAbsPenaltyCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'خروج مبكر محسوب',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _nonNegValidator(v) ? null : '≥ 0',
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _paidHolidayCtrl,
                            enabled: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'أيام مدفوعة محسوبة',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                _nonNegValidator(v) ? null : '≥ 0',
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            value: _suggestedMethod,
                            items: const [
                              DropdownMenuItem(
                                  value: 'cash', child: Text('نقدي')),
                              DropdownMenuItem(
                                  value: 'bank', child: Text('بنك')),
                              DropdownMenuItem(
                                  value: 'transfer', child: Text('تحويل')),
                            ],
                            onChanged: (v) =>
                                setState(() => _suggestedMethod = v ?? 'cash'),
                            decoration: InputDecoration(
                              labelText: 'طريقة الدفع',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: TextFormField(
                            inputFormatters: const [YallaDigitNormalizer()],
                            controller: _noteCtrl,
                            decoration: InputDecoration(
                              labelText: 'ملاحظة (اختياري)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _isLocked ? null : _submitAccrual,
                            icon: const Icon(Icons.save),
                            label: const Text('تسجيل استحقاق وربط GL'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  Expanded(
                    child: runs.isEmpty
                        ? const Center(child: Text('لا يوجد سجلات رواتب'))
                        : (isDesktop ? _buildTable(runs) : _buildCards(runs)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, double value, {bool emphasized = false}) {
    final color = emphasized ? Colors.blue : Colors.black87;
    final fw = emphasized ? FontWeight.w700 : FontWeight.w500;
    return Chip(
      label: Text(
        '$label: ${MoneyFormatter.format(value)}',
        style: TextStyle(color: color, fontWeight: fw),
      ),
      side: BorderSide(color: color.withOpacity(0.3)),
      backgroundColor: color.withOpacity(0.06),
    );
  }

  Widget _buildCards(List<PayrollRun> items) {
    final df = DateFormat('yyyy-MM-dd');
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final r = items[i];
        final remain = (r.net - r.amountPaid);
        return ListTile(
          leading: CircleAvatar(
            child: Icon(remain > 0 ? Icons.hourglass_top : Icons.check),
          ),
          title: Text(
            'صافي: ${MoneyFormatter.format(r.net)} — مدفوع: ${MoneyFormatter.format(r.amountPaid)}',
          ),
          subtitle: Text(
            '${df.format(r.periodStart)} → ${df.format(r.periodEnd)}  •  استحقاق: ${df.format(r.accrualDate)}  •  حالة: ${r.status}',
          ),
          trailing: remain > 0
              ? ElevatedButton(
                  onPressed: _isLocked ? null : () => _openPayDialog(r),
                  child: const Text('إنشاء سند صرف'),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildTable(List<PayrollRun> items) {
    final df = DateFormat('yyyy-MM-dd');
    final rows = items.map((r) {
      final remain = (r.net - r.amountPaid);
      return DataRow(
        cells: [
          DataCell(Text(r.id.substring(0, 8))),
          DataCell(
              Text('${df.format(r.periodStart)} → ${df.format(r.periodEnd)}')),
          DataCell(Text(df.format(r.accrualDate))),
          DataCell(Text('${MoneyFormatter.format(r.net)}')),
          DataCell(Text('${MoneyFormatter.format(r.amountPaid)}')),
          DataCell(Text('${MoneyFormatter.format(remain)}')),
          DataCell(Text(r.status)),
          DataCell(
            remain > 0
                ? ElevatedButton(
                    onPressed: _isLocked ? null : () => _openPayDialog(r),
                    child: const Text('إنشاء سند صرف'),
                  )
                : const Icon(Icons.check, color: Colors.green),
          ),
        ],
      );
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('الفترة')),
          DataColumn(label: Text('تاريخ الاستحقاق')),
          DataColumn(label: Text('الصافي')),
          DataColumn(label: Text('المدفوع')),
          DataColumn(label: Text('المتبقي')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('إجراء')),
        ],
        rows: rows,
      ),
    );
  }
}
