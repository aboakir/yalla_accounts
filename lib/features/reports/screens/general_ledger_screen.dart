// 📁 lib/features/reports/screens/general_ledger_screen.dart
//
// الأستاذ العام — General Ledger (GL v28)
// - جدول قابل للتمرير أفقي/عمودي (بدون قص).
// - حالة واضحة عندما لا توجد حسابات + زر تحديث.
// - اختيار حساب + فلاتر تاريخ + بحث نصّي (ref/note/source).
// - رصيد تراكمي + إجمالي مدين/دائن.
// - يعتمد على: accounts, gl_entries, gl_lines (عبر DBService).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class GeneralLedgerScreen extends StatefulWidget {
  const GeneralLedgerScreen({super.key});

  @override
  State<GeneralLedgerScreen> createState() => _GeneralLedgerScreenState();
}

class _GeneralLedgerScreenState extends State<GeneralLedgerScreen> {
  final ScrollController _verticalCtrl = ScrollController();
  final ScrollController _horizontalCtrl = ScrollController();
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  DateTime? _from;
  DateTime? _to;
  String _query = '';
  bool _loading = true;
  String? _error;

  List<_Account> _accounts = [];
  int? _selectedAccountId;

  List<_GLEntry> _rows = [];
  double _sumDebit = 0;
  double _sumCredit = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty || _selectedAccountId == null) return;

    final account = _accounts.firstWhere(
      (a) => a.id == _selectedAccountId,
      orElse: () => _accounts.first,
    );

    final rowsForPdf = _rows.map((e) {
      return {
        'date': DateFormat('yyyy-MM-dd').format(e.date),
        'description': e.description,
        'debit': e.debit.toStringAsFixed(2),
        'credit': e.credit.toStringAsFixed(2),
        'balance': e.runningBalance.toStringAsFixed(2),
      };
    }).toList();

    await YallaPdfService.exportGeneralLedgerPdf(
      accountName: '${account.code} — ${account.name}',
      from: _from ?? DateTime.now(),
      to: _to ?? DateTime.now(),
      rows: rowsForPdf,
    );
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await DBService.database;
      final accMaps = await db
          .rawQuery('SELECT id, code, name FROM accounts ORDER BY code ASC');

      _accounts = accMaps
          .map((m) => _Account(
                id: (m['id'] as num).toInt(),
                code: (m['code'] ?? '').toString(),
                name: (m['name'] ?? '').toString(),
              ))
          .toList();

      _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : null;
      await _load();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
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
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() => _to = d);
      _load();
    }
  }

  Future<void> _load() async {
    if (_selectedAccountId == null || _accounts.isEmpty) {
      setState(() {
        _rows = [];
        _sumDebit = 0;
        _sumCredit = 0;
        _loading = false;
      });
      return;
    }

    if (!_accounts.any((a) => a.id == _selectedAccountId)) {
      setState(() => _selectedAccountId =
          _accounts.isNotEmpty ? _accounts.first.id : null);
      if (_selectedAccountId == null) {
        setState(() {
          _rows = [];
          _sumDebit = 0;
          _sumCredit = 0;
          _loading = false;
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await DBService.database;

      final where = <String>['l.account_id = ?'];
      final args = <dynamic>[_selectedAccountId];

      if (_from != null) {
        where.add('e.date >= ?');
        args.add(_from!.toIso8601String());
      }
      if (_to != null) {
        final toInclusive =
            DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59);
        where.add('e.date <= ?');
        args.add(toInclusive.toIso8601String());
      }
      if (_query.trim().isNotEmpty) {
        final s = '%${_query.trim()}%';
        where.add('(e.ref LIKE ? OR e.note LIKE ? OR e.source LIKE ?)');
        args.addAll([s, s, s]);
      }

      final sql = '''
        SELECT 
          e.id        AS entry_id,
          e.date      AS date,
          e.ref       AS ref,
          e.source    AS source,
          e.source_id AS source_id,
          e.note      AS note,
          l.debit     AS debit,
          l.credit    AS credit
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        WHERE ${where.join(' AND ')}
        ORDER BY e.date ASC, e.id ASC
      ''';

      final maps = await db.rawQuery(sql, args);

      double running = 0, sD = 0, sC = 0;
      final rows = <_GLEntry>[];

      for (final m in maps) {
        final d = (m['debit'] is num) ? (m['debit'] as num).toDouble() : 0.0;
        final c = (m['credit'] is num) ? (m['credit'] as num).toDouble() : 0.0;

        running += d - c;
        sD += d;
        sC += c;

        final ref = (m['ref'] ?? '').toString();
        final note = (m['note'] ?? '').toString();
        final src = (m['source'] ?? '').toString();
        final srcId = (m['source_id'] ?? '').toString();

        rows.add(_GLEntry(
          id: (m['entry_id'] as num).toInt(),
          date: DateTime.tryParse((m['date'] ?? '').toString()) ??
              DateTime(1970, 1, 1),
          description: note.isNotEmpty ? note : (ref.isNotEmpty ? ref : '—'),
          debit: d,
          credit: c,
          runningBalance: running,
          tooltip: [
            if (ref.isNotEmpty) 'ref: $ref',
            if (src.isNotEmpty) 'source: $src',
            if (srcId.isNotEmpty) 'id: $srcId',
          ].join(' • '),
        ));
      }

      setState(() {
        _rows = rows;
        _sumDebit = sD;
        _sumCredit = sC;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: AdaptiveRow(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          const Text('الأستاذ العام',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: _selectedAccountId,
            dropdownColor: Colors.white,
            onChanged: _accounts.isEmpty
                ? null
                : (v) {
                    setState(() => _selectedAccountId = v);
                    _load();
                  },
            hint: const Text('لا يوجد حسابات', textAlign: TextAlign.right),
            items: _accounts
                .map((a) => DropdownMenuItem<int>(
                      value: a.id,
                      child: Text('${a.code} — ${a.name}',
                          textAlign: TextAlign.right),
                    ))
                .toList(),
          ),
          const Spacer(),
          _ChipButton(
              label: _from == null ? 'من' : _df.format(_from!),
              icon: Icons.date_range,
              onTap: _pickFrom),
          const SizedBox(width: 8),
          _ChipButton(
              label: _to == null ? 'إلى' : _df.format(_to!),
              icon: Icons.event,
              onTap: _pickTo),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              textAlign: TextAlign.right,
              onChanged: (v) {
                setState(() => _query = v);
                _load();
              },
              decoration: InputDecoration(
                hintText: 'بحث في المرجع/الوصف/المصدر...',
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
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'تصدير PDF',
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _exportPdf,
          ),
        ],
      ),
    );

    final totalsBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _Stat(
              label: 'إجمالي مدين',
              value: _money.format(_sumDebit),
              color: Colors.green),
          _Stat(
              label: 'إجمالي دائن',
              value: _money.format(_sumCredit),
              color: Colors.red),
          _Stat(
            label: 'الرصيد',
            value: _money.format(_sumDebit - _sumCredit),
            color: (_sumDebit - _sumCredit) >= 0 ? Colors.green : Colors.red,
            bold: true,
          ),
        ],
      ),
    );

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('تعذر تحميل البيانات:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red)),
                ),
              )
            : _accounts.isEmpty
                ? _NoAccountsState(onReload: _boot)
                : _rows.isEmpty
                    ? const _EmptyState(
                        icon: Icons.menu_book,
                        title: 'لا توجد حركات للحساب ضمن الفلاتر الحالية')
                    : PrimaryScrollController(
                        controller: _verticalCtrl,
                        child: _GLTable(
                          rows: _rows,
                          money: _money,
                          horizontalCtrl: _horizontalCtrl,
                        ),
                      );

    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: AdaptiveRow(
        children: [
          if (!isMobile)
            const YallaSidebar(currentRoute: '/reports/general-ledger'),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  header,
                  totalsBar,
                  Expanded(child: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ========== Models / Widgets ==========

class _Account {
  final int id;
  final String code;
  final String name;
  _Account({required this.id, required this.code, required this.name});
}

class _GLEntry {
  final int id;
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final double runningBalance;
  final String tooltip;

  _GLEntry({
    required this.id,
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    required this.tooltip,
  });
}

class _GLTable extends StatelessWidget {
  final List<_GLEntry> rows;
  final NumberFormat money;
  final ScrollController horizontalCtrl;

  const _GLTable({
    required this.rows,
    required this.money,
    required this.horizontalCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: horizontalCtrl,
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 860),
          child: AdaptiveDataTable(
            columns: const [
              DataColumn(label: Text('التاريخ')),
              DataColumn(label: Text('الوصف')),
              DataColumn(label: Text('مدين')),
              DataColumn(label: Text('دائن')),
              DataColumn(label: Text('الرصيد')),
            ],
            rows: rows.map((e) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(DateFormat('yyyy-MM-dd').format(e.date)),
                  ),
                  DataCell(
                    Tooltip(
                      message: e.tooltip.isEmpty
                          ? 'لا توجد بيانات مرجعية'
                          : e.tooltip,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          e.description,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      money.format(e.debit),
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                  DataCell(
                    Text(
                      money.format(e.credit),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  DataCell(
                    Text(
                      money.format(e.runningBalance),
                      style: TextStyle(
                        color:
                            e.runningBalance >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;
  const _Stat(
      {required this.label,
      required this.value,
      required this.color,
      this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 2),
          Text('$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ChipButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoAccountsState extends StatelessWidget {
  final VoidCallback onReload;
  const _NoAccountsState({required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(
          child: _EmptyState(
            icon: Icons.account_tree_outlined,
            title: 'لا يوجد حسابات بعد',
            subtitle:
                'شغّل DBService.ensureDefaultAccountsExist() ثم حدّث الصفحة.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: ElevatedButton.icon(
            onPressed: onReload,
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث'),
          ),
        ),
      ],
    );
  }
}
