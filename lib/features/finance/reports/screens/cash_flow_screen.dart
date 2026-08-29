// 📁 lib/features/finance/reports/screens/cash_flow_screen.dart
//
// CashFlowScreen — تقرير التدفق النقدي (GL v30 موحَّد الهوية)
// ---------------------------------------------------------------------
// • المصدر: gl_entries + gl_lines + accounts عبر DBService.
// • الحسابات: 1000 الصندوق، 1010 البنك. فلتر: الكل | صندوق | بنك.
// • فلاتر: تاريخ من/إلى + بحث نصّي في ref/note/source.
// • عرض: جدول دسكتوب + بطاقات موبايل. زر فتح القيد لكل صف.
// • مجاميع: Inflows=مدين، Outflows=دائن، Net، Running balance لكل صف.
// • تصدير CSV إلى مجلّد Downloads (مع fallback للمؤقت).
// • بدون أي بيانات وهمية. بدون تغيير في المعمارية.
//
// فهارس أداء موصى بها:
//   CREATE INDEX IF NOT EXISTS idx_gl_lines_account ON gl_lines(account_id);
//   CREATE INDEX IF NOT EXISTS idx_gl_entries_date  ON gl_entries(date);

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  DateTime? _from;
  DateTime? _to;
  String _query = '';
  String? _which; // null=All, '1000'=Cash, '1010'=Bank

  bool _loading = true;
  String? _error;

  int? _accCashId; // 1000
  int? _accBankId; // 1010

  List<_Row> _rows = [];
  double _sumIn = 0.0; // مدين (زيادة نقد/بنك)
  double _sumOut = 0.0; // دائن (نقص نقد/بنك)

  @override
  void initState() {
    super.initState();
    _boot();
  }

  // ───────── Boot: resolve account ids + first load ─────────
  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _accCashId = await DBService.getAccountIdByCode('1000');
      _accBankId = await DBService.getAccountIdByCode('1010');
      if (_accCashId == null && _accBankId == null) {
        throw StateError(
            'حسابات النقدية غير موجودة (1000/1010). نفّذ تهيئة الحسابات.');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // ───────── Load rows with filters ─────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
      _sumIn = 0.0;
      _sumOut = 0.0;
    });

    try {
      final db = await DBService.database;

      // Resolve account filter
      final ids = <int>[];
      if (_which == null || _which == '1000') {
        if (_accCashId != null) ids.add(_accCashId!);
      }
      if (_which == null || _which == '1010') {
        if (_accBankId != null) ids.add(_accBankId!);
      }
      if (ids.isEmpty) throw StateError('لا يوجد حساب نقدي ضمن الفلتر.');

      final placeholders = List.filled(ids.length, '?').join(',');
      final where = <String>['l.account_id IN ($placeholders)'];
      final args = <Object?>[...ids];

      if (_from != null) {
        where.add('e.date >= ?');
        args.add(
            DateTime(_from!.year, _from!.month, _from!.day).toIso8601String());
      }
      if (_to != null) {
        where.add('e.date <= ?');
        args.add(DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59)
            .toIso8601String());
      }
      if (_query.trim().isNotEmpty) {
        final s = '%${_query.trim()}%';
        where.add('(e.ref LIKE ? OR e.note LIKE ? OR e.source LIKE ?)');
        args.addAll([s, s, s]);
      }

      final sql = '''
        SELECT
          e.id                    AS entry_id,
          e.date                  AS date,
          IFNULL(e.ref,'')        AS ref,
          IFNULL(e.source,'')     AS source,
          IFNULL(e.source_id,'')  AS source_id,
          IFNULL(e.note,'')       AS note,
          l.account_id            AS account_id,
          CAST(l.debit  AS REAL)  AS debit,
          CAST(l.credit AS REAL)  AS credit
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        WHERE ${where.join(' AND ')}
        ORDER BY e.date ASC, e.id ASC, l.id ASC
      ''';

      final maps = await db.rawQuery(sql, args);

      double running = 0.0;
      double sIn = 0.0, sOut = 0.0;
      final out = <_Row>[];

      for (final m in maps) {
        final deb = _toD(m['debit']);
        final cre = _toD(m['credit']);

        sIn += deb; // مدين يزيد النقد
        sOut += cre; // دائن ينقص النقد
        running += (deb - cre);

        final aid = (m['account_id'] as num).toInt();
        final isCash = _accCashId != null && aid == _accCashId!;
        final isBank = _accBankId != null && aid == _accBankId!;

        out.add(_Row(
          entryId: (m['entry_id'] as num).toInt(),
          date: DateTime.tryParse((m['date'] ?? '').toString()) ??
              DateTime(1970, 1, 1),
          ref: (m['ref'] ?? '').toString(),
          note: (m['note'] ?? '').toString(),
          source: (m['source'] ?? '').toString(),
          sourceId: (m['source_id'] ?? '').toString(),
          debitIn: deb,
          creditOut: cre,
          running: double.parse(running.toStringAsFixed(2)),
          accountLabel:
              isCash ? 'الصندوق (1000)' : (isBank ? 'البنك (1010)' : 'نقدية'),
        ));
      }

      if (!mounted) return;
      setState(() {
        _rows = out;
        _sumIn = sIn;
        _sumOut = sOut;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ───────── Date pickers ─────────
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

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    const currentRoute = '/reports/cash-flow';
    final net = _sumIn - _sumOut;

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 6,
              offset: const Offset(0, 2)),
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
            'تقرير التدفق النقدي',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // اختيار الحساب — Account filter dropdown
          DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String?>(
                value: _which,
                iconEnabledColor: Colors.white,
                dropdownColor: Colors.white,
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('كل الحسابات (نقد + بنك)')),
                  DropdownMenuItem<String?>(
                      value: '1000', child: Text('الصندوق فقط (1000)')),
                  DropdownMenuItem<String?>(
                      value: '1010', child: Text('البنك فقط (1010)')),
                ],
                onChanged: (v) {
                  setState(() => _which = v);
                  _load();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          _chip(
              label: _from == null ? 'من' : _df.format(_from!),
              icon: Icons.date_range,
              onTap: _pickFrom),
          const SizedBox(width: 8),
          _chip(
              label: _to == null ? 'إلى' : _df.format(_to!),
              icon: Icons.event,
              onTap: _pickTo),
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
                hintText: 'بحث في المرجع/الوصف/المصدر…',
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );

    final totalsTop = Container(
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
          _stat('التدفقات الداخلة', _sumIn, Colors.green),
          _stat('التدفقات الخارجة', _sumOut, Colors.red),
          Chip(
            backgroundColor:
                (net >= 0 ? Colors.green : Colors.red).withOpacity(.08),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(net >= 0 ? 'صافي موجب: ' : 'صافي سالب: ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  _money.format(net.abs()),
                  style: TextStyle(
                      color: net >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _exportCsv(_rows),
            icon: const Icon(Icons.download_rounded),
            label: const Text('تصدير CSV'),
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
            : _rows.isEmpty
                ? const _EmptyState(
                    icon: Icons.ssid_chart,
                    title: 'لا توجد تدفقات نقدية ضمن الفلاتر الحالية',
                    subtitle: 'عدّل فترة التاريخ/الحساب أو أزل البحث.',
                  )
                : (isMobile ? _cards() : _table());

    final totalsBottom = Material(
      elevation: 2,
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.summarize),
            const SizedBox(width: 8),
            Text('داخل: ${_money.format(_sumIn)}',
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Text('خارج: ${_money.format(_sumOut)}',
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              'صافي: ${_money.format(net)}',
              style: TextStyle(
                  color: net >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: Row(
        children: [
          if (!isMobile) const YallaSidebar(currentRoute: currentRoute),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  header,
                  totalsTop,
                  Expanded(child: body),
                  if (!isMobile) totalsBottom,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────── Desktop table view ─────────
  Widget _table() {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('قيد')),
            DataColumn(label: Text('الحساب')),
            DataColumn(label: Text('داخل (مدين)')),
            DataColumn(label: Text('خارج (دائن)')),
            DataColumn(label: Text('الرصيد التراكمي')),
            DataColumn(label: Text('الوصف')),
            DataColumn(label: Text('فتح')),
          ],
          rows: _rows.map((r) {
            final tip = [
              if (r.ref.isNotEmpty) 'ref: ${r.ref}',
              if (r.source.isNotEmpty) 'source: ${r.source}',
              if (r.sourceId.isNotEmpty) 'source_id: ${r.sourceId}',
            ].join('  •  ');
            return DataRow(
              cells: [
                DataCell(Text(_df.format(r.date))),
                DataCell(Text('#${r.entryId}')),
                DataCell(Text(r.accountLabel, textAlign: TextAlign.right)),
                DataCell(Text(_money.format(r.debitIn),
                    style: const TextStyle(color: Colors.green))),
                DataCell(Text(_money.format(r.creditOut),
                    style: const TextStyle(color: Colors.red))),
                DataCell(Text(
                  _money.format(r.running),
                  style: TextStyle(
                      color: r.running >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold),
                )),
                DataCell(
                  Tooltip(
                    message: tip.isEmpty ? 'لا توجد بيانات مرجعية' : tip,
                    child: SizedBox(
                      width: 280,
                      child: Text(
                        r.note.isNotEmpty
                            ? r.note
                            : (r.ref.isNotEmpty ? r.ref : '-'),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  IconButton(
                    tooltip: 'فتح القيد',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => GLEntryScreen.open(context, r.entryId),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ───────── Mobile cards view ─────────
  Widget _cards() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final tip = [
          if (r.ref.isNotEmpty) 'ref: ${r.ref}',
          if (r.source.isNotEmpty) 'source: ${r.source}',
          if (r.sourceId.isNotEmpty) 'source_id: ${r.sourceId}',
        ].join('  •  ');
        return Card(
          child: ListTile(
            title: Text(
                '${_df.format(r.date)} • #${r.entryId} • ${r.accountLabel}',
                textAlign: TextAlign.right),
            subtitle: Text(
              r.note.isNotEmpty ? r.note : (r.ref.isNotEmpty ? r.ref : '-'),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            leading: Tooltip(
              message: tip.isEmpty ? 'لا توجد بيانات مرجعية' : tip,
              child: const Icon(Icons.info_outline),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money.format(r.running),
                  style: TextStyle(
                      color: r.running >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_money.format(r.debitIn),
                        style: const TextStyle(color: Colors.green)),
                    const SizedBox(width: 8),
                    Text(_money.format(r.creditOut),
                        style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ],
            ),
            onTap: () => GLEntryScreen.open(context, r.entryId),
          ),
        );
      },
    );
  }

  // ───────── Actions ─────────
  Future<void> _exportCsv(List<_Row> list) async {
    try {
      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد بيانات للتصدير')));
        return;
      }

      final sb = StringBuffer()
        ..writeln(
            'date,entry_id,account,inflow,outflow,running,ref,source,source_id,note');
      for (final r in list) {
        sb.writeln([
          _df.format(r.date),
          r.entryId,
          r.accountLabel.replaceAll(',', ' '),
          r.debitIn.toStringAsFixed(2),
          r.creditOut.toStringAsFixed(2),
          r.running.toStringAsFixed(2),
          r.ref.replaceAll(',', ' '),
          r.source.replaceAll(',', ' '),
          r.sourceId.replaceAll(',', ' '),
          r.note.replaceAll(',', ' '),
        ].join(','));
      }

      // Downloads directory → fallback to temp
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getTemporaryDirectory();

      final file = File('${dir.path}${Platform.pathSeparator}cash_flow.csv');
      await file.writeAsString(sb.toString());

      // Share dialog for convenience
      await Share.shareXFiles([XFile(file.path)], text: 'Cash Flow CSV');

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم حفظ CSV: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
    }
  }

  // ───────── Utils ─────────
  double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Widget _stat(String label, double value, Color color) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_money.format(value),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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

// ───────── Models ─────────
class _Row {
  final int entryId;
  final DateTime date;
  final String ref;
  final String note;
  final String source;
  final String sourceId;
  final double debitIn; // مدين
  final double creditOut; // دائن
  final double running;
  final String accountLabel;

  _Row({
    required this.entryId,
    required this.date,
    required this.ref,
    required this.note,
    required this.source,
    required this.sourceId,
    required this.debitIn,
    required this.creditOut,
    required this.running,
    required this.accountLabel,
  });
}

// ───────── Empty State ─────────
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
