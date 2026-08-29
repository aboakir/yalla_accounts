// 📁 lib/features/finance/reports/screens/suppliers_aging_screen.dart
//
// SuppliersAgingScreen — أعمار ذمم الموردين (GL v29/v30)
// -------------------------------------------------------------
// • المصدر: accounts + gl_entries + gl_lines (+ suppliers) عبر DBService فقط.
// • منطق AP (ذمم الموردين):
//     - فاتورة مشتريات/على الحساب → تُسجَّل "دائن" على حساب 2200.*  ⇒ liability ↑
//     - دفعة لمورّد → تُسجَّل "مدين" على 2200.*                     ⇒ liability ↓
// • نحسب الأعمار بطريقة FIFO: نستهلك المدفوعات (مدين) من أقدم الفواتير (دائن).
// • تجميع السلال: 0–30 | 31–60 | 61–90 | 91–120 | +120.
// • فلاتر: تاريخ مرجعي "حتى" + بحث باسم/رقم المورّد.
// • UI: جدول على الديسكتوب، بطاقات على الموبايل. هوية لونية موحّدة.
// • لا جداول وسيطة ولا بيانات وهمية.
//
// ملاحظات:
// - حسابات AP: code='2200' أو '2200.%'.
// - party_type للمورد: 'SUPPLIER' (غير حساس لحالة الأحرف).
// - suppliers.id يُفترض نصّي (supplier_pid). الربط على l.party_id = s.id كما هو.
// - نهاية اليوم: 23:59:59 لضمان شمول كامل اليوم المرجعي.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class SuppliersAgingScreen extends StatefulWidget {
  const SuppliersAgingScreen({super.key});

  @override
  State<SuppliersAgingScreen> createState() => _SuppliersAgingScreenState();
}

class _SuppliersAgingScreenState extends State<SuppliersAgingScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  DateTime _asOf = DateTime.now();
  String _query = '';

  bool _loading = true;
  String? _error;

  List<_SupplierBucket> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ========= Helpers =========
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
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
      setState(() => _asOf = d);
      _load();
    }
  }

  // ========= Load & Compute =========
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
    });

    try {
      final db = await DBService.database;

      // 1) احصل على كل حسابات AP (2200.* + الرئيسي إن وجد)
      final accRows = await db.rawQuery(
        "SELECT id FROM accounts WHERE code='2200' OR code LIKE '2200.%'",
      );
      if (accRows.isEmpty) {
        setState(() {
          _rows = [];
          _loading = false;
        });
        return;
      }

      final accIds = accRows
          .map((m) => m['id'])
          .where((v) => v != null)
          .map((v) => v is int ? v : int.tryParse(v.toString()) ?? -1)
          .where((v) => v > 0)
          .toList();
      if (accIds.isEmpty) {
        setState(() {
          _rows = [];
          _loading = false;
        });
        return;
      }

      final endIso = _endOfDay(_asOf).toIso8601String();
      final placeholders = List.filled(accIds.length, '?').join(',');
      final args = <Object?>[...accIds, endIso];

      // 2) اسحب كل الحركات حتى asOf، مربوطة باسم المورّد إن وُجد
      // AP منطق الإشارة: credit = فاتورة/التزام جديد، debit = دفعة/خفض الالتزام
      final rows = await db.rawQuery('''
        SELECT
          e.date                         AS date,
          l.debit                        AS debit,
          l.credit                       AS credit,
          UPPER(IFNULL(l.party_type,'')) AS party_type,
          l.party_id                     AS party_id,
          s.name                         AS supplier_name
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        LEFT JOIN suppliers s ON s.id = l.party_id        -- supplier_pid نصّي
        WHERE l.account_id IN ($placeholders)
          AND e.date <= ?
          AND l.party_id IS NOT NULL
          AND UPPER(IFNULL(l.party_type,'')) = 'SUPPLIER'
        ORDER BY e.date ASC, e.id ASC, l.id ASC
      ''', args);

      // 3) FIFO لكل مورّد: نعامل credit كـ "فاتورة مستحقة" ونستهلكها بـ debit "دفعات"
      final Map<String, _SupplierBucket> suppliers = {};
      final end = _endOfDay(_asOf);

      for (final m in rows) {
        final pid = (m['party_id'] ?? '').toString();
        if (pid.isEmpty) continue;

        final name = (m['supplier_name'] ?? 'مورد').toString();

        final rec =
            suppliers.putIfAbsent(pid, () => _SupplierBucket(pid, name));

        DateTime d;
        try {
          d = DateTime.parse((m['date'] ?? '').toString());
        } catch (_) {
          d = end;
        }

        final debit = _toD(m['debit']); // دفعة: تخفّض الالتزام
        final credit = _toD(m['credit']); // فاتورة: تزيد الالتزام

        if (credit > 0) rec.invoices.add(_Leg(date: d, amount: credit));
        if (debit > 0) rec.credits.add(_Leg(date: d, amount: debit));
      }

      for (final rec in suppliers.values) {
        rec.invoices.sort((a, b) => a.date.compareTo(b.date));
        rec.credits.sort((a, b) => a.date.compareTo(b.date));

        var pool = rec.credits.fold<double>(0, (s, x) => s + x.amount);

        // استهلاك الدفعات من أقدم الفواتير
        for (final inv in rec.invoices) {
          if (pool <= 0) break;
          final take = inv.remaining <= pool ? inv.remaining : pool;
          inv.remaining = _r(inv.remaining - take);
          pool = _r(pool - take);
        }

        // وزّع المتبقي من الفواتير ضمن سلال الأعمار
        for (final inv in rec.invoices) {
          final rem = inv.remaining;
          if (rem <= 0) continue;
          final days = end.difference(inv.date).inDays;
          if (days <= 30) {
            rec.current += rem;
          } else if (days <= 60) {
            rec.d30 += rem;
          } else if (days <= 90) {
            rec.d60 += rem;
          } else if (days <= 120) {
            rec.d90 += rem;
          } else {
            rec.over90 += rem;
          }
        }
      }

      // 4) فلترة/بحث وترتيب
      final q = _query.trim().toLowerCase();
      final list = suppliers.values.map((r) => r.toMap()).where((m) {
        if (q.isEmpty) return true;
        final pid = (m['supplier_pid'] ?? '').toString().toLowerCase();
        final name = (m['supplier_name'] ?? '').toString().toLowerCase();
        return pid.contains(q) || name.contains(q);
      }).toList()
        ..removeWhere((m) => _toD(m['total_due']).abs() <= 0.000001)
        ..sort((a, b) => _toD(b['total_due']).compareTo(_toD(a['total_due'])));

      setState(() {
        _rows = list.map(_SupplierBucket.fromMap).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double _r(double v) => double.parse(v.toStringAsFixed(2));

  // ========= Navigation =========
  void _openSupplierLedger(_SupplierBucket r) {
    // افتح متصفح GL مع تمرير party_type/party_id إن كان مدعومًا، وإلا افتح حساب 2200.S<pid> إن وُجد
    Navigator.of(context).pushNamed(
      AppRoutes
          .purchasesSupplierLedger, // إن لم يكن موجود، غيّره لـ AppRoutes.financeGL
      arguments: {
        'supplierPid': r.supplierPid,
        'to': _endOfDay(_asOf).toIso8601String(),
      },
    );
  }

  // ========= UI =========
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    final total = _rows.fold<double>(0, (s, r) => s + r.totalDue);
    final total0 = _rows.fold<double>(0, (s, r) => s + r.current);
    final total30 = _rows.fold<double>(0, (s, r) => s + r.d30);
    final total60 = _rows.fold<double>(0, (s, r) => s + r.d60);
    final total90 = _rows.fold<double>(0, (s, r) => s + r.d90);
    final total120 = _rows.fold<double>(0, (s, r) => s + r.over90);

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
            'أعمار ذمم الموردين',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _chip(
            label: _df.format(_asOf),
            icon: Icons.event,
            onTap: _pickAsOf,
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
                hintText: 'بحث باسم/رقم المورّد…',
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
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: 'مسح البحث',
            onPressed: () {
              setState(() => _query = '');
              _load();
            },
            icon: const Icon(Icons.clear_all, color: Colors.white),
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
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _stat('0–30', total0, Colors.blueGrey),
          _stat('31–60', total30, Colors.indigo),
          _stat('61–90', total60, Colors.deepPurple),
          _stat('91–120', total90, Colors.purple),
          _stat('+120', total120, Colors.red),
          _stat('الإجمالي', total, Colors.black87, bold: true),
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
            : (isMobile ? _cards() : _table());

    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: Row(
        children: [
          if (!isMobile)
            const YallaSidebar(currentRoute: '/reports/suppliers-aging'),
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

  // ===== Desktop table =====
  Widget _table() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('المورّد')),
                  DataColumn(label: Text('المعرف')),
                  DataColumn(label: Text('0–30')),
                  DataColumn(label: Text('31–60')),
                  DataColumn(label: Text('61–90')),
                  DataColumn(label: Text('91–120')),
                  DataColumn(label: Text('+120')),
                  DataColumn(label: Text('الإجمالي')),
                  DataColumn(label: Text('كشف/GL')),
                ],
                rows: _rows.map((r) {
                  return DataRow(
                    cells: [
                      DataCell(Text(r.supplierName)),
                      DataCell(Text(r.supplierPid)),
                      DataCell(Text(_money.format(r.current))),
                      DataCell(Text(_money.format(r.d30))),
                      DataCell(Text(_money.format(r.d60))),
                      DataCell(Text(_money.format(r.d90))),
                      DataCell(Text(_money.format(r.over90))),
                      DataCell(Text(
                        _money.format(r.totalDue),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      )),
                      DataCell(
                        IconButton(
                          tooltip: 'فتح كشف/GL',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _openSupplierLedger(r),
                        ),
                      ),
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

  // ===== Mobile cards =====
  Widget _cards() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        return Card(
          child: ListTile(
            title: Text(r.supplierName, textAlign: TextAlign.right),
            subtitle: Text('ID: ${r.supplierPid}', textAlign: TextAlign.right),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('الإجمالي: ${_money.format(r.totalDue)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('0–30: ${_money.format(r.current)}'),
                Text('31–60: ${_money.format(r.d30)}'),
                Text('61–90: ${_money.format(r.d60)}'),
                Text('91–120: ${_money.format(r.d90)}'),
                Text('+120: ${_money.format(r.over90)}'),
              ],
            ),
            onTap: () => _openSupplierLedger(r),
          ),
        );
      },
    );
  }

  // ===== UI bits =====
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

  Widget _stat(String label, double value, Color color, {bool bold = false}) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      side: BorderSide(color: color.withOpacity(.25)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            _money.format(value),
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Internal model/logic =====

class _Leg {
  final DateTime date;
  final double amount;
  double remaining;
  _Leg({required this.date, required this.amount}) : remaining = amount;
}

class _SupplierBucket {
  final String supplierPid; // suppliers.id (TEXT)
  final String supplierName;

  final List<_Leg> invoices = []; // credit
  final List<_Leg> credits = []; // debit (دفعات)

  double current = 0.0; // 0–30
  double d30 = 0.0; // 31–60
  double d60 = 0.0; // 61–90
  double d90 = 0.0; // 91–120
  double over90 = 0.0; // >120

  _SupplierBucket(this.supplierPid, this.supplierName);

  double get totalDue =>
      double.parse((current + d30 + d60 + d90 + over90).toStringAsFixed(2));

  Map<String, dynamic> toMap() => {
        'supplier_pid': supplierPid,
        'supplier_name': supplierName,
        'current': current,
        'd30': d30,
        'd60': d60,
        'd90': d90,
        'over90': over90,
        'total_due': totalDue,
      };

  static _SupplierBucket fromMap(Map<String, dynamic> m) {
    final b = _SupplierBucket(
      (m['supplier_pid'] ?? '').toString(),
      (m['supplier_name'] ?? 'مورد').toString(),
    );
    b.current = (m['current'] as num?)?.toDouble() ?? 0.0;
    b.d30 = (m['d30'] as num?)?.toDouble() ?? 0.0;
    b.d60 = (m['d60'] as num?)?.toDouble() ?? 0.0;
    b.d90 = (m['d90'] as num?)?.toDouble() ?? 0.0;
    b.over90 = (m['over90'] as num?)?.toDouble() ?? 0.0;
    return b;
  }
}
