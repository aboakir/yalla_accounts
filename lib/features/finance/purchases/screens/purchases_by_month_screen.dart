// 📁 lib/features/finance/purchases/screens/purchases_by_month_screen.dart
//
// PurchasesByMonthScreen — تجميع مشتريات شهري من GL + مقارنة YoY
// المصدر: GL على حساب 1400 (debit) من قيود source='PURCHASE'

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class PurchasesByMonthScreen extends StatefulWidget {
  const PurchasesByMonthScreen({super.key});

  @override
  State<PurchasesByMonthScreen> createState() => _PurchasesByMonthScreenState();
}

class _PurchasesByMonthScreenState extends State<PurchasesByMonthScreen> {
  bool _loading = true;
  int _months = 12; // 6 / 12 / 24
  final _nf = NumberFormat('#,##0.00');

  // rows: [{ym, total, yoy, prev}]
  List<_Row> _rows = [];
  double _sumPeriod = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows = [];
      _sumPeriod = 0;
    });

    final db = await DBService.database;

    // احصل على id حساب 1400
    final acc1400 = await DBService.getAccountIdByCode('1400');
    if (acc1400 == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حساب 1400 غير موجود')),
      );
      return;
    }

    // اجلب آخر N أشهر (من GL)
    final rows = await db.rawQuery('''
      SELECT 
        substr(e.date,1,7) AS ym,
        IFNULL(SUM(l.debit),0) AS total
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? AND e.source = 'PURCHASE'
      GROUP BY ym
      ORDER BY ym DESC
      LIMIT ?
    ''', [acc1400, _months]);

    // خريطة ym -> total
    final Map<String, double> map = {};
    for (final r in rows) {
      final ym = r['ym']?.toString() ?? '';
      final t = ((r['total'] as num?) ?? 0).toDouble();
      if (ym.isNotEmpty) {
        map[ym] = t;
      }
    }

    final out = <_Row>[];
    double sum = 0;

    for (final ym in map.keys) {
      final total = map[ym] ?? 0.0;
      sum += total;
      final prevYm = _prevYearYm(ym); // 2025-11 -> 2024-11
      // لو الشهر السابق غير موجود في نتائج LIMIT، نجلبه باستعلام مفرد
      final prev = map.containsKey(prevYm)
          ? (map[prevYm] ?? 0.0)
          : await _fetchMonth(db, acc1400, prevYm);
      final yoy = _calcYoY(total, prev);
      out.add(_Row(ym: ym, total: total, yoy: yoy, prev: prev));
    }

    // رتب تصاعديًا للعرض
    out.sort((a, b) => a.ym.compareTo(b.ym));

    if (!mounted) return;
    setState(() {
      _rows = out;
      _sumPeriod = sum;
      _loading = false;
    });
  }

  // استعلام شهر مفرد عند الحاجة
  Future<double> _fetchMonth(dynamic db, int accId, String ym) async {
    if (ym.isEmpty) return 0.0;
    final r = await db.rawQuery('''
      SELECT IFNULL(SUM(l.debit),0) AS total
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? AND e.source = 'PURCHASE'
        AND substr(e.date,1,7) = ?
    ''', [accId, ym]);
    if (r.isEmpty) return 0.0;
    return ((r.first['total'] as num?) ?? 0).toDouble();
  }

  static String _prevYearYm(String ym) {
    // ym = 'YYYY-MM'
    if (ym.length != 7) return '';
    final y = int.tryParse(ym.substring(0, 4)) ?? 0;
    final m = ym.substring(5, 7);
    return '${y - 1}-$m';
  }

  static double _calcYoY(double cur, double prev) {
    if (prev == 0) return cur > 0 ? 100.0 : 0.0;
    return ((cur - prev) / prev) * 100.0;
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel = switch (_months) {
      6 => 'آخر 6 أشهر',
      24 => 'آخر 24 شهرًا',
      _ => 'آخر 12 شهرًا',
    };
    final desktop = Responsive.isDesktop(context);

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_rows.isEmpty) {
      content = const Center(child: Text('لا توجد مشتريات ضمن الفترة المحددة'));
    } else {
      content = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AdaptiveRow(
              children: [
                _kpi('الفترة', periodLabel),
                const SizedBox(width: 16),
                _kpi('إجمالي المشتريات', _nf.format(_sumPeriod)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == 0) return _headerRow();
                    final r = _rows[i - 1];
                    final yoyStr =
                        '${r.yoy >= 0 ? '▲' : '▼'} ${_nf.format(r.yoy.abs())}%';
                    final yoyColor =
                        r.yoy >= 0 ? AppColors.primary : Colors.red;
                    final prevLabel = r.prev == 0 ? '—' : _prevYearYm(r.ym);
                    return ListTile(
                      leading: Text(r.ym),
                      title: Text(_nf.format(r.total)),
                      subtitle: Text(
                        'مقارنة مع $prevLabel • السابق: ${_nf.format(r.prev)}',
                      ),
                      trailing: Text(
                        yoyStr,
                        style: TextStyle(
                          color: yoyColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('المشتريات حسب الشهر'),
        actions: [
          DropdownButton<int>(
            value: _months,
            underline: const SizedBox.shrink(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _months = v);
              _load();
            },
            items: const [
              DropdownMenuItem(value: 6, child: Text('6 أشهر')),
              DropdownMenuItem(value: 12, child: Text('12 شهرًا')),
              DropdownMenuItem(value: 24, child: Text('24 شهرًا')),
            ],
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      drawer: desktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/purchases/by-month'),
            ),
      body: AdaptiveRow(
        children: [
          if (desktop) const YallaSidebar(currentRoute: '/purchases/by-month'),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _kpi(String k, String v) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            Text(v, style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
      ),
    );
  }

  Widget _headerRow() {
    return const ListTile(
      leading: Text('الشهر', style: TextStyle(fontWeight: FontWeight.bold)),
      title: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle:
          Text('مقارنة سنوية', style: TextStyle(fontWeight: FontWeight.bold)),
      trailing: Text('التغير %', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class _Row {
  final String ym; // YYYY-MM
  final double total;
  final double yoy; // %
  final double prev;

  _Row({
    required this.ym,
    required this.total,
    required this.yoy,
    required this.prev,
  });
}
