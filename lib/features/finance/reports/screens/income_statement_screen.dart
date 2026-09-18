import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';
// 📁 lib/features/finance/reports/screens/income_statement_screen.dart
//
// قائمة الدخل — Income Statement (GL v29/v30)
// -------------------------------------------------------------
// - المصدر: accounts + gl_entries + gl_lines عبر DBService فقط.
// - فلاتر: نطاق تاريخ (within JOIN على gl_entries) + بحث باسم/كود الحساب.
// - تجميع: REVENUE / EXPENSE + صافي الربح/الخسارة.
// - عرض: جدولي على الديسكتوب + بطاقات على الموبايل.
// - تصدير: CSV + PDF (A4، RTL).
// - Drill-through: فتح GL للحساب وتمرير نفس الفلاتر.
// - خيار "إظهار الصفرية" لإظهار الحسابات بلا حركة.
//
// performance indexes المقترحة:
// CREATE INDEX IF NOT EXISTS idx_gl_lines_account ON gl_lines(account_id);
// CREATE INDEX IF NOT EXISTS idx_gl_entries_date  ON gl_entries(date);

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
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class IncomeStatementScreen extends StatefulWidget {
  const IncomeStatementScreen({super.key});

  @override
  State<IncomeStatementScreen> createState() => _IncomeStatementScreenState();
}

class _IncomeStatementScreenState extends State<IncomeStatementScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  DateTime? _from;
  DateTime? _to;
  String _query = '';
  bool _showZeroRows = false;

  bool _loading = true;
  String? _error;

  // نتائج
  List<_Row> _revenues = [];
  List<_Row> _expenses = [];
  double _sumRev = 0.0;
  double _sumExp = 0.0;

  // PDF Font cache
  static const String _arabicTtfPath = 'fonts/Cairo/Cairo-Regular.ttf';
  pw.Font? _pdfArabicFont;

  static const double _eps = 0.000001;

  @override
  void initState() {
    super.initState();
    _load();
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

  // ───────────── Load ─────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _revenues = [];
      _expenses = [];
      _sumRev = 0.0;
      _sumExp = 0.0;
    });

    try {
      if (_from != null && _to != null && _from!.isAfter(_to!)) {
        throw ArgumentError('بداية الفترة بعد نهايتها');
      }
      final db = await DBService.database;

      // شروط التاريخ داخل LEFT JOIN على gl_entries للحفاظ على الحسابات بلا حركة
      final joinDateConds = <String>[];
      final args = <Object?>[];

      if (_from != null) {
        joinDateConds.add('substr(e.date,1,10) >= substr(?,1,10)');
        args.add(_dayStart(_from!).toIso8601String());
      }
      if (_to != null) {
        joinDateConds.add('substr(e.date,1,10) <= substr(?,1,10)');
        args.add(_dayEnd(_to!).toIso8601String());
      }
      final joinDateSql =
          joinDateConds.isEmpty ? '' : ' AND ${joinDateConds.join(' AND ')}';

      // فلتر البحث على accounts فقط حتى لا نسقط الحسابات الصفرية
      final q = _query.trim();
      // دعم النوع أو الكود: 4xxx للإيرادات و 5xxx للمصاريف
      String whereAccounts =
          "(a.type IN ('REVENUE','EXPENSE') OR a.code LIKE '4%' OR a.code LIKE '5%')";
      if (q.isNotEmpty) {
        whereAccounts += " AND (LOWER(a.name) LIKE LOWER(?) OR a.code LIKE ?)";
        args.addAll(['%$q%', '%$q%']);
      }

      final sql = '''
        SELECT
          a.id                    AS account_id,
          IFNULL(a.code,'')       AS code,
          a.name                  AS name,
          a.type                  AS type,      -- REVENUE / EXPENSE
          IFNULL(SUM(CASE WHEN e.id IS NOT NULL THEN l.debit ELSE 0 END),0)  AS sdebit,
          IFNULL(SUM(CASE WHEN e.id IS NOT NULL THEN l.credit ELSE 0 END),0) AS scredit
        FROM accounts a
        LEFT JOIN gl_lines   l ON l.account_id = a.id
        LEFT JOIN gl_entries e ON e.id = l.entry_id $joinDateSql
        WHERE $whereAccounts
        GROUP BY a.id, a.code, a.name, a.type
        ORDER BY a.type ASC, a.code ASC
      ''';

      final maps = await db.rawQuery(sql, args);

      final rev = <_Row>[];
      final exp = <_Row>[];
      double sRev = 0.0, sExp = 0.0;

      for (final m in maps) {
        final id = (m['account_id'] as num).toInt();
        final code = (m['code'] ?? '').toString();
        final name = (m['name'] ?? '').toString();
        final type = (m['type'] ?? '').toString();
        final d = _toD(m['sdebit']);
        final c = _toD(m['scredit']);

        final isRevenue = type == 'REVENUE' || code.startsWith('4');
        final isExpense = type == 'EXPENSE' || code.startsWith('5');

        if (isRevenue) {
          final amt = c - d; // طبيعة دائن
          if (_showZeroRows || amt.abs() > _eps) {
            final amt2 = double.parse(amt.toStringAsFixed(2));
            rev.add(_Row(accountId: id, code: code, name: name, amount: amt2));
            sRev += amt2;
          }
        } else if (isExpense) {
          final amt = d - c; // طبيعة مدين
          if (_showZeroRows || amt.abs() > _eps) {
            final amt2 = double.parse(amt.toStringAsFixed(2));
            exp.add(_Row(accountId: id, code: code, name: name, amount: amt2));
            sExp += amt2;
          }
        }
      }

      setState(() {
        _revenues = rev;
        _expenses = exp;
        _sumRev = double.parse(sRev.toStringAsFixed(2));
        _sumExp = double.parse(sExp.toStringAsFixed(2));
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
      if (_revenues.isEmpty && _expenses.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير')),
        );
        return;
      }

      final sb = StringBuffer()..writeln('section,code,account,amount');

      for (final r in _revenues) {
        sb.writeln([
          'Revenue',
          r.code,
          r.name.replaceAll(',', ' '),
          r.amount.toStringAsFixed(2)
        ].join(','));
      }
      for (final r in _expenses) {
        sb.writeln([
          'Expense',
          r.code,
          r.name.replaceAll(',', ' '),
          r.amount.toStringAsFixed(2)
        ].join(','));
      }

      sb
        ..writeln(['Totals', '', 'Total Revenue', _sumRev.toStringAsFixed(2)]
            .join(','))
        ..writeln(['Totals', '', 'Total Expense', _sumExp.toStringAsFixed(2)]
            .join(','))
        ..writeln(['Totals', '', 'Net', (_sumRev - _sumExp).toStringAsFixed(2)]
            .join(','));

      final dir =
          await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/income_statement.csv');
      await file.writeAsString(sb.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'Income Statement');
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
      if (_revenues.isEmpty && _expenses.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير')),
        );
        return;
      }

      final font = await _loadPdfArabicFont();
      final doc = pw.Document();

      final net = _sumRev - _sumExp;
      final asOfText = [
        if (_from != null) 'من ${_df.format(_from!)}',
        if (_to != null) 'إلى ${_df.format(_to!)}',
      ].join(' • ');

      pw.Widget sectionTable(String title, int colorHex, List<_Row> rows) {
        final color = PdfColor.fromInt(colorHex);
        final sum = rows.fold<double>(0, (s, r) => s + r.amount);
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: color,
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  _money.format(sum),
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder(
                horizontalInside:
                    pw.BorderSide(width: .2, color: PdfColors.grey300),
                bottom: pw.BorderSide(width: .4, color: PdfColors.grey400),
                top: pw.BorderSide(width: .4, color: PdfColors.grey400),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2), // code
                1: pw.FlexColumnWidth(7), // name
                2: pw.FlexColumnWidth(3), // amount
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFEFEFEF)),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('الكود',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text('الحساب',
                            textDirection: pw.TextDirection.rtl,
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text('المبلغ',
                            textDirection: pw.TextDirection.rtl,
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                ...rows.map((r) {
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(r.code,
                            style: pw.TextStyle(font: font, fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(r.name,
                              textDirection: pw.TextDirection.rtl,
                              style: pw.TextStyle(font: font, fontSize: 10)),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(_money.format(r.amount),
                              textDirection: pw.TextDirection.rtl,
                              style: pw.TextStyle(font: font, fontSize: 10)),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],
        );
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => [
            // Header
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('قائمة الدخل',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold)),
                pw.Spacer(),
                if (asOfText.isNotEmpty)
                  pw.Text(asOfText,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                          font: font, fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(),

            // Totals
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                    color: const PdfColor.fromInt(0xFFE9F7EF),
                  ),
                  child: pw.Text('الإيرادات: ${_money.format(_sumRev)}',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 11,
                          color: const PdfColor.fromInt(0xFF67BC1F))),
                ),
                pw.SizedBox(width: 8),
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                    color: const PdfColor.fromInt(0xFFFFEBEE),
                  ),
                  child: pw.Text('المصاريف: ${_money.format(_sumExp)}',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                          font: font, fontSize: 11, color: PdfColors.red800)),
                ),
                pw.SizedBox(width: 8),
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                    color: (net >= 0
                        ? const PdfColor.fromInt(0xFFE9F7EF)
                        : const PdfColor.fromInt(0xFFFFEBEE)),
                  ),
                  child: pw.Text(
                    '${net >= 0 ? 'صافي الربح' : 'صافي الخسارة'}: ${_money.format(net.abs())}',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 11,
                      color: net >= 0
                          ? const PdfColor.fromInt(0xFF67BC1F)
                          : PdfColors.red800,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 14),

            // Sections
            sectionTable('الإيرادات', 0xFF67BC1F, _revenues),
            pw.SizedBox(height: 16),
            sectionTable('المصاريف', 0xFFC62828, _expenses),
          ],
        ),
      );

      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: 'income_statement.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير PDF: $e')),
      );
    }
  }

  // ───────────── Navigation ─────────────
  void _openGL(int accountId) {
    Navigator.of(context).pushNamed(
      AppRoutes.financeGL,
      arguments: {
        'accountId': accountId,
        'from': _from?.toIso8601String(),
        'to': _to != null ? _dayEnd(_to!).toIso8601String() : null,
        'query': '',
      },
    );
  }

  // ───────────── UI ─────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = !Responsive.isDesktop(context);
    final net = _sumRev - _sumExp;

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
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          const Text(
            'قائمة الدخل',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          // إظهار الصفوف الصفرية
          AdaptiveRow(
            children: [
              const Text('إظهار الصفرية',
                  style: TextStyle(color: Colors.white)),
              Switch(
                value: _showZeroRows,
                activeColor: Colors.white,
                onChanged: (v) {
                  setState(() => _showZeroRows = v);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(width: 8),
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
          _chip(
            label: _from == null ? 'من' : _df.format(_from!),
            icon: Icons.date_range,
            onTap: _pickFrom,
          ),
          const SizedBox(width: 8),
          _chip(
            label: _to == null ? 'إلى' : _df.format(_to!),
            icon: Icons.event,
            onTap: _pickTo,
          ),
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
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: 'مسح الفلاتر',
            onPressed: () {
              setState(() {
                _from = null;
                _to = null;
                _query = '';
                _showZeroRows = false;
              });
              _load();
            },
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
          _stat('إجمالي الإيرادات', _sumRev, AppColors.primary),
          _stat('إجمالي المصاريف', _sumExp, Colors.red),
          _stat(
            net >= 0 ? 'صافي الربح' : 'صافي الخسارة',
            net.abs(),
            net >= 0 ? AppColors.primary : Colors.red,
            bold: true,
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
      body: AdaptiveRow(
        children: [
          if (!isMobile)
            const YallaSidebar(currentRoute: '/finance/income-statement'),
          Expanded(
            child: SafeArea(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverToBoxAdapter(child: header),
                  SliverToBoxAdapter(child: totals),
                ],
                body: body,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Desktop =====
  Widget _tables() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AdaptiveRow(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الإيرادات
          Expanded(
            child: _section(
              title: 'الإيرادات',
              color: AppColors.primary,
              rows: _revenues,
            ),
          ),
          const SizedBox(width: 12),
          // المصاريف
          Expanded(
            child: _section(
              title: 'المصاريف',
              color: Colors.red,
              rows: _expenses,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required Color color,
    required List<_Row> rows,
  }) {
    final sum = rows.fold<double>(0, (s, r) => s + r.amount);
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            AdaptiveRow(
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
            Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: AdaptiveDataTable(
                  columns: const [
                    DataColumn(label: Text('الكود')),
                    DataColumn(label: Text('الحساب')),
                    DataColumn(label: Text('المبلغ')),
                    DataColumn(label: Text('GL')),
                  ],
                  rows: rows
                      .map(
                        (r) => DataRow(
                          cells: [
                            DataCell(Text(r.code.isEmpty ? '—' : r.code)),
                            DataCell(Text(r.name, textAlign: TextAlign.right)),
                            DataCell(Text(_money.format(r.amount),
                                style: TextStyle(color: color))),
                            DataCell(
                              IconButton(
                                tooltip: 'عرض الأستاذ العام للحساب',
                                icon: const Icon(Icons.open_in_new),
                                onPressed: () => _openGL(r.accountId),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
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
        _cardSection('الإيرادات', AppColors.primary, _revenues),
        const SizedBox(height: 12),
        _cardSection('المصاريف', Colors.red, _expenses),
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
            AdaptiveRow(
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
                title: Text(
                  '${r.code.isEmpty ? '—' : r.code} — ${r.name}',
                  textAlign: TextAlign.right,
                ),
                trailing: Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_money.format(r.amount),
                        style: TextStyle(color: color)),
                    IconButton(
                      tooltip: 'عرض الأستاذ العام للحساب',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => _openGL(r.accountId),
                    ),
                  ],
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

// ===== Model =====
class _Row {
  final int accountId;
  final String code;
  final String name;
  final double amount;
  _Row({
    required this.accountId,
    required this.code,
    required this.name,
    required this.amount,
  });
}
