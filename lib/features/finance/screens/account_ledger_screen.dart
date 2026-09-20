import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';
// 📁 lib/features/finance/screens/account_ledger_screen.dart
//
// الأستاذ العام لحساب واحد — Account Ledger (GL v29)

import 'dart:io';
import '../../reports/screens/gl_entry_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/pdf/account_ledger_pdf.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/platform/yalla_path_provider.dart';
import 'package:share_plus/share_plus.dart';

// PDF/Printing
import 'package:printing/printing.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class AccountLedgerScreen extends StatefulWidget {
  const AccountLedgerScreen({super.key});

  @override
  State<AccountLedgerScreen> createState() => _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends State<AccountLedgerScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  int? _accountId;
  String _accountCode = '';
  String _accountName = '';

  DateTime? _from;
  DateTime? _to;
  String _query = '';
  int _searchReset = 0;
  String? _pendingSearch;
  bool _loading = true;
  String? _error;

  // بيانات الجدول
  double _opening = 0.0;
  double _sumDebit = 0.0;
  double _sumCredit = 0.0;
  List<_Row> _rows = [];

  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;

    _readRouteArgs();
    // شغّل التحميل بعد بناء أول إطار لتجنّب استخدام context مبكراً
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _readRouteArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final aid = args['accountId'];
      if (aid is int) _accountId = aid;
      final fromIso = args['from']?.toString();
      final toIso = args['to']?.toString();
      final q = args['query']?.toString();
      if (fromIso != null && fromIso.isNotEmpty) {
        _from = DateTime.tryParse(fromIso);
      }
      if (toIso != null && toIso.isNotEmpty) {
        _to = DateTime.tryParse(toIso);
      }
      if (q != null) _query = q;
    }
  }

  // ───────────── Helpers ─────────────
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
    if (!mounted) return;
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
    if (!mounted) return;
    if (d != null) {
      setState(() => _to = d);
      _load();
    }
  }

  void _runSearch() {
    _query = _pendingSearch ?? _query;
    _load();
  }

  void _resetFilters() {
    setState(() {
      _from = null;
      _to = null;
      _query = '';
      _searchReset++;
      _pendingSearch = null;
    });
    _load();
  }

  // ───────────── Load ─────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _opening = 0;
      _sumDebit = 0;
      _sumCredit = 0;
      _rows = [];
    });

    try {
      if (_from != null && _to != null && _from!.isAfter(_to!)) {
        throw ArgumentError('بداية الفترة بعد نهايتها');
      }
      final db = await DBService.database;

      _accountId ??= await DBService.getAccountIdByCode('1000');
      if (_accountId == null) {
        throw StateError('لم يتم تحديد حساب. مرّر accountId عبر Route args.');
      }

      // معلومات الحساب
      final acc = await db.query('accounts',
          columns: ['code', 'name'],
          where: 'id=?',
          whereArgs: [_accountId],
          limit: 1);
      if (acc.isEmpty) throw StateError('الحساب غير موجود: id=$_accountId');

      _accountCode = (acc.first['code'] ?? '').toString();
      _accountName = (acc.first['name'] ?? '').toString();

      // رصيد افتتاحي قبل "من"
      if (_from != null) {
        final openQ = await db.rawQuery('''
          SELECT IFNULL(SUM(l.debit),0) AS d, IFNULL(SUM(l.credit),0) AS c
          FROM gl_lines l
          JOIN gl_entries e ON e.id = l.entry_id
          WHERE l.account_id = ?
            AND substr(e.date,1,10) < substr(?,1,10)
        ''', [_accountId, _dayStart(_from!).toIso8601String()]);
        final d = _toD(openQ.first['d']);
        final c = _toD(openQ.first['c']);
        _opening = double.parse((d - c).toStringAsFixed(2));
      } else {
        _opening = 0.0;
      }

      // شروط WHERE
      final where = <String>['l.account_id = ?'];
      final args = <Object?>[_accountId];

      if (_from != null) {
        where.add('substr(e.date,1,10) >= substr(?,1,10)');
        args.add(_dayStart(_from!).toIso8601String());
      }
      if (_to != null) {
        where.add('substr(e.date,1,10) <= substr(?,1,10)');
        args.add(_dayEnd(_to!).toIso8601String());
      }

      final sql = '''
        SELECT 
          e.id        AS entry_id,
          e.date      AS date,
          e.ref       AS ref,
          e.source    AS source,
          e.source_id AS source_id,
          e.note      AS note,
          a.code      AS account_code,
          a.name      AS account_name,
          l.debit     AS debit,
          l.credit    AS credit,
          l.party_type AS party_type,
          l.party_id   AS party_id,
          l.invoice_id AS invoice_id,
          l.repair_id  AS repair_id
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        JOIN accounts  a ON a.id = l.account_id
        WHERE ${where.join(' AND ')}
        ORDER BY e.date ASC, e.id ASC, l.id ASC
      ''';

      final maps = await db.rawQuery(sql, args);

      // تحويل + رصيد تراكمي
      final rows = <_Row>[];
      double running = _opening;
      double sumD = 0, sumC = 0;

      // سطر افتتاحي افتراضي لو يوجد تاريخ "من"
      if (_from != null && (_opening).abs() > 0.000001) {
        rows.add(_Row.opening(
          date: _dayStart(_from!),
          amount: _opening,
        ));
      }

      for (final m in maps) {
        final d = _toD(m['debit']);
        final c = _toD(m['credit']);
        running += d - c;
        sumD += d;
        sumC += c;
        if (_query.trim().isNotEmpty &&
            !m.values
                .join(' ')
                .toLowerCase()
                .contains(_query.trim().toLowerCase())) {
          continue;
        }

        rows.add(
          _Row(
            isOpening: false,
            entryId: (m['entry_id'] as num).toInt(),
            date: DateTime.tryParse((m['date'] ?? '').toString()) ??
                DateTime(1970, 1, 1),
            description: ((m['note'] ?? '').toString().trim().isNotEmpty)
                ? (m['note'] ?? '').toString()
                : (m['ref'] ?? '').toString(),
            debit: d,
            credit: c,
            accountCode: (m['account_code'] ?? '').toString(),
            accountName: (m['account_name'] ?? '').toString(),
            partyType: (m['party_type'] ?? '').toString(),
            partyId: (m['party_id'] ?? '').toString(),
            invoiceId: (m['invoice_id'] ?? '').toString(),
            repairId: (m['repair_id'] ?? '').toString(),
            ref: (m['ref'] ?? '').toString(),
            source: (m['source'] ?? '').toString(),
            sourceId: (m['source_id'] ?? '').toString(),
            runningBalance: running,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _sumDebit = double.parse(sumD.toStringAsFixed(2));
        _sumCredit = double.parse(sumC.toStringAsFixed(2));
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

  // ───────────── Export CSV ─────────────
  Future<void> _exportCsv() async {
    try {
      if (_rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير')),
        );
        return;
      }

      final sb = StringBuffer()
        ..writeln(
            'date,entry_id,ref,source,source_id,party,invoice_id,repair_id,debit,credit,running');

      for (final r in _rows) {
        if (r.isOpening) {
          sb.writeln([
            _df.format(r.date),
            'OPENING',
            '',
            '',
            '',
            '',
            '',
            '',
            '0.00',
            '0.00',
            r.runningBalance.toStringAsFixed(2),
          ].join(','));
          continue;
        }
        final party = [
          if ((r.partyType).isNotEmpty) r.partyType,
          if ((r.partyId).isNotEmpty) r.partyId,
        ].join(':');
        sb.writeln([
          _df.format(r.date),
          r.entryId,
          r.ref.replaceAll(',', ' '),
          r.source,
          r.sourceId,
          party,
          r.invoiceId,
          r.repairId,
          r.debit.toStringAsFixed(2),
          r.credit.toStringAsFixed(2),
          r.runningBalance.toStringAsFixed(2),
        ].map((s) => s.toString()).join(','));
      }

      final dir =
          await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/account_ledger_$_accountCode.csv');
      await file.writeAsString(sb.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'Account Ledger CSV');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير CSV: ${UserFacingError.message(e)}')),
      );
    }
  }

  Future<void> _exportPdf() async {
    if (_accountId == null || _loading) return;
    try {
      final bytes = await AccountLedgerPdf.generateForAccount(_accountId!,
          from: _from, to: _to);
      await Printing.sharePdf(
          bytes: bytes,
          filename:
              'ledger_${_accountCode.isEmpty ? 'account' : _accountCode}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('تعذر إنشاء كشف PDF صالح: ${UserFacingError.message(e)}')));
    }
  }

  // ───────────── UI ─────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = !Responsive.isDesktop(context);
    final ending = _opening + (_sumDebit - _sumCredit);

    final header = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_accountName.isEmpty ? 'جاري تحميل الحساب…' : _accountName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        if (_accountCode.isNotEmpty) Text('رقم الحساب: $_accountCode'),
        FinancialPeriodFilter(
            from: _from,
            to: _to,
            onChanged: (range) {
              setState(() {
                _from = range.start;
                _to = range.end;
              });
              _load();
            }),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(_searchReset),
          initialValue: _query,
          inputFormatters: const [YallaDigitNormalizer()],
          textInputAction: TextInputAction.search,
          onChanged: (value) => _pendingSearch = value,
          onFieldSubmitted: (_) => _runSearch(),
          decoration: InputDecoration(
            labelText: 'بحث في الوصف أو رقم المستند',
            suffixIcon: IconButton(
                tooltip: 'بحث',
                onPressed: _runSearch,
                icon: const Icon(Icons.search)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('الفترة وخيارات العرض'),
          subtitle: Text(
              '${_from == null ? 'من البداية' : _df.format(_from!)} — ${_to == null ? 'كل التواريخ' : _df.format(_to!)}'),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: _pickFrom,
                  icon: const Icon(Icons.date_range),
                  label: Text(_from == null ? 'من تاريخ' : _df.format(_from!))),
              OutlinedButton.icon(
                  onPressed: _pickTo,
                  icon: const Icon(Icons.event),
                  label: Text(_to == null ? 'إلى تاريخ' : _df.format(_to!))),
              TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('مسح الفلاتر')),
            ])
          ],
        ),
      ]),
    );
    final totals = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth < 600
              ? (constraints.maxWidth - 8) / 2
              : (constraints.maxWidth - 24) / 4;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
                width: width,
                child: _stat('رصيد بداية الفترة', _opening, Colors.blueGrey)),
            SizedBox(
                width: width,
                child: _stat(_debitLabel, _sumDebit, Colors.teal)),
            SizedBox(
                width: width,
                child: _stat(_creditLabel, _sumCredit, Colors.deepOrange)),
            SizedBox(
                width: width,
                child: _stat(
                    _query.trim().isEmpty
                        ? 'الرصيد بعد الحركات'
                        : 'الرصيد بعد الحركات',
                    ending,
                    AppColors.primary,
                    bold: true)),
          ]);
        }),
        const SizedBox(height: 8),
        Text(
            _isCashAccount
                ? 'الوارد يزيد رصيد هذا الحساب، والمنصرف يخفضه.'
                : 'مدين ودائن هما جانبا القيد، ولا يعنيان قبضًا أو صرفًا بالضرورة. الرصيد = بداية الفترة + المدين − الدائن.',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        if (_query.trim().isNotEmpty)
          const Text(
              'البحث يرشّح الحركات المعروضة فقط؛ الأرصدة والإجماليات تخص كامل الفترة.',
              style: TextStyle(fontSize: 12)),
      ]),
    );

    final content = _loading
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
                    icon: Icons.menu_book_outlined,
                    title: 'لا توجد حركات ضمن الفلاتر الحالية',
                    subtitle: 'جرّب تغيير الفترة أو مسح البحث.',
                  )
                : (!Responsive.isDesktop(context)
                    ? _mobileList()
                    : _desktopTable());

    return Scaffold(
      appBar: AppBar(
          title: const Text('حركة الحساب', overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                tooltip: 'تحديث',
                onPressed: _load,
                icon: const Icon(Icons.refresh)),
            PopupMenuButton<String>(
              tooltip: 'تصدير الكشف',
              icon: const Icon(Icons.ios_share),
              onSelected: (value) {
                if (value == 'pdf') {
                  _exportPdf();
                } else {
                  _exportCsv();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: Text('تصدير PDF')),
                PopupMenuItem(value: 'csv', child: Text('تصدير CSV (Excel)')),
              ],
            ),
          ]),
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: Row(children: [
        if (!isMobile) const YallaSidebar(currentRoute: '/finance/gl'),
        Expanded(
            child: SafeArea(
                top: false,
                child: isMobile
                    ? CustomScrollView(slivers: [
                        SliverToBoxAdapter(child: header),
                        SliverToBoxAdapter(child: totals),
                        if (!_loading && _error == null && _rows.isNotEmpty)
                          SliverPadding(
                              padding: const EdgeInsets.all(12),
                              sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                      (_, index) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: _movementCard(_rows[index])),
                                      childCount: _rows.length)))
                        else
                          SliverFillRemaining(
                              hasScrollBody: false, child: content),
                      ])
                    : Column(
                        children: [header, totals, Expanded(child: content)]))),
      ]),
    );
  }

  Widget _desktopTable() {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AdaptiveDataTable(
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('الوصف')),
            DataColumn(label: Text('مدين')),
            DataColumn(label: Text('دائن')),
            DataColumn(label: Text('الرصيد')),
          ],
          rows: _rows.map((e) {
            final tip = e.isOpening
                ? 'رصيد افتتاحي'
                : [
                    if (e.ref.isNotEmpty) 'ref: ${e.ref}',
                    if (e.source.isNotEmpty) 'source: ${e.source}',
                    if (e.sourceId.isNotEmpty) 'source_id: ${e.sourceId}',
                    if (e.partyType.isNotEmpty || e.partyId.isNotEmpty)
                      'party: ${e.partyType}:${e.partyId}',
                    if (e.invoiceId.isNotEmpty) 'invoice: ${e.invoiceId}',
                    if (e.repairId.isNotEmpty) 'repair: ${e.repairId}',
                  ].join('  •  ');
            return DataRow(cells: [
              DataCell(Text(_df.format(e.date))),
              DataCell(
                Tooltip(
                  message: tip.isEmpty ? '—' : tip,
                  child: Text(
                    e.isOpening ? 'رصيد افتتاحي' : e.description,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              DataCell(Text(
                e.isOpening ? '0.00' : _money.format(e.debit),
                style: const TextStyle(color: AppColors.primary),
              )),
              DataCell(Text(
                e.isOpening ? '0.00' : _money.format(e.credit),
                style: const TextStyle(color: Colors.red),
              )),
              DataCell(Text(
                _money.format(e.runningBalance),
                style: TextStyle(
                  color: e.runningBalance >= 0 ? AppColors.primary : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  bool get _isCashAccount =>
      const {'1000', '1010', '1020', '1030'}.contains(_accountCode);
  String get _debitLabel => _isCashAccount ? 'وارد إلى الحساب' : 'حركات مدينة';
  String get _creditLabel => _isCashAccount ? 'منصرف من الحساب' : 'حركات دائنة';

  Widget _mobileList() => ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (_, index) => _movementCard(_rows[index]));

  Widget _movementCard(_Row e) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    e.isOpening
                        ? 'رصيد بداية الفترة'
                        : e.description.isEmpty
                            ? 'حركة مالية'
                            : e.description,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_df.format(e.date),
                    style: const TextStyle(color: Colors.black54)),
                if (e.ref.isNotEmpty) Text('رقم المستند: ${e.ref}'),
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  if (!e.isOpening && e.debit != 0)
                    Text('$_debitLabel: ${_money.format(e.debit)}',
                        style: const TextStyle(
                            color: Colors.teal, fontWeight: FontWeight.bold)),
                  if (!e.isOpening && e.credit != 0)
                    Text('$_creditLabel: ${_money.format(e.credit)}',
                        style: const TextStyle(
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold)),
                ]),
                const Divider(height: 24),
                Text('الرصيد بعد الحركة: ${_money.format(e.runningBalance)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (e.entryId != null)
                  Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                          onPressed: () =>
                              showGlEntryDetails(context, e.entryId!),
                          icon:
                              const Icon(Icons.receipt_long_outlined, size: 18),
                          label: const Text('تفاصيل الحركة والمستند'))),
              ],
            )),
      );

  Widget _stat(String label, double value, Color color, {bool bold = false}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(_money.format(value),
              style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ]),
      );
}

class _Row {
  final bool isOpening;
  final int? entryId; // null للرصيد الافتتاحي
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final String accountCode;
  final String accountName;

  final String partyType;
  final String partyId;
  final String invoiceId;
  final String repairId;
  final String ref;
  final String source;
  final String sourceId;

  final double runningBalance;

  _Row({
    required this.isOpening,
    required this.entryId,
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.accountCode,
    required this.accountName,
    required this.partyType,
    required this.partyId,
    required this.invoiceId,
    required this.repairId,
    required this.ref,
    required this.source,
    required this.sourceId,
    required this.runningBalance,
  });

  factory _Row.opening({required DateTime date, required double amount}) {
    return _Row(
      isOpening: true,
      entryId: null,
      date: date,
      description: 'رصيد افتتاحي',
      debit: 0.0,
      credit: 0.0,
      accountCode: '',
      accountName: '',
      partyType: '',
      partyId: '',
      invoiceId: '',
      repairId: '',
      ref: '',
      source: '',
      sourceId: '',
      runningBalance: amount,
    );
  }
}

// ───────────── حالة فراغ ─────────────
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
