// 📁 lib/features/employees/screens/advances_report_screen.dart
//
// AdvancesReportScreen — تقرير السلف/المكافآت/التسديدات (DB v30)
// - مصدر البيانات: AdvanceDatabaseService.listAll()
// - فلاتر: التاريخ (من/إلى)، النوع، الطريقة، موظف (ID نصي)، حد أعلى للصفوف
// - KPIs: إجمالي السلف، المكافآت، التسديدات، الصافي = (السلف - التسديدات)
// - عرض: DataTable على الديسكتوب وبطاقات على الموبايل
//
// لا يعتمد على Riverpod؛ يستدعي الخدمة مباشرةً. متوافق مع AppRoutes.reportsAdvances.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/employees/services/advance_database_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class AdvancesReportScreen extends StatefulWidget {
  const AdvancesReportScreen({super.key});

  @override
  State<AdvancesReportScreen> createState() => _AdvancesReportScreenState();
}

class _AdvancesReportScreenState extends State<AdvancesReportScreen> {
  final _df = DateFormat('yyyy-MM-dd');

  // فلاتر
  DateTime? _from;
  DateTime? _to;
  String _type = 'all'; // all | advance | bonus | repayment
  String _method = 'all'; // all | cash | bank | cheque | transfer
  String _employeeId = ''; // نصي
  int _limit = 500;

  // بيانات
  List<Advance> _rows = const [];
  bool _loading = false;

  // KPIs
  double _sumAdv = 0, _sumBonus = 0, _sumRepay = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime(now.year, now.month, 1),
      firstDate: DateTime(now.year - 4, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'من تاريخ',
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime(now.year, now.month + 1, 0),
      firstDate: DateTime(now.year - 4, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'إلى تاريخ',
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    // 1) اجلب الكل ثم طبق الفلاتر محليًا
    final all = await AdvanceDatabaseService.listAll();

    // 2) فلترة
    bool okByDate(DateTime d) {
      if (_from != null &&
          d.isBefore(DateTime(_from!.year, _from!.month, _from!.day))) {
        return false;
      }
      if (_to != null &&
          d.isAfter(DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59))) {
        return false;
      }
      return true;
    }

    final filtered = all.where((a) {
      if (!okByDate(a.date)) return false;
      if (_type != 'all' && a.type.toLowerCase() != _type) return false;
      if (_method != 'all' && (a.method ?? '').toLowerCase() != _method) {
        return false;
      }
      if (_employeeId.trim().isNotEmpty &&
          !a.employeeId
              .toLowerCase()
              .contains(_employeeId.trim().toLowerCase())) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    // 3) حد أعلى
    final limited = filtered.take(_limit).toList(growable: false);

    // 4) KPIs
    double s(String t) => limited
        .where((x) => x.type.toLowerCase() == t)
        .fold<double>(0.0, (s, x) => s + x.amount);

    setState(() {
      _rows = limited;
      _sumAdv = s('advance');
      _sumBonus = s('bonus');
      _sumRepay = s('repayment');
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final net = (_sumAdv - _sumRepay);

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/reports/advances'),
            ),
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName: 'تقارير الموظفين',
          actions: [],
        ),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/reports/advances'),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // KPIs
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _kpi('إجمالي السلف', _sumAdv, Colors.red),
                      _kpi('إجمالي المكافآت', _sumBonus, Colors.green),
                      _kpi('إجمالي التسديدات', _sumRepay, Colors.teal),
                      _kpi('صافي السلف = سلف − تسديد', net, Colors.blue,
                          bold: true),
                      Chip(
                        label: Text('عدد السطور: ${_rows.length}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),

                  // Filters
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      _dateBox('من', _from, _pickFrom),
                      _dateBox('إلى', _to, _pickTo),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _type,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('الكل')),
                            DropdownMenuItem(
                                value: 'advance', child: Text('سلفة')),
                            DropdownMenuItem(
                                value: 'bonus', child: Text('مكافأة')),
                            DropdownMenuItem(
                                value: 'repayment', child: Text('تسديد سلفة')),
                          ],
                          onChanged: (v) => setState(() => _type = v ?? 'all'),
                          decoration: InputDecoration(
                            labelText: 'النوع',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _method,
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
                              setState(() => _method = v ?? 'all'),
                          decoration: InputDecoration(
                            labelText: 'الطريقة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextFormField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          decoration: InputDecoration(
                            labelText: 'موظف (ID يحتوي)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _employeeId = v,
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: _limit,
                          items: const [
                            DropdownMenuItem(value: 100, child: Text('100')),
                            DropdownMenuItem(value: 200, child: Text('200')),
                            DropdownMenuItem(value: 500, child: Text('500')),
                            DropdownMenuItem(value: 1000, child: Text('1000')),
                          ],
                          onChanged: (v) => setState(() => _limit = v ?? 500),
                          decoration: InputDecoration(
                            labelText: 'حد الصفوف',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _refresh,
                          icon: const Icon(Icons.filter_alt),
                          label: const Text('تطبيق الفلاتر'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('لا توجد بيانات وفق الفلاتر')),
                    )
                  else
                    (Responsive.isDesktop(context)
                        ? _buildTable(_rows)
                        : _buildCards(_rows)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Widgets =====

  Widget _dateBox(String label, DateTime? val, Future<void> Function() onTap) {
    return SizedBox(
      width: 200,
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: AdaptiveRow(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(val == null ? '—' : _df.format(val)),
              const Icon(Icons.date_range),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpi(String label, double value, Color color, {bool bold = false}) {
    return Chip(
      label: Text(
        '$label: ${MoneyFormatter.format(value)}',
        style: TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      side: BorderSide(color: color.withOpacity(0.35)),
      backgroundColor: color.withOpacity(0.06),
    );
  }

  Widget _buildCards(List<Advance> items) {
    final dff = DateFormat('yyyy-MM-dd – HH:mm');
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final a = items[i];
        final (label, icon, color) = _labelIconForType(a.type);
        return ListTile(
          leading: CircleAvatar(
            foregroundColor: color,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon),
          ),
          title: Text('$label — ${MoneyFormatter.format(a.amount)}'),
          subtitle: Text([
            'Emp: ${a.employeeId}',
            dff.format(a.date),
            if ((a.method ?? '').isNotEmpty) '(${a.method})',
            if ((a.note ?? '').isNotEmpty) a.note!,
          ].join('  •  ')),
        );
      },
    );
  }

  Widget _buildTable(List<Advance> items) {
    final dff = DateFormat('yyyy-MM-dd HH:mm');
    final rows = items.map((a) {
      final (label, _, color) = _labelIconForType(a.type);
      return DataRow(
        cells: [
          DataCell(Text(a.id.length > 8 ? a.id.substring(0, 8) : a.id)),
          DataCell(Text(a.employeeId)),
          DataCell(Text(label, style: TextStyle(color: color))),
          DataCell(Text('${MoneyFormatter.format(a.amount)}')),
          DataCell(Text(dff.format(a.date))),
          DataCell(Text(a.method ?? '—')),
          DataCell(Text(a.note ?? '—')),
        ],
      );
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Employee')),
          DataColumn(label: Text('النوع')),
          DataColumn(label: Text('المبلغ')),
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الطريقة')),
          DataColumn(label: Text('ملاحظة')),
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
