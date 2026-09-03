// 📁 lib/features/repairs/screens/vehicles_arrears_screen.dart
//
// VehiclesArrearsScreen — ذمم المركبات (بيانات حقيقية فقط)
// - مصدر المدفوع: journal_entries (credit على حساب "العملاء") مع relatedRepairId.
// - يجلب ملفات الإصلاح من جدول repairs ويحسب المتبقي بدقة.
// - فلترة بالتاريخ + نوع المستفيد (الكل/تأمين/أفراد) + بحث.
// - عرض متجاوب: جدول على الديسكتوب وبطاقات على الشاشات الصغيرة.
// - زر "عرض" يفتح RepairDetailsScreen بعد جلب الـ Repair من DB.
//
// ملاحظة:
// لا يستخدم أي بيانات وهمية. إذا لم يوجد جدول اليومية تظهر القيم 0 كمدفوع.
//
// يعتمد وجود الأعمدة في repairs:
// id, vehicleType, vehicleModel, vehicleNumber, beneficiaryType, beneficiaryName,
// receivedDate (TEXT), totalFileValue (REAL)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class VehiclesArrearsScreen extends StatefulWidget {
  const VehiclesArrearsScreen({super.key});

  @override
  State<VehiclesArrearsScreen> createState() => _VehiclesArrearsScreenState();
}

class _VehiclesArrearsScreenState extends State<VehiclesArrearsScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _currency = NumberFormat('#,##0.00', 'ar');

  bool _loading = true;
  String? _error;

  // فلاتر
  final _searchCtrl = TextEditingController();
  DateTimeRange? _range;
  String _type = 'الكل'; // الكل / تأمين / أفراد

  // بيانات معروضة
  List<_ArRow> _rows = [];

  // إجماليات سريعة
  double get _sumRemaining => _rows.fold(0.0, (s, r) => s + r.remaining);
  int get _countUnpaid => _rows.where((r) => r.status == 'غير مسدد').length;
  int get _countPartial => _rows.where((r) => r.status == 'مسدد جزئي').length;
  int get _countPaid => _rows.where((r) => r.status == 'مسدد').length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Database> _db() async => DBService.database;

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table]);
    return rows.isNotEmpty;
  }

  Future<double> _paidFromJournal(Database db, String repairId) async {
    if (!await _tableExists(db, 'journal_entries')) return 0.0;
    // نعتمد أن الدفعة تُسجل كـ credit على حساب "العملاء"
    // (يمكنك توسيع قائمة الأسماء إن لزم)
    const account = 'العملاء';
    final rows = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(credit),0) AS paid
      FROM journal_entries
      WHERE relatedRepairId = ?
        AND accountName = ?
      ''',
      [repairId, account],
    );
    return rows.isEmpty
        ? 0.0
        : ((rows.first['paid'] as num?)?.toDouble() ?? 0.0);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await _db();

      // نبني شرط WHERE لجدول repairs
      final where = <String>[];
      final args = <dynamic>[];

      // نوع المستفيد
      if (_type == 'تأمين') {
        where.add('beneficiaryType = ?');
        args.add('شركة تأمين');
      } else if (_type == 'أفراد') {
        where.add('beneficiaryType = ?');
        args.add('أفراد');
      }

      // نطاق التاريخ (على receivedDate)
      if (_range != null) {
        where.add('receivedDate BETWEEN ? AND ?');
        args.add(_range!.start.toIso8601String());
        // نهاية اليوم
        args.add(DateTime(_range!.end.year, _range!.end.month, _range!.end.day,
                23, 59, 59)
            .toIso8601String());
      }

      // بحث نصي
      final q = _searchCtrl.text.trim();
      if (q.isNotEmpty) {
        where.add(
            '(vehicleNumber LIKE ? OR vehicleType LIKE ? OR vehicleModel LIKE ? OR beneficiaryName LIKE ?)');
        final like = '%$q%';
        args.addAll([like, like, like, like]);
      }

      final sql = StringBuffer(
          'SELECT id, vehicleType, vehicleModel, vehicleNumber, beneficiaryType, beneficiaryName, receivedDate, totalFileValue FROM repairs');
      if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');
      sql.write(' ORDER BY receivedDate DESC');

      final repairs = await db.rawQuery(sql.toString(), args);

      // حوّل لكل صف + احسب المدفوع من اليومية والمتبقي
      final list = <_ArRow>[];
      for (final m in repairs) {
        final id = (m['id'] ?? '').toString();
        final vt = (m['vehicleType'] ?? '').toString();
        final vm = (m['vehicleModel'] ?? '').toString();
        final vn = (m['vehicleNumber'] ?? '').toString();
        final bt = (m['beneficiaryType'] ?? '').toString();
        final bn = (m['beneficiaryName'] ?? '').toString();
        final rdRaw = (m['receivedDate'] ?? '').toString();
        final rd = DateTime.tryParse(rdRaw) ?? DateTime(1970, 1, 1);
        final total = (m['totalFileValue'] as num?)?.toDouble() ?? 0.0;

        final paid = await _paidFromJournal(db, id);
        final remaining = (total - paid).clamp(-0.0, double.infinity);
        final status =
            remaining <= 0.0 ? 'مسدد' : (paid > 0 ? 'مسدد جزئي' : 'غير مسدد');

        list.add(_ArRow(
          repairId: id,
          title: '$vt — $vn',
          vehicleModel: vm,
          beneficiaryType: bt,
          beneficiaryName: bn,
          receivedDate: rd,
          total: total,
          paid: paid,
          remaining: remaining,
          status: status,
        ));
      }

      // الأحدث أولاً + أعلى متبقي على السطح
      list.sort((a, b) {
        final byRemain = b.remaining.compareTo(a.remaining);
        if (byRemain != 0) return byRemain;
        return b.receivedDate.compareTo(a.receivedDate);
      });

      _rows = list;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final dr = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (dr != null) {
      setState(() {
        _range = DateTimeRange(
          start: dr.start,
          end: DateTime(dr.end.year, dr.end.month, dr.end.day, 23, 59, 59),
        );
      });
      await _load();
    }
  }

  void _clearRange() {
    setState(() => _range = null);
    _load();
  }

  Future<void> _openDetails(String repairId) async {
    try {
      final repair = await RepairDatabaseService.getRepairById(repairId);
      if (!mounted) return;
      if (repair == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر جلب ملف الإصلاح')),
        );
        return;
      }
      Navigator.of(context)
          .pushNamed(AppRoutes.repairDetail, arguments: repair);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ فتح التفاصيل: $e')));
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: AppRoutes.vehiclesArrears),
            ),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('💳 ذمم المركبات',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              color: Colors.white),
        ],
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: AppRoutes.vehiclesArrears),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'حدث خطأ أثناء تحميل البيانات:\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          // ===== Toolbar =====
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 520),
                                  child: TextField(
                                    inputFormatters: const [
                                      YallaDigitNormalizer()
                                    ],
                                    controller: _searchCtrl,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      hintText:
                                          'بحث بالرقم/النوع/الموديل/اسم المستفيد…',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onSubmitted: (_) => _load(),
                                  ),
                                ),
                                Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    DropdownButton<String>(
                                      value: _type,
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'الكل', child: Text('الكل')),
                                        DropdownMenuItem(
                                            value: 'تأمين',
                                            child: Text('تأمين')),
                                        DropdownMenuItem(
                                            value: 'أفراد',
                                            child: Text('أفراد')),
                                      ],
                                      onChanged: (v) {
                                        setState(() => _type = v ?? 'الكل');
                                        _load();
                                      },
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _pickRange,
                                      icon: const Icon(Icons.date_range),
                                      label: Text(_range == null
                                          ? 'كل التواريخ'
                                          : '${_df.format(_range!.start)} → ${_df.format(_range!.end)}'),
                                    ),
                                    if (_range != null)
                                      IconButton(
                                          onPressed: _clearRange,
                                          icon: const Icon(Icons.clear)),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // ===== KPIs =====
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 12,
                                children: [
                                  _chipStat('الإجمالي المتبقي',
                                      _currency.format(_sumRemaining)),
                                  _chipStat('غير مسدد', _countUnpaid.toString(),
                                      color: Colors.red),
                                  _chipStat(
                                      'مسدد جزئي', _countPartial.toString(),
                                      color: Colors.orange),
                                  _chipStat('مسدد', _countPaid.toString(),
                                      color: Colors.green),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // ===== Content =====
                          Expanded(
                            child: Responsive.isDesktop(context)
                                ? _buildTable()
                                : _buildCards(),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chipStat(String label, String value, {Color? color}) {
    return Chip(
      backgroundColor: Colors.grey.shade100,
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final columns = [
      'الحالة',
      'المتبقي',
      'المدفوع',
      'قيمة الملف',
      'المستفيد',
      'ملف الإصلاح',
      'التاريخ',
      'تفاصيل',
    ];

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 980),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: AdaptiveDataTable(
                columnSpacing: 20,
                headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                rows: _rows.map((r) {
                  final statusColor = r.status == 'مسدد'
                      ? Colors.green
                      : (r.status == 'مسدد جزئي' ? Colors.orange : Colors.red);
                  return DataRow(cells: [
                    DataCell(Text(r.status,
                        style: TextStyle(
                            color: statusColor, fontWeight: FontWeight.w600))),
                    DataCell(Text(_currency.format(r.remaining),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text(_currency.format(r.paid))),
                    DataCell(Text(_currency.format(r.total))),
                    DataCell(
                        Text('${r.beneficiaryType} — ${r.beneficiaryName}')),
                    DataCell(Text(r.title)),
                    DataCell(Text(_df.format(r.receivedDate))),
                    DataCell(
                      TextButton(
                        onPressed: () => _openDetails(r.repairId),
                        child: const Text('عرض'),
                      ),
                    ),
                  ]);
                }).toList(),
                columns:
                    columns.map((c) => DataColumn(label: Text(c))).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCards() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final statusColor = r.status == 'مسدد'
            ? Colors.green
            : (r.status == 'مسدد جزئي' ? Colors.orange : Colors.red);

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdaptiveRow(children: [
                  Expanded(
                    child: Text(r.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Text(_df.format(r.receivedDate)),
                ]),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _kv('المستفيد',
                        '${r.beneficiaryType} — ${r.beneficiaryName}'),
                    _kv('قيمة الملف', _currency.format(r.total)),
                    _kv('المدفوع', _currency.format(r.paid)),
                    _kv('المتبقي', _currency.format(r.remaining), bold: true),
                    Chip(
                      label: Text(r.status,
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _openDetails(r.repairId),
                    child: const Text('عرض'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    return AdaptiveRow(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v,
            style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w400)),
      ],
    );
  }
}

class _ArRow {
  final String repairId;
  final String title; // "نوع — رقم"
  final String vehicleModel;
  final String beneficiaryType;
  final String beneficiaryName;
  final DateTime receivedDate;
  final double total;
  final double paid;
  final double remaining;
  final String status; // مسدد / مسدد جزئي / غير مسدد

  _ArRow({
    required this.repairId,
    required this.title,
    required this.vehicleModel,
    required this.beneficiaryType,
    required this.beneficiaryName,
    required this.receivedDate,
    required this.total,
    required this.paid,
    required this.remaining,
    required this.status,
  });
}
