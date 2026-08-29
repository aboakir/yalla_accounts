// 📁 lib/features/employees/screens/employee_advances_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';

import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/employees/providers/advance_provider.dart';
import 'package:yalla_accounts/features/employees/services/advance_database_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class EmployeeAdvancesScreen extends ConsumerStatefulWidget {
  final Employee employee;
  const EmployeeAdvancesScreen({super.key, required this.employee});

  @override
  ConsumerState<EmployeeAdvancesScreen> createState() =>
      _EmployeeAdvancesScreenState();
}

class _EmployeeAdvancesScreenState
    extends ConsumerState<EmployeeAdvancesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  // form
  String _type = 'advance'; // advance | bonus | repayment
  String _method = 'cash'; // cash | bank | cheque | transfer
  DateTime _date = DateTime.now();

  // view filters
  String _viewType = 'all'; // all | advance | bonus | repayment
  String _viewMethod = 'all'; // all | cash | bank | cheque | transfer
  String _viewQuery = ''; // free text search (id/method/note)

  double _glAdvanceBalance = 0.0; // رصيد السلف من GL (1120.E)

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(advanceProvider.notifier).loadAdvances(widget.employee.id);
      await _refreshGlBalance();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  double _toDouble(String v) => double.tryParse(v.trim()) ?? 0.0;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'اختر تاريخ العملية',
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day, _date.hour,
            _date.minute, _date.second);
      });
    }
  }

  Future<void> _refreshGlBalance() async {
    final bal = await AdvanceDatabaseService.getEmployeeAdvanceBalance(
        widget.employee.id);
    if (!mounted) return;
    setState(() => _glAdvanceBalance = bal);
  }

  Future<void> _reloadAll() async {
    await ref.read(advanceProvider.notifier).loadAdvances(widget.employee.id);
    await _refreshGlBalance();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = _toDouble(_amountController.text);
    final note = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    final submittedType = _type;
    try {
      if (submittedType == 'repayment') {
        await ref.read(advanceProvider.notifier).repayAdvance(
              employeeId: widget.employee.id,
              amount: amount,
              method: _method,
              date: _date,
              note: note,
            );
      } else {
        final id = const Uuid().v4();
        final adv = Advance(
          id: id,
          employeeId: widget.employee.id,
          amount: amount,
          type: submittedType,
          date: _date,
          note: note,
          method: _method,
        );
        await ref
            .read(advanceProvider.notifier)
            .addAdvance(adv, method: _method);
      }

      await _reloadAll();

      _amountController.clear();
      _notesController.clear();
      setState(() {
        _type = 'advance';
        _method = 'cash';
        _date = DateTime.now();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(submittedType == 'repayment'
              ? 'تم تسجيل التسديد وربط GL'
              : 'تم الحفظ وربط GL')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل العملية: $e')));
    }
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('سيتم حذف السجل وعكس القيد المحاسبي إن وُجد.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref
            .read(advanceProvider.notifier)
            .deleteAdvance(id, widget.employee.id);
        await _reloadAll();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم الحذف وعكس GL')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
      }
    }
  }

  Future<void> _confirmReverse(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('عكس القيد المحاسبي'),
        content: const Text(
            'سيتم إنشاء قيد عكسي وإزالة الربط من هذا السجل. المتابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('عكس')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await AdvanceDatabaseService.reverseAdvance(id);
        await _reloadAll();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم عكس القيد وتحديث الرصيد')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل عكس القيد: $e')));
      }
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final dfFull = DateFormat('yyyy-MM-dd – HH:mm');
    final isDesktop = Responsive.isDesktop(context);
    final user = ref.watch(currentUserProvider);

    final all = ref.watch(advanceProvider);
    final employeeRows = all
        .where((a) => a.employeeId == widget.employee.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    bool matchFilter(Advance a) {
      if (_viewType != 'all' && a.type.toLowerCase() != _viewType) return false;
      if (_viewMethod != 'all' &&
          (a.method ?? '').toLowerCase() != _viewMethod) {
        return false;
      }
      if (_viewQuery.trim().isNotEmpty) {
        final q = _viewQuery.trim().toLowerCase();
        final hay = [
          a.id,
          a.method ?? '',
          a.note ?? '',
          a.employeeId,
          DateFormat('yyyy-MM-dd HH:mm').format(a.date),
          a.type
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }

    final items = employeeRows.where(matchFilter).toList();

    final totalAdvances = employeeRows
        .where((a) => a.type == 'advance')
        .fold<double>(0.0, (s, a) => s + a.amount);
    final totalRewards = employeeRows
        .where((a) => a.type == 'bonus')
        .fold<double>(0.0, (s, a) => s + a.amount);
    final totalRepayments = employeeRows
        .where((a) => a.type == 'repayment')
        .fold<double>(0.0, (s, a) => s + a.amount);

    final netAfterAdvances = widget.employee.baseSalary +
        widget.employee.allowances -
        widget.employee.deductions -
        (totalAdvances - totalRepayments);

    return Scaffold(
      drawer: isDesktop
          ? null
          : Drawer(
              child: YallaSidebar(currentRoute: '/employees/advances'),
            ),
      appBar: YallaAppBar(
        workshopName: user?.name ?? '',
        logoPath: user?.workshopLogoPath ?? '',
        showThemeToggle: true,
        showUserAvatar: false,
        showSearch: false,
        showNotifications: false,
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/employees/advances'),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reloadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header + KPIs
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('الموظف: ${widget.employee.fullName}',
                          style: Theme.of(context).textTheme.titleLarge),
                      _kpiChip(
                          label: 'إجمالي السلف',
                          value: totalAdvances,
                          color: Colors.red),
                      _kpiChip(
                          label: 'إجمالي المكافآت',
                          value: totalRewards,
                          color: Colors.green),
                      _kpiChip(
                          label: 'إجمالي التسديدات',
                          value: totalRepayments,
                          color: Colors.teal),
                      _kpiChip(
                          label: 'رصيد السلف (GL)',
                          value: _glAdvanceBalance,
                          color: Colors.deepPurple),
                      _kpiChip(
                          label: 'الصافي بعد السلف',
                          value: netAfterAdvances,
                          color: Colors.blue,
                          bold: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),

                  // Form
                  Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            value: _type,
                            items: const [
                              DropdownMenuItem(
                                  value: 'advance', child: Text('سلفة')),
                              DropdownMenuItem(
                                  value: 'bonus', child: Text('مكافأة')),
                              DropdownMenuItem(
                                  value: 'repayment',
                                  child: Text('تسديد سلفة')),
                            ],
                            onChanged: (v) =>
                                setState(() => _type = v ?? 'advance'),
                            decoration: InputDecoration(
                                labelText: 'النوع',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                  labelText: 'التاريخ',
                                  border: OutlineInputBorder()),
                              child: AdaptiveRow(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(df.format(_date)),
                                  const Icon(Icons.calendar_today)
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            value: _method,
                            items: const [
                              DropdownMenuItem(
                                  value: 'cash', child: Text('نقدي')),
                              DropdownMenuItem(
                                  value: 'bank', child: Text('بنك')),
                              DropdownMenuItem(
                                  value: 'cheque', child: Text('شيك')),
                              DropdownMenuItem(
                                  value: 'transfer', child: Text('تحويل')),
                            ],
                            onChanged: (v) =>
                                setState(() => _method = v ?? 'cash'),
                            decoration: InputDecoration(
                                labelText: 'طريقة الدفع',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: 'المبلغ',
                              prefixText: '${MoneyFormatter.symbol} ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final x = double.tryParse((v ?? '').trim());
                              if (x == null || x <= 0) return 'ادخل مبلغًا > 0';
                              return null;
                            },
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: TextFormField(
                            controller: _notesController,
                            decoration: InputDecoration(
                                labelText: 'ملاحظات (اختياري)',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _submit,
                            icon: const Icon(Icons.save),
                            label: Text(_type == 'repayment'
                                ? 'تسجيل تسديد وربط GL'
                                : 'حفظ وربط GL'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),

                  // View filters
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _viewType,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('الكل')),
                            DropdownMenuItem(
                                value: 'advance', child: Text('سلفة')),
                            DropdownMenuItem(
                                value: 'bonus', child: Text('مكافأة')),
                            DropdownMenuItem(
                                value: 'repayment', child: Text('تسديد سلفة')),
                          ],
                          onChanged: (v) =>
                              setState(() => _viewType = v ?? 'all'),
                          decoration: InputDecoration(
                              labelText: 'فلترة النوع',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _viewMethod,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('الكل')),
                            DropdownMenuItem(
                                value: 'cash', child: Text('نقدي')),
                            DropdownMenuItem(value: 'bank', child: Text('بنك')),
                            DropdownMenuItem(
                                value: 'cheque', child: Text('شيك')),
                            DropdownMenuItem(
                                value: 'transfer', child: Text('تحويل')),
                          ],
                          onChanged: (v) =>
                              setState(() => _viewMethod = v ?? 'all'),
                          decoration: InputDecoration(
                              labelText: 'طريقة الدفع',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      SizedBox(
                        width: 280,
                        child: TextFormField(
                          onChanged: (v) => setState(() => _viewQuery = v),
                          decoration: InputDecoration(
                            labelText: 'بحث (ID/ملاحظة/طريقة)',
                            hintText: 'اكتب نصًا للبحث',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _reloadAll,
                          icon: const Icon(Icons.refresh),
                          label: const Text('تحديث'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(),

                  // List
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text('لا يوجد سجلات وفق الفلاتر الحالية')),
                    )
                  else
                    (isDesktop
                        ? _buildDataTable(items, dfFull)
                        : _buildCards(items, dfFull)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== UI helpers =====

  Widget _kpiChip({
    required String label,
    required double value,
    required Color color,
    bool bold = false,
  }) {
    final style = TextStyle(
        color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500);
    return Chip(
      label: Text('$label: ${MoneyFormatter.format(value)}', style: style),
      side: BorderSide(color: color.withOpacity(0.4)),
      backgroundColor: color.withOpacity(0.06),
    );
  }

  Widget _buildCards(List<Advance> items, DateFormat dfFull) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final a = items[i];
        final (label, icon, color) = _labelIconForType(a.type);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          title: Text('$label — ${MoneyFormatter.format(a.amount)}'),
          subtitle: Text([
            dfFull.format(a.date),
            if ((a.note ?? '').isNotEmpty) a.note!,
            if ((a.method ?? '').isNotEmpty) '(${a.method})',
          ].join('  •  ')),
          trailing: Wrap(
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'عكس القيد',
                icon: const Icon(Icons.rotate_left, color: Colors.orange),
                onPressed: () => _confirmReverse(a.id),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDelete(a.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDataTable(List<Advance> items, DateFormat dfFull) {
    final rows = items.map((a) {
      final (label, _, color) = _labelIconForType(a.type);
      return DataRow(cells: [
        DataCell(Text(a.id.length > 8 ? a.id.substring(0, 8) : a.id)),
        DataCell(Text(label, style: TextStyle(color: color))),
        DataCell(Text('${MoneyFormatter.format(a.amount)}')),
        DataCell(Text(dfFull.format(a.date))),
        DataCell(Text(a.method ?? '—')),
        DataCell(Text(a.note ?? '—')),
        DataCell(
          AdaptiveRow(
            children: [
              IconButton(
                tooltip: 'عكس القيد',
                icon: const Icon(Icons.rotate_left, color: Colors.orange),
                onPressed: () => _confirmReverse(a.id),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDelete(a.id),
              ),
            ],
          ),
        ),
      ]);
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('النوع')),
          DataColumn(label: Text('المبلغ')),
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الطريقة')),
          DataColumn(label: Text('ملاحظات')),
          DataColumn(label: Text('إجراءات')),
        ],
        rows: rows,
      ),
    );
  }

  (String, IconData, Color) _labelIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'bonus':
        return ('مكافأة', Icons.card_giftcard, Colors.green);
      case 'repayment':
        return ('تسديد سلفة', Icons.reply, Colors.teal);
      default:
        return ('سلفة', Icons.arrow_upward, Colors.red);
    }
  }
}
