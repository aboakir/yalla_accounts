// 📁 lib/features/finance/screens/account_ledger_screen.dart
//
// الأستاذ العام لحساب واحد — Account Ledger (GL v29)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// PDF/Printing
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

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
  bool _loading = true;
  String? _error;

  // بيانات الجدول
  double _opening = 0.0;
  double _sumDebit = 0.0;
  double _sumCredit = 0.0;
  List<_Row> _rows = [];

  // PDF Font cache
  static const String _arabicTtfPath = 'fonts/Cairo/Cairo-Regular.ttf';
  pw.Font? _pdfArabicFont;

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

  void _resetFilters() {
    setState(() {
      _from = null;
      _to = null;
      _query = '';
    });
    _load();
  }

  // ───────────── Load ─────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _opening = 0;
      _sumDebit = 0;
      _sumCredit = 0;
      _rows = [];
    });

    try {
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
            AND e.date < ?
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
        where.add('e.date >= ?');
        args.add(_dayStart(_from!).toIso8601String());
      }
      if (_to != null) {
        where.add('e.date <= ?');
        args.add(_dayEnd(_to!).toIso8601String());
      }

      final q = _query.trim();
      if (q.isNotEmpty) {
        final s = '%$q%';
        where.add('('
            'e.ref LIKE ? OR e.note LIKE ? OR e.source LIKE ? OR e.source_id LIKE ? OR '
            'a.code LIKE ? OR a.name LIKE ? OR '
            'IFNULL(l.party_type, \'\') LIKE ? OR IFNULL(l.party_id, \'\') LIKE ? OR '
            'IFNULL(l.invoice_id, \'\') LIKE ? OR IFNULL(l.repair_id, \'\') LIKE ?'
            ')');
        args.addAll([s, s, s, s, s, s, s, s, s, s]);
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

      setState(() {
        _rows = rows;
        _sumDebit = double.parse(sumD.toStringAsFixed(2));
        _sumCredit = double.parse(sumC.toStringAsFixed(2));
        _loading = false;
      });
    } catch (e) {
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
        SnackBar(content: Text('فشل تصدير CSV: $e')),
      );
    }
  }

  // ───────────── PDF helpers ─────────────
  Future<pw.Font> _loadPdfArabicFont() async {
    if (_pdfArabicFont != null) return _pdfArabicFont!;
    try {
      final data = await rootBundle.load(_arabicTtfPath);
      _pdfArabicFont = pw.Font.ttf(data);
      return _pdfArabicFont!;
    } catch (_) {
      _pdfArabicFont = pw.Font.helvetica(); // fallback
      return _pdfArabicFont!;
    }
  }

  Future<void> _exportPdf() async {
    try {
      if (_rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير')),
        );
        return;
      }

      final font = await _loadPdfArabicFont();
      final doc = pw.Document();

      final asOfText = [
        if (_from != null) 'من ${_df.format(_from!)}',
        if (_to != null) 'إلى ${_df.format(_to!)}',
      ].join(' • ');

      final ending = _opening + (_sumDebit - _sumCredit);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => [
            // Header
            pw.Row(
              children: [
                pw.Text('الأستاذ العام',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold)),
                pw.Spacer(),
                pw.Text(
                    '${_accountCode.isEmpty ? '' : '$_accountCode — '}$_accountName',
                    style: pw.TextStyle(font: font, fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 4),
            if (asOfText.isNotEmpty)
              pw.Text(asOfText,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                      font: font, fontSize: 10, color: PdfColors.grey700)),
            pw.Divider(),

            // Totals
            pw.SizedBox(height: 6),
            pw.Row(children: [
              _pdfChip(font, 'افتتاحي: ${_money.format(_opening)}',
                  PdfColors.blue800, 0xFFE3F2FD),
              pw.SizedBox(width: 8),
              _pdfChip(font, 'مدين: ${_money.format(_sumDebit)}',
                  PdfColors.green800, 0xFFE9F7EF),
              pw.SizedBox(width: 8),
              _pdfChip(font, 'دائن: ${_money.format(_sumCredit)}',
                  PdfColors.red800, 0xFFFFEBEE),
              pw.SizedBox(width: 8),
              _pdfChip(
                  font,
                  'ختامي: ${_money.format(ending)}',
                  ending >= 0 ? PdfColors.green800 : PdfColors.red800,
                  ending >= 0 ? 0xFFE9F7EF : 0xFFFFEBEE),
            ]),
            pw.SizedBox(height: 10),

            // Table
            pw.Table(
              border: pw.TableBorder(
                horizontalInside:
                    pw.BorderSide(width: .2, color: PdfColors.grey300),
                bottom: pw.BorderSide(width: .4, color: PdfColors.grey400),
                top: pw.BorderSide(width: .4, color: PdfColors.grey400),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(5),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFEFEFEF)),
                  children: [
                    _cell(font, 'التاريخ', bold: true),
                    _cell(font, 'الوصف', bold: true, alignRight: true),
                    _cell(font, 'مدين', bold: true),
                    _cell(font, 'دائن', bold: true),
                    _cell(font, 'رصيد', bold: true),
                  ],
                ),
                if (_from != null)
                  pw.TableRow(children: [
                    _cell(font, _df.format(_dayStart(_from!))),
                    _cell(font, 'رصيد افتتاحي', alignRight: true),
                    _cell(font, '0.00'),
                    _cell(font, '0.00'),
                    _cell(font, _money.format(_opening)),
                  ]),
                ..._rows.where((r) => !r.isOpening).map((r) {
                  return pw.TableRow(children: [
                    _cell(font, _df.format(r.date)),
                    _cell(font, r.description.isEmpty ? '-' : r.description,
                        alignRight: true),
                    _cell(font, _money.format(r.debit)),
                    _cell(font, _money.format(r.credit)),
                    _cell(font, _money.format(r.runningBalance)),
                  ]);
                }),
              ],
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'ledger_${_accountCode.isEmpty ? 'account' : _accountCode}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير PDF: $e')),
      );
    }
  }

  pw.Widget _pdfChip(pw.Font font, String text, PdfColor fg, int bgHex) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(6),
        color: PdfColor.fromInt(bgHex),
      ),
      child: pw.Text(text,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: font, fontSize: 11, color: fg)),
    );
  }

  pw.Widget _cell(pw.Font font, String text,
      {bool bold = false, bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Align(
        alignment:
            alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          textDirection:
              alignRight ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: pw.TextStyle(
            font: font,
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ───────────── UI ─────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final ending = _opening + (_sumDebit - _sumCredit);

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
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الأستاذ العام للحساب',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _accountId == null
                      ? '—'
                      : '${_accountCode.isEmpty ? '' : '$_accountCode — '}$_accountName',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: TextField(
              textAlign: TextAlign.right,
              onChanged: (v) {
                setState(() => _query = v);
                _load();
              },
              decoration: InputDecoration(
                hintText: 'بحث: المرجع/الوصف/المصدر/طرف/فاتورة/ملف…',
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
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: 'مسح الفلاتر',
            onPressed: _resetFilters,
            icon: const Icon(Icons.clear_all, color: Colors.white),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download_rounded),
            label: const Text('CSV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
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
          _stat('رصيد افتتاحي', _opening, Colors.blueGrey),
          _stat('إجمالي مدين', _sumDebit, Colors.green),
          _stat('إجمالي دائن', _sumCredit, Colors.red),
          _stat(
            'الرصيد الختامي',
            ending,
            ending >= 0 ? Colors.green : Colors.red,
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
                    subtitle:
                        'عدّل التاريخ/البحث أو نفّذ عمليات تولّد قيود GL.',
                  )
                : (Responsive.isMobile(context)
                    ? _mobileList()
                    : _desktopTable());

    return Scaffold(
      drawer: Responsive.isMobile(context)
          ? const Drawer(child: YallaSidebar())
          : null,
      body: AdaptiveRow(
        children: [
          if (!Responsive.isMobile(context))
            const YallaSidebar(currentRoute: '/finance/gl'),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  header,
                  totals,
                  Expanded(child: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── Views ─────────────

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
                style: const TextStyle(color: Colors.green),
              )),
              DataCell(Text(
                e.isOpening ? '0.00' : _money.format(e.credit),
                style: const TextStyle(color: Colors.red),
              )),
              DataCell(Text(
                _money.format(e.runningBalance),
                style: TextStyle(
                  color: e.runningBalance >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _mobileList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = _rows[i];
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
        return Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            title: Text(
              e.isOpening ? 'رصيد افتتاحي' : e.description,
              textAlign: TextAlign.right,
            ),
            subtitle: Text(
              _df.format(e.date),
              textAlign: TextAlign.right,
            ),
            leading: Tooltip(
              message: tip.isEmpty ? '—' : tip,
              child: const Icon(Icons.info_outline),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money.format(e.runningBalance),
                  style: TextStyle(
                    color: e.runningBalance >= 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                AdaptiveRow(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.isOpening ? '0.00' : _money.format(e.debit),
                      style: const TextStyle(color: Colors.green),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      e.isOpening ? '0.00' : _money.format(e.credit),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────── UI bits ─────────────
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
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
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

// ───────────── Models داخلي ─────────────

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
