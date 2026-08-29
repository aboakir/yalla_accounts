// 📁 lib/features/finance/reports/screens/balance_sheet_screen.dart
//
// الميزانية العمومية — Balance Sheet (GL v29)
// -------------------------------------------------------------
// - المصدر: accounts + gl_entries + gl_lines عبر DBService فقط.
// - نمطان للحساب:
//     • "رصيد حتى تاريخ" (As-Of) = جميع الحركات حتى نهاية يوم "إلى" (افتراضي).
//     • "حركة فترة" = الحركات بين "من" و "إلى" (شبيهة بفترة تقريرية).
// - أرباح الفترة: تُحتسب من REVENUE/EXPENSE وتُعرض ضمن حقوق الملكية.
// - فلاتر: تاريخ من/إلى + وضع الحساب (As-Of / فترة) + بحث باسم/كود الحساب +
//          خيار إخفاء الأرصدة الصفرية.
// - تجميع حسب نوع الحساب: ASSET / LIABILITY / EQUITY.
// - طريقة الاحتساب المحاسبي:
//     • الأصول  = SUM(debit - credit)
//     • الخصوم  = SUM(credit - debit)
//     • الملكية = SUM(credit - debit) + أرباح الفترة
// - Drill-through: الضغط على أي حساب يفتح GLBrowser مع تمرير الفلاتر.
// - عرض جدولي على الديسكتوب وبطاقات على الموبايل.
// - بدون إنشاء جداول وبدون أي بيانات وهمية.
// - محسّن أداءً: LEFT JOIN مع شروط التاريخ داخل JOIN فقط.
//
// ملاحظات:
// - في وضع "As-Of" يُهمل "من" ويُستخدم فقط "إلى" لحساب الرصيد التراكمي.
// - الحسابات بلا حركة تبقى ظاهرة بقيم صفرية ما لم تختر إخفاءها.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  // فلاتر
  DateTime? _from; // يُستخدم فقط في وضع الفترة
  DateTime? _to = DateTime.now();
  bool _periodMode = false; // false = As-Of، true = حركة فترة
  bool _hideZero = false;
  String _query = '';

  bool _loading = true;
  String? _error;

  // نتائج
  List<_Row> _assets = [];
  List<_Row> _liabilities = [];
  List<_Row> _equity = [];
  double _sumAssets = 0.0;
  double _sumLiab = 0.0;
  double _sumEquity = 0.0;

  // أرباح الفترة المضافة إلى حقوق الملكية

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ─────────────── Helpers ───────────────
  double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() => _from = d);
      _load();
    }
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() => _to = d);
      _load();
    }
  }

  void _toggleMode(bool v) {
    setState(() => _periodMode = v);
    _load();
  }

  void _toggleHideZero(bool v) {
    setState(() => _hideZero = v);
    _load();
  }

  void _clearFilters() {
    setState(() {
      _from = null;
      _to = DateTime.now();
      _query = '';
      _periodMode = false;
      _hideZero = false;
    });
    _load();
  }

  // ─────────────── Load ───────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _assets = [];
      _liabilities = [];
      _equity = [];
      _sumAssets = 0;
      _sumLiab = 0;
      _sumEquity = 0;
    });

    try {
      final db = await DBService.database;

      // نحسب حدود التاريخ وفق الوضع المختار
      DateTime? fromIso;
      DateTime? toIso;

      if (_periodMode) {
        // حركة فترة: يلزم "إلى". "من" اختياري. إن لم يوجد "من" نأخذ أول يوم من السنة.
        final toRef = _to ?? DateTime.now();
        toIso = _dayEnd(toRef);
        if (_from != null) {
          fromIso = _dayStart(_from!);
        } else {
          fromIso = DateTime(toRef.year, 1, 1);
        }
      } else {
        // As-Of: نستخدم فقط "إلى". إن لم توجد نضع اليوم.
        final toRef = _to ?? DateTime.now();
        fromIso = null;
        toIso = _dayEnd(toRef);
      }

      // شروط التاريخ داخل JOIN للحفاظ على LEFT JOIN
      final joinConds = <String>[];
      final args = <Object?>[];

      if (_periodMode) {
        joinConds.add('e.date >= ?');
        joinConds.add('e.date <= ?');
        args.add(fromIso!.toIso8601String());
        args.add(toIso.toIso8601String());
      } else {
        joinConds.add('e.date <= ?');
        args.add(toIso.toIso8601String());
      }
      final joinDateSql =
          joinConds.isEmpty ? '' : ' AND ${joinConds.join(' AND ')}';

      final q = _query.trim().toLowerCase();

      // === 1) تجميع الحسابات حسب النوع (ASSET/LIABILITY/EQUITY) ===
      final sqlMain = '''
        SELECT
          a.id                    AS account_id,
          IFNULL(a.code,'')       AS code,
          a.name                  AS name,
          a.type                  AS type,   -- ASSET / LIABILITY / EQUITY / REVENUE / EXPENSE
          IFNULL(SUM(l.debit),0)  AS sdebit,
          IFNULL(SUM(l.credit),0) AS scredit
        FROM accounts a
        LEFT JOIN gl_lines   l ON l.account_id = a.id
        LEFT JOIN gl_entries e ON e.id = l.entry_id $joinDateSql
        WHERE a.type IN ('ASSET','LIABILITY','EQUITY')
        GROUP BY a.id, a.code, a.name, a.type
        ORDER BY 
          CASE a.type 
            WHEN 'ASSET' THEN 1 
            WHEN 'LIABILITY' THEN 2 
            WHEN 'EQUITY' THEN 3 
            ELSE 4 
          END,
          a.code ASC, a.name ASC
      ''';

      final rowsMain = await db.rawQuery(sqlMain, args);

      final assets = <_Row>[];
      final liab = <_Row>[];
      final eq = <_Row>[];

      for (final m in rowsMain) {
        final type = (m['type'] ?? '').toString();
        final code = (m['code'] ?? '').toString();
        final name = (m['name'] ?? '').toString();
        final d = _toD(m['sdebit']);
        final c = _toD(m['scredit']);

        // فلتر البحث
        if (q.isNotEmpty &&
            !code.toLowerCase().contains(q) &&
            !name.toLowerCase().contains(q)) {
          continue;
        }

        double amount;
        if (type == 'ASSET') {
          amount = d - c; // طبيعة مدين
          if (_hideZero && amount.abs() < 1e-9) continue;
          assets.add(_Row(
              accountId: (m['account_id'] as num).toInt(),
              code: code,
              name: name,
              amount: amount));
        } else if (type == 'LIABILITY') {
          amount = c - d; // طبيعة دائن
          if (_hideZero && amount.abs() < 1e-9) continue;
          liab.add(_Row(
              accountId: (m['account_id'] as num).toInt(),
              code: code,
              name: name,
              amount: amount));
        } else if (type == 'EQUITY') {
          amount = c - d; // طبيعة دائن
          if (_hideZero && amount.abs() < 1e-9) continue;
          eq.add(_Row(
              accountId: (m['account_id'] as num).toInt(),
              code: code,
              name: name,
              amount: amount));
        }
      }

      // === 2) أرباح الفترة (REVENUE/EXPENSE) ===
      final sqlProfit = '''
        SELECT
          SUM(CASE WHEN a.type='REVENUE' THEN (IFNULL(l.credit,0) - IFNULL(l.debit,0)) ELSE 0 END) AS rev_net,
          SUM(CASE WHEN a.type='EXPENSE' THEN (IFNULL(l.debit,0) - IFNULL(l.credit,0)) ELSE 0 END) AS exp_net
        FROM accounts a
        LEFT JOIN gl_lines   l ON l.account_id = a.id
        LEFT JOIN gl_entries e ON e.id = l.entry_id $joinDateSql
        WHERE a.type IN ('REVENUE','EXPENSE')
      ''';
      final rowsProfit = await db.rawQuery(sqlProfit, args);
      final revNet = _toD(rowsProfit.first['rev_net']);
      final expNet = _toD(rowsProfit.first['exp_net']);
      final profit = revNet - expNet; // موجب يزيد الملكية

      // إدراج “أرباح متراكمة للفترة” كبند مستقل تحت حقوق الملكية
      if (!_hideZero || profit.abs() >= 1e-9) {
        eq.add(_Row(
          accountId: null,
          code: '',
          name: 'أرباح متراكمة للفترة',
          amount: profit,
          isDerived: true,
        ));
      }

      // مجاميع الأقسام
      final sumA = assets.fold<double>(0, (s, r) => s + r.amount);
      final sumL = liab.fold<double>(0, (s, r) => s + r.amount);
      final sumE = eq.fold<double>(0, (s, r) => s + r.amount);

      setState(() {
        _assets = assets;
        _liabilities = liab;
        _equity = eq;
        _sumAssets = sumA;
        _sumLiab = sumL;
        _sumEquity = sumE;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ─────────────── Drill-through ───────────────
  void _openGLForAccount(_Row r) {
    Navigator.of(context).pushNamed(
      AppRoutes.financeGL,
      arguments: {
        if (_periodMode) 'from': _from?.toIso8601String(),
        'to': _to?.toIso8601String(),
        if (r.accountId != null) 'accountId': r.accountId,
        'query': _query,
      },
    );
  }

  // ─────────────── UI ───────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final diff = (_sumAssets - (_sumLiab + _sumEquity)).abs();
    final balanced = diff < 0.005;

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
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          const Text(
            'الميزانية العمومية',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Row(
            children: [
              const Text('As-Of', style: TextStyle(color: Colors.white)),
              Switch(
                value: _periodMode,
                activeColor: Colors.white,
                onChanged: _toggleMode,
              ),
              const Text('فترة', style: TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(width: 8),
          if (_periodMode) ...[
            _chip(
              label: _from == null ? 'من' : _df.format(_from!),
              icon: Icons.date_range,
              onTap: _pickFrom,
            ),
            const SizedBox(width: 8),
          ],
          _chip(
            label: _to == null ? 'إلى' : _df.format(_to!),
            icon: Icons.event,
            onTap: _pickTo,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: TextField(
              textAlign: TextAlign.right,
              onChanged: (v) {
                setState(() => _query = v);
                _load();
              },
              decoration: InputDecoration(
                hintText: 'بحث باسم/كود الحساب…',
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
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            selected: _hideZero,
            onSelected: _toggleHideZero,
            label: const Text('إخفاء الأرصدة الصفرية'),
            selectedColor: Colors.white.withOpacity(.15),
            labelStyle: const TextStyle(color: Colors.white),
            backgroundColor: Colors.white.withOpacity(.10),
            side: const BorderSide(color: Colors.white),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: 'مسح الفلاتر',
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off, color: Colors.white),
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
          _stat('الأصول (A)', _sumAssets, Colors.blueGrey),
          _stat('الخصوم (L)', _sumLiab, Colors.deepPurple),
          _stat('حقوق الملكية (E)', _sumEquity, Colors.teal),
          Chip(
            backgroundColor:
                (balanced ? Colors.green : Colors.orange).withOpacity(.08),
            label: Text(
              balanced ? '✅ A = L + E' : '⚠️ فرق: ${_money.format(diff)}',
              style: TextStyle(
                color: balanced ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
            : (isMobile ? _cards() : _tables());

    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: Row(
        children: [
          if (!isMobile)
            const YallaSidebar(currentRoute: '/reports/balance-sheet'),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  header,
                  totals,
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Desktop =====
  Widget _tables() {
    return LayoutBuilder(
      builder: (context, constraints) {
        double maxW = constraints.maxWidth;

        // عدد الأعمدة حسب حجم الشاشة
        int columns;
        if (maxW >= 1600) {
          columns = 3;
        } else if (maxW >= 1100) {
          columns = 2;
        } else {
          columns = 1;
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.80, // يتحكم بارتفاع البطاقة
            ),
            children: [
              _sectionTable('الأصول', Colors.blueGrey, _assets),
              _sectionTable('الخصوم', Colors.deepPurple, _liabilities),
              _sectionTable('حقوق الملكية', Colors.teal, _equity),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTable(String title, Color color, List<_Row> rows) {
    final sum = rows.fold<double>(0, (s, r) => s + r.amount);

    return Card(
      elevation: 2,
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 16)),
                const Spacer(),
                Text(
                  _money.format(sum),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListTile(
                      dense: true,
                      onTap: r.accountId == null
                          ? null
                          : () => _openGLForAccount(r),
                      title: Text(
                        '${r.code.isEmpty ? '—' : r.code} — ${r.name}',
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _money.format(r.amount),
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Mobile =====
  Widget _cards() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _cardSection('الأصول', Colors.blueGrey, _assets),
        const SizedBox(height: 12),
        _cardSection('الخصوم', Colors.deepPurple, _liabilities),
        const SizedBox(height: 12),
        _cardSection('حقوق الملكية', Colors.teal, _equity),
      ],
    );
  }

  Widget _cardSection(String title, Color color, List<_Row> rows) {
    final sum = rows.fold<double>(0, (s, r) => s + r.amount);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: color)),
                const Spacer(),
                Text(_money.format(sum),
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const Divider(),
            ...rows.map((r) {
              return ListTile(
                dense: true,
                onTap: r.accountId == null ? null : () => _openGLForAccount(r),
                title: Text(
                  '${r.code.isEmpty ? '—' : r.code} — ${r.name}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
                trailing: Text(
                  _money.format(r.amount),
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              );
            }),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا توجد أرصدة ضمن الفلاتر الحالية'),
              ),
          ],
        ),
      ),
    );
  }

  // ===== UI bits =====
  Widget _stat(String label, double value, Color color) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            _money.format(value),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Chip(
        backgroundColor: AppColors.primary,
        labelPadding: const EdgeInsetsDirectional.only(start: 8, end: 10),
        label: Row(
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

// ===== Model =====
class _Row {
  final int? accountId; // null للبنود المشتقة مثل أرباح الفترة
  final String code;
  final String name;
  final double amount;
  final bool isDerived;
  _Row({
    required this.accountId,
    required this.code,
    required this.name,
    required this.amount,
    this.isDerived = false,
  });
}
