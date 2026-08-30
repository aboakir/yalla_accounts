// 📁 lib/features/finance/reports/screens/ar_aging_screen.dart
//
// أعمار الذمم — AR Aging (v29 / FIFO per client)
// -----------------------------------------------
// - "حتى تاريخ" مع توزيع FIFO: نستهلك المدفوعات الأقدم فالأحدث على مستوى العميل.
// - تبويبات نوع العميل: الكل / أفراد / شركة تأمين.
// - بحث باسم العميل.
// - ترتيب أعمدة مع مؤشرات، افتراضي: المتبقي تنازلي.
// - مجاميع أعلى الشاشة + ألوان دلالية.
// - DataTable للديسكتوب + كروت للموبايل.
// - تصدير CSV لما هو ظاهر.
// - يعتمد جداول DBService v29: clients, invoices, payments.
// - بدون RTL إجباري؛ يتبع إعداد التطبيق.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ARAgingScreen extends StatefulWidget {
  const ARAgingScreen({super.key});
  @override
  State<ARAgingScreen> createState() => _ARAgingScreenState();
}

class _ARAgingScreenState extends State<ARAgingScreen>
    with SingleTickerProviderStateMixin {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  late final TabController _tabs;

  DateTime _asOf = DateTime.now();
  String _query = '';

  bool _loading = true;
  String? _error;

  // بيانات
  List<_Row> _all = [];
  List<_Row> _filtered = [];

  // مجاميع
  double _sumInv = 0, _sumPaid = 0, _sumRemain = 0;
  double _sumB0 = 0, _sumB30 = 0, _sumB60 = 0, _sumB90 = 0;

  // ترتيب
  String _sortKey = 'remain'; // remain|client|type|invoice|paid|b0|b30|b60|b90
  bool _sortDesc = true;

  // واجهة
  bool _showSidebar = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_applyFilters);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _pickAsOf() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() => _asOf = DateTime(d.year, d.month, d.day, 23, 59, 59));
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _all = [];
      _resetSums();
    });

    try {
      final db = await DBService.database;

      // وجود الجداول
      Future<bool> exists(String t) async => (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [t],
          ))
              .isNotEmpty;
      if (!await exists('clients') || !await exists('invoices')) {
        setState(() {
          _loading = false;
          _error = 'جداول العملاء/الفواتير غير موجودة.';
        });
        return;
      }
      final hasPay = await exists('payments');

      // خريطة نوع العميل
      final typesRows = await db.rawQuery('SELECT id, type FROM clients');
      final typeById = <int, String>{};
      for (final m in typesRows) {
        final id = (m['id'] as num).toInt();
        final t = (m['type'] ?? '').toString().toLowerCase();
        final norm = (t == 'insurance' || t == 'شركة تأمين' || t == 'تأمين')
            ? 'شركة تأمين'
            : 'أفراد';
        typeById[id] = norm;
      }

      // العملاء الذين لديهم فواتير
      final cliMaps = await db.rawQuery('''
        SELECT DISTINCT c.id AS id, c.name AS name
        FROM clients c
        JOIN invoices i ON i.client_id = c.id
        ORDER BY LOWER(c.name) ASC
      ''');

      for (final m in cliMaps) {
        final cid = (m['id'] as num).toInt();
        final cname = (m['name'] ?? '').toString();
        final ctype = typeById[cid] ?? 'أفراد';

        // فواتير حتى asOf
        final invs = await db.rawQuery('''
          SELECT id, date, total
          FROM invoices
          WHERE client_id = ? AND date <= ?
          ORDER BY date ASC, id ASC
        ''', [cid, _asOf.toIso8601String()]);
        if (invs.isEmpty) continue;

        final invoiceList = invs
            .map((e) => _Invoice(
                  id: (e['id'] ?? '').toString(),
                  date: DateTime.tryParse((e['date'] ?? '').toString()) ??
                      DateTime(1970, 1, 1),
                  total: _toD(e['total']),
                ))
            .toList();

        // مجموع مدفوعات العميل حتى asOf
        double paid = 0.0;
        if (hasPay) {
          final pay = await db.rawQuery('''
            SELECT IFNULL(SUM(amount),0) AS s
            FROM payments
            WHERE client_id = ? AND date <= ?
          ''', [cid, _asOf.toIso8601String()]);
          paid = _toD(pay.first['s']);
        }

        // إجمالي الفواتير
        final invTotal =
            invoiceList.fold<double>(0, (s, i) => s + (i.total ?? 0));

        // FIFO per client
        double remainingPaid = paid;
        final pending = <_Pending>[];
        for (final inv in invoiceList) {
          final invAmt = inv.total ?? 0;
          final covered = remainingPaid >= invAmt
              ? invAmt
              : (remainingPaid > 0 ? remainingPaid : 0);
          final left = ((invAmt - covered).clamp(0, 1e15)).toDouble();
          remainingPaid -= covered;
          if (left > 0) pending.add(_Pending(date: inv.date, amount: left));
        }

        // سلال الأعمار
        double b0 = 0, b30 = 0, b60 = 0, b90 = 0;
        for (final p in pending) {
          final days = _daysDiff(_asOf, p.date);
          if (days <= 30) {
            b0 += p.amount;
          } else if (days <= 60) {
            b30 += p.amount;
          } else if (days <= 90) {
            b60 += p.amount;
          } else {
            b90 += p.amount;
          }
        }

        final remain = pending.fold<double>(0, (s, x) => s + x.amount);

        _all.add(_Row(
          clientId: cid,
          clientName: cname,
          clientType: ctype,
          invoicesTotal: invTotal,
          paidTotal: paid.clamp(0, invTotal).toDouble(),
          remainTotal: remain,
          bucket0_30: b0,
          bucket31_60: b30,
          bucket61_90: b60,
          bucket90p: b90,
        ));
      }

      _applyFilters();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    final q = _query.trim().toLowerCase();
    final tab = _tabs.index; // 0: الكل, 1: أفراد, 2: شركة تأمين

    _filtered = _all.where((r) {
      if (q.isNotEmpty && !r.clientName.toLowerCase().contains(q)) return false;
      if (tab == 1 && r.clientType != 'أفراد') return false;
      if (tab == 2 && r.clientType != 'شركة تأمين') return false;
      return true;
    }).toList();

    _sortNow();
    _recomputeSums();
    setState(() {});
  }

  void _sortNow() {
    int cmpNum(num a, num b) => a.compareTo(b);
    int cmpStr(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    _filtered.sort((a, b) {
      int r;
      switch (_sortKey) {
        case 'client':
          r = cmpStr(a.clientName, b.clientName);
          break;
        case 'type':
          r = cmpStr(a.clientType, b.clientType);
          break;
        case 'invoice':
          r = cmpNum(a.invoicesTotal, b.invoicesTotal);
          break;
        case 'paid':
          r = cmpNum(a.paidTotal, b.paidTotal);
          break;
        case 'b0':
          r = cmpNum(a.bucket0_30, b.bucket0_30);
          break;
        case 'b30':
          r = cmpNum(a.bucket31_60, b.bucket31_60);
          break;
        case 'b60':
          r = cmpNum(a.bucket61_90, b.bucket61_90);
          break;
        case 'b90':
          r = cmpNum(a.bucket90p, b.bucket90p);
          break;
        case 'remain':
        default:
          r = cmpNum(a.remainTotal, b.remainTotal);
      }
      return _sortDesc ? -r : r;
    });
  }

  void _toggleSort(String key) {
    if (_sortKey == key) {
      _sortDesc = !_sortDesc;
    } else {
      _sortKey = key;
      _sortDesc =
          (key != 'client' && key != 'type'); // أرقام تنازلي، نصوص تصاعدي
    }
    _sortNow();
    setState(() {});
  }

  void _recomputeSums() {
    _resetSums();
    for (final r in _filtered) {
      _sumInv += r.invoicesTotal;
      _sumPaid += r.paidTotal;
      _sumRemain += r.remainTotal;
      _sumB0 += r.bucket0_30;
      _sumB30 += r.bucket31_60;
      _sumB60 += r.bucket61_90;
      _sumB90 += r.bucket90p;
    }
  }

  void _resetSums() {
    _sumInv = _sumPaid = _sumRemain = 0;
    _sumB0 = _sumB30 = _sumB60 = _sumB90 = 0;
  }

  // ===== Helpers =====

  double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int _daysDiff(DateTime asOf, DateTime date) {
    final a = DateTime(asOf.year, asOf.month, asOf.day);
    final d = DateTime(date.year, date.month, date.day);
    final raw = a.difference(d).inDays;
    if (raw < 0) return 0;
    if (raw > 100000) return 100000;
    return raw;
  }

  Future<void> _exportCsv() async {
    try {
      final sb = StringBuffer()
        ..writeln(
            'client,type,invoices_total,paid,remain,0_30,31_60,61_90,90_plus');
      for (final r in _filtered) {
        sb.writeln([
          r.clientName.replaceAll(',', ' '),
          r.clientType == 'شركة تأمين' ? 'Insurance' : 'Individual',
          r.invoicesTotal.toStringAsFixed(2),
          r.paidTotal.toStringAsFixed(2),
          r.remainTotal.toStringAsFixed(2),
          r.bucket0_30.toStringAsFixed(2),
          r.bucket31_60.toStringAsFixed(2),
          r.bucket61_90.toStringAsFixed(2),
          r.bucket90p.toStringAsFixed(2),
        ].join(','));
      }
      final dir = await getDownloadsDirectory();
      final path =
          '${dir?.path ?? (await getTemporaryDirectory()).path}/ar_aging_${_df.format(_asOf)}.csv';
      final file = File(path);
      await file.writeAsString(sb.toString(), encoding: utf8);
      await Share.shareXFiles([XFile(file.path)], text: 'AR Aging Export');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير CSV: $e')),
      );
    }
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    const currentRoute = '/reports/ar-aging';

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: AdaptiveRow(
        children: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          const Text(
            'أعمار الذمم (عملاء)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _chip(label: _df.format(_asOf), icon: Icons.event, onTap: _pickAsOf),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: TextField(
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: 'بحث باسم العميل…',
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) {
                _query = v;
                _applyFilters();
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _filtered.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.download_rounded),
            label: const Text('CSV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );

    final totals = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _stat('إجمالي الفواتير', _sumInv, Colors.blueGrey),
          _stat('المدفوع', _sumPaid, Colors.green),
          _stat('المتبقي', _sumRemain, Colors.red, bold: true),
          _stat('0-30', _sumB0, Colors.black87),
          _stat('31-60', _sumB30, Colors.black87),
          _stat('61-90', _sumB60, Colors.black87),
          _stat('+90', _sumB90, Colors.black87),
        ],
      ),
    );

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'تعذر تحميل البيانات:\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            : _filtered.isEmpty
                ? const _EmptyState(
                    icon: Icons.receipt_long,
                    title: 'لا توجد ذمم ضمن الفلاتر الحالية',
                    subtitle: 'جرّب تغيير تاريخ "حتى" أو البحث أو التبويب.',
                  )
                : (isDesktop ? _table() : _cards());

    return Scaffold(
      drawer: isDesktop || _showSidebar
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      appBar: isDesktop
          ? AppBar(
              backgroundColor: AppColors.primary,
              title: const Text(''),
              leading: IconButton(
                tooltip: _showSidebar ? 'إخفاء القائمة' : 'إظهار القائمة',
                icon: Icon(_showSidebar ? Icons.chevron_right : Icons.menu),
                onPressed: () => setState(() => _showSidebar = !_showSidebar),
              ),
            )
          : null,
      body: AdaptiveRow(
        children: [
          if (isDesktop && _showSidebar)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: currentRoute),
            ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  header,
                  totals,
                  Material(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabs,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.grey,
                      tabs: const [
                        Tab(text: 'الكل'),
                        Tab(text: 'أفراد'),
                        Tab(text: 'شركة تأمين'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Desktop Table =====
  Widget _table() {
    DataColumn col(String title, String key) {
      final isActive = _sortKey == key;
      final isNumeric = const {
        'invoice',
        'paid',
        'remain',
        'b0',
        'b30',
        'b60',
        'b90'
      }.contains(key);
      return DataColumn(
        label: InkWell(
          onTap: () => _toggleSort(key),
          child: AdaptiveRow(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (isActive) ...[
                const SizedBox(width: 4),
                Icon(_sortDesc ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 14),
              ]
            ],
          ),
        ),
        numeric: isNumeric,
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 0),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: AdaptiveDataTable(
                headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                columns: [
                  col('العميل', 'client'),
                  col('النوع', 'type'),
                  col('إجمالي الفواتير', 'invoice'),
                  col('المدفوع', 'paid'),
                  col('المتبقي', 'remain'),
                  col('0-30', 'b0'),
                  col('31-60', 'b30'),
                  col('61-90', 'b60'),
                  col('+90', 'b90'),
                ],
                rows: _filtered.map((r) {
                  return DataRow(
                    cells: [
                      DataCell(Text(r.clientName, textAlign: TextAlign.right)),
                      DataCell(Text(r.clientType)),
                      DataCell(Text(_money.format(r.invoicesTotal))),
                      DataCell(Text(_money.format(r.paidTotal),
                          style: const TextStyle(color: Colors.green))),
                      DataCell(Text(_money.format(r.remainTotal),
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold))),
                      DataCell(Text(_money.format(r.bucket0_30))),
                      DataCell(Text(_money.format(r.bucket31_60))),
                      DataCell(Text(_money.format(r.bucket61_90))),
                      DataCell(Text(_money.format(r.bucket90p))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Mobile Cards =====
  Widget _cards() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _filtered[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(r.clientName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    Chip(
                        backgroundColor: Colors.grey.shade200,
                        label: Text(r.clientType)),
                    Chip(
                        backgroundColor: Colors.grey.shade100,
                        label:
                            Text('إجمالي: ${_money.format(r.invoicesTotal)}')),
                    Chip(
                        backgroundColor: Colors.green.shade100,
                        label: Text('مدفوع: ${_money.format(r.paidTotal)}')),
                    Chip(
                        backgroundColor: Colors.red.shade100,
                        label: Text('متبقي: ${_money.format(r.remainTotal)}')),
                  ],
                ),
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    Chip(label: Text('0-30: ${_money.format(r.bucket0_30)}')),
                    Chip(label: Text('31-60: ${_money.format(r.bucket31_60)}')),
                    Chip(label: Text('61-90: ${_money.format(r.bucket61_90)}')),
                    Chip(label: Text('+90: ${_money.format(r.bucket90p)}')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stat(String label, double value, Color color, {bool bold = false}) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            _money.format(value),
            style: TextStyle(
                color: color,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _chip(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Chip(
        backgroundColor: AppColors.primary,
        labelPadding: const EdgeInsetsDirectional.only(start: 8, end: 10),
        label: AdaptiveRow(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ===== نماذج داخلية =====

class _Invoice {
  final String id;
  final DateTime date;
  final double? total;
  _Invoice({required this.id, required this.date, required this.total});
}

class _Pending {
  final DateTime date;
  final double amount;
  _Pending({required this.date, required this.amount});
}

class _Row {
  final int clientId;
  final String clientName;
  final String clientType; // 'أفراد' | 'شركة تأمين'
  final double invoicesTotal;
  final double paidTotal;
  final double remainTotal;
  final double bucket0_30;
  final double bucket31_60;
  final double bucket61_90;
  final double bucket90p;

  _Row({
    required this.clientId,
    required this.clientName,
    required this.clientType,
    required this.invoicesTotal,
    required this.paidTotal,
    required this.remainTotal,
    required this.bucket0_30,
    required this.bucket31_60,
    required this.bucket61_90,
    required this.bucket90p,
  });
}

// ===== حالة فراغ =====

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 76, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
