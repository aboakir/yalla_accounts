// 📁 lib/features/finance/purchases/screens/supplier_ledger_screen.dart
//
// SupplierLedgerScreen — كشف حساب مورّد (GL)
// - يعتمد gl_entries + gl_lines حيث party_type='SUPPLIER' و party_id=supplierId.
// - الرصيد يُحسب كـ (credit - debit) لأن ذمم الموردين طبيعتها دائنة.
// - يوفّر: فترة تاريخية + بحث نصي اختياري في المرجع/المصدر.
// - Opening balance قبل تاريخ البداية + Running balance لكل سطر.
// - زر لفتح قيد GL.
//
// ملاحظة: يتوافق مع AppRoutes.purchasesSupplierLedger التي تمرر arguments:
// { 'supplierId': <String>, 'supplierName': <String> }

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SupplierLedgerScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;

  const SupplierLedgerScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen> {
  final _df = DateFormat('yyyy-MM-dd', 'ar');
  final _nf = NumberFormat('#,##0.00', 'ar');

  // فترة افتراضية: من أول السنة حتى اليوم
  late DateTime _from =
      DateTime(DateTime.now().year, 1, 1); // 1 يناير من السنة الحالية
  late DateTime _to = DateTime.now();

  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;

  double _opening = 0.0; // قبل from
  double _closing = 0.0; // opening + مجموع الفترة
  List<_LedgerRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      locale: const Locale('ar'),
      helpText: 'اختر تاريخ البداية',
    );
    if (d == null) return;
    setState(() => _from = DateTime(d.year, d.month, d.day));
    await _load();
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      locale: const Locale('ar'),
      helpText: 'اختر تاريخ النهاية',
    );
    if (d == null) return;
    setState(() => _to = DateTime(d.year, d.month, d.day));
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows = [];
      _opening = 0.0;
      _closing = 0.0;
    });

    final db = await DBService.database;
    final sid = widget.supplierId;

    final fromIso =
        DateTime(_from.year, _from.month, _from.day).toIso8601String();
    final toIso =
        DateTime(_to.year, _to.month, _to.day, 23, 59, 59).toIso8601String();
    final term = _searchCtrl.text.trim();

    // Opening balance قبل from: SUM(credit - debit)
    final opSql = '''
      SELECT IFNULL(SUM(l.credit - l.debit), 0) AS bal
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE l.party_type='SUPPLIER'
        AND CAST(l.party_id AS TEXT)=?
        AND date(e.date) < date(?)
    ''';
    final op = await db.rawQuery(opSql, [sid, fromIso]);
    final opening = ((op.first['bal'] as num?) ?? 0).toDouble();

    // حركات الفترة
    final whereSearch = term.isEmpty
        ? ''
        : ' AND (LOWER(IFNULL(e.ref,"")) LIKE LOWER(?) OR LOWER(e.source) LIKE LOWER(?)) ';

    final txSql = '''
      SELECT 
        e.id            AS entry_id,
        e.date          AS entry_date,
        e.ref           AS ref,
        e.source        AS source,
        a.code          AS acc_code,
        a.name          AS acc_name,
        l.debit         AS debit,
        l.credit        AS credit
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      JOIN accounts a   ON a.id = l.account_id
      WHERE l.party_type='SUPPLIER'
        AND CAST(l.party_id AS TEXT)=?
        AND date(e.date) BETWEEN date(?) AND date(?)
        $whereSearch
      ORDER BY e.date, e.id, l.id;
    ''';

    final args = term.isEmpty
        ? [sid, fromIso, toIso]
        : [sid, fromIso, toIso, '%$term%', '%$term%'];

    final q = await db.rawQuery(txSql, args);

    final rows = <_LedgerRow>[];
    double running = opening;

    for (final m in q) {
      final debit = ((m['debit'] as num?) ?? 0).toDouble();
      final credit = ((m['credit'] as num?) ?? 0).toDouble();
      final delta = credit - debit; // طبيعة دائنة لذمم الموردين
      running += delta;

      rows.add(_LedgerRow(
        entryId:
            (m['entry_id'] as int?) ?? int.tryParse('${m['entry_id']}') ?? 0,
        date: DateTime.tryParse('${m['entry_date']}') ?? DateTime.now(),
        ref: (m['ref'] ?? '') as String? ?? '',
        source: (m['source'] ?? '') as String? ?? '',
        accCode: (m['acc_code'] ?? '') as String? ?? '',
        accName: (m['acc_name'] ?? '') as String? ?? '',
        debit: debit,
        credit: credit,
        delta: delta,
        running: running,
      ));
    }

    setState(() {
      _opening = opening;
      _rows = rows;
      _closing = rows.isEmpty ? opening : rows.last.running;
      _loading = false;
    });
  }

  Future<void> _openGL(int id) async {
    await GLEntryScreen.open(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'كشف حساب مورّد — ${widget.supplierName} (${widget.supplierId})'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                AdaptiveRow(
                  children: [
                    // من
                    Expanded(
                      child: InkWell(
                        onTap: _pickFrom,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'من تاريخ',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(_df.format(_from)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // إلى
                    Expanded(
                      child: InkWell(
                        onTap: _pickTo,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'إلى تاريخ',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.calendar_month),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(_df.format(_to)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // بحث
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchCtrl,
                        onSubmitted: (_) => _load(),
                        decoration: InputDecoration(
                          labelText: 'بحث في المرجع/المصدر',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _load();
                                  },
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('تطبيق'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ملخص الأرصدة
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _chip('رصيد افتتاحي', _nf.format(_opening)),
                      _chip('رصيد ختامي', _nf.format(_closing)),
                    ],
                  ),
                ),
                // هيدر
                Container(
                  color: Colors.black.withOpacity(.04),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: AdaptiveRow(
                    children: [
                      _h('التاريخ', flex: 2),
                      _h('المرجع', flex: 2),
                      _h('المصدر'),
                      _h('الحساب', flex: 2),
                      _h('مدين', alignEnd: true),
                      _h('دائن', alignEnd: true),
                      _h('الأثر', alignEnd: true),
                      _h('الرصيد', alignEnd: true),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                // جدول
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('لا توجد حركات ضمن الفترة'))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: CircleAvatar(
                                radius: 16,
                                child: Text('${r.entryId}'),
                              ),
                              title: AdaptiveRow(
                                children: [
                                  Expanded(
                                      flex: 2, child: Text(_df.format(r.date))),
                                  Expanded(
                                      flex: 2,
                                      child: Text(r.ref.isEmpty ? '-' : r.ref)),
                                  Expanded(child: Text(r.source)),
                                  Expanded(
                                      flex: 2,
                                      child:
                                          Text('${r.accCode} • ${r.accName}')),
                                  Expanded(
                                    child: Text(_nf.format(r.debit),
                                        textAlign: TextAlign.end),
                                  ),
                                  Expanded(
                                    child: Text(_nf.format(r.credit),
                                        textAlign: TextAlign.end),
                                  ),
                                  Expanded(
                                    child: Text(_nf.format(r.delta),
                                        textAlign: TextAlign.end),
                                  ),
                                  Expanded(
                                    child: Text(_nf.format(r.running),
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                tooltip: 'فتح القيد',
                                onPressed: () => _openGL(r.entryId),
                                icon: const Icon(Icons.open_in_new),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _h(String s, {int flex = 1, bool alignEnd = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        s,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }
}

class _LedgerRow {
  final int entryId;
  final DateTime date;
  final String ref;
  final String source;
  final String accCode;
  final String accName;
  final double debit;
  final double credit;

  /// الأثر على رصيد المورّد = credit - debit
  final double delta;

  /// الرصيد الجاري بعد هذا السطر
  final double running;

  _LedgerRow({
    required this.entryId,
    required this.date,
    required this.ref,
    required this.source,
    required this.accCode,
    required this.accName,
    required this.debit,
    required this.credit,
    required this.delta,
    required this.running,
  });
}
