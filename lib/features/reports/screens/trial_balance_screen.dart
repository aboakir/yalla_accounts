import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';
// 📁 lib/features/reports/screens/trial_balance_screen.dart
//
// ميزان المراجعة — Trial Balance (GL v30)
// -------------------------------------------------------------
// - يعتمد على: accounts, gl_entries, gl_lines عبر DBService.
// - فلاتر: نطاق تاريخ + بحث بالاسم/الكود + زر مسح سريع.
// - عرض: جدول على الديسكتوب + بطاقات على الموبايل.
// - مجاميع مدين/دائن + تحذير إذا كان الميزان غير متساوٍ.
// - تصدير CSV لما هو ظاهر (fallback لمجلد مؤقت إن لم تتوفر Downloads).
// - Drill-through: فتح GLBrowser للحساب المحدد وتمرير الفلاتر.
// - خيار "عرض الرصيد الصافي" لوضع صافي الحركة في جهة واحدة.
// - بدون إنشاء جداول أو بيانات وهمية.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:yalla_accounts/core/platform/yalla_path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class TrialBalanceScreen extends StatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  State<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends State<TrialBalanceScreen> {
  final _df = DateFormat('yyyy-MM-dd', 'ar');
  final _money = NumberFormat('#,##0.00', 'ar');

  DateTime? _from;
  DateTime? _to;
  String _query = '';
  bool _showNetSide = false; // عرض الرصيد الصافي في جهة واحدة
  bool _hideZeroRows = false; // إخفاء الحسابات الصفرية

  bool _loading = true;
  String? _error;

  List<_TBRow> _rows = [];
  double _sumDebit = 0.0, _sumCredit = 0.0;
  static const _arabicTtfPath = 'fonts/Cairo/Cairo-Regular.ttf';
  pw.Font? _pdfArabicFont;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      setState(() => _from = DateTime(d.year, d.month, d.day));
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
      setState(() => _to = DateTime(d.year, d.month, d.day, 23, 59, 59));
      _load();
    }
  }

  void _clearFilters() {
    setState(() {
      _from = null;
      _to = null;
      _query = '';
      _hideZeroRows = false;
      _showNetSide = false;
    });
    _load();
  }

  double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _exportCsv() async {
    try {
      if (_rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير')),
        );
        return;
      }

      final sb = StringBuffer()..writeln('code,account,debit,credit,net');
      for (final r in _rows) {
        final net = r.debit - r.credit;
        var debit = r.debit;
        var credit = r.credit;
        if (_showNetSide) {
          if (net >= 0) {
            debit = net;
            credit = 0.0;
          } else {
            debit = 0.0;
            credit = -net;
          }
        }
        sb.writeln([
          r.code,
          r.name.replaceAll(',', ' '),
          debit.toStringAsFixed(2),
          credit.toStringAsFixed(2),
          net.toStringAsFixed(2),
        ].join(','));
      }
      final totalDebit = _showNetSide ? _sumNetDebit() : _sumDebit;
      final totalCredit = _showNetSide ? _sumNetCredit() : _sumCredit;
      sb.writeln([
        'TOTAL',
        '',
        totalDebit.toStringAsFixed(2),
        totalCredit.toStringAsFixed(2),
        (totalDebit - totalCredit).toStringAsFixed(2),
      ].join(','));

      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getTemporaryDirectory();

      final file = File('${dir.path}/trial_balance.csv');
      await file.writeAsString(sb.toString(), encoding: utf8);
      await Share.shareXFiles([XFile(file.path)], text: 'Trial Balance Export');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير CSV: ${UserFacingError.message(e)}')),
      );
    }
  }

  Future<pw.Font> _loadPdfArabicFont() async {
    if (_pdfArabicFont != null) return _pdfArabicFont!;
    try {
      final data = await rootBundle.load(_arabicTtfPath);
      _pdfArabicFont = pw.Font.ttf(data);
    } catch (_) {
      _pdfArabicFont = pw.Font.helvetica();
    }
    return _pdfArabicFont!;
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
      final totalDebit = _showNetSide ? _sumNetDebit() : _sumDebit;
      final totalCredit = _showNetSide ? _sumNetCredit() : _sumCredit;
      final period = [
        if (_from != null) 'من ${_df.format(_from!)}',
        if (_to != null) 'إلى ${_df.format(_to!)}',
      ].join(' — ');

      final tableRows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            for (final label in const ['الكود', 'الحساب', 'مدين', 'دائن', 'الصافي'])
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  label,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
                ),
              ),
          ],
        ),
        ..._rows.map((r) {
          final net = r.debit - r.credit;
          var debit = r.debit;
          var credit = r.credit;
          if (_showNetSide) {
            if (net >= 0) {
              debit = net;
              credit = 0.0;
            } else {
              debit = 0.0;
              credit = -net;
            }
          }
          return pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(r.code, style: pw.TextStyle(font: font))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(r.name, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: font))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(debit.toStringAsFixed(2), style: pw.TextStyle(font: font))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(credit.toStringAsFixed(2), style: pw.TextStyle(font: font))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(net.toStringAsFixed(2), style: pw.TextStyle(font: font))),
            ],
          );
        }),
      ];

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            pw.Text(
              'ميزان المراجعة',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            if (period.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(period, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: font)),
            ],
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(5),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(2),
              },
              children: tableRows,
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'إجمالي مدين: ${totalDebit.toStringAsFixed(2)} | إجمالي دائن: ${totalCredit.toStringAsFixed(2)} | الفرق: ${(totalDebit - totalCredit).abs().toStringAsFixed(2)}',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        name: 'trial_balance.pdf',
        onLayout: (_) async => doc.save(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير PDF: ${UserFacingError.message(e)}')),
      );
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
      _sumDebit = 0.0;
      _sumCredit = 0.0;
    });

    try {
      if (_from != null && _to != null && _from!.isAfter(_to!)) {
        throw ArgumentError('بداية الفترة بعد نهايتها');
      }
      final db = await DBService.database;

      // شروط التاريخ داخل JOIN للحفاظ على LEFT JOIN
      final joinDateConds = <String>[];
      final joinArgs = <Object?>[];

      if (_from != null) {
        joinDateConds.add('substr(e.date,1,10) >= substr(?,1,10)');
        joinArgs.add(_from!.toIso8601String());
      }
      if (_to != null) {
        joinDateConds.add('substr(e.date,1,10) <= substr(?,1,10)');
        joinArgs.add(_to!.toIso8601String());
      }
      final joinDateSql =
          joinDateConds.isEmpty ? '' : ' AND ${joinDateConds.join(' AND ')}';

      final sql = '''
        SELECT
          a.id       AS account_id,
          a.code     AS code,
          a.name     AS name,
          IFNULL(SUM(CASE WHEN e.id IS NOT NULL THEN l.debit ELSE 0 END), 0)  AS sdebit,
          IFNULL(SUM(CASE WHEN e.id IS NOT NULL THEN l.credit ELSE 0 END), 0) AS scredit
        FROM accounts a
        LEFT JOIN gl_lines   l ON l.account_id = a.id
        LEFT JOIN gl_entries e ON e.id = l.entry_id $joinDateSql
        GROUP BY a.id, a.code, a.name
        ORDER BY a.code ASC
      ''';

      final maps = await db.rawQuery(sql, joinArgs);

      final q = _query.trim().toLowerCase();
      final out = <_TBRow>[];
      double sD = 0.0, sC = 0.0;

      for (final m in maps) {
        final code = (m['code'] ?? '').toString();
        final name = (m['name'] ?? '').toString();
        final debit = _toD(m['sdebit']);
        final credit = _toD(m['scredit']);

        if (_hideZeroRows &&
            debit.abs() < 0.000001 &&
            credit.abs() < 0.000001) {
          continue;
        }
        if (q.isNotEmpty &&
            !code.toLowerCase().contains(q) &&
            !name.toLowerCase().contains(q)) {
          continue;
        }

        out.add(_TBRow(
          accountId: (m['account_id'] as num).toInt(),
          code: code,
          name: name,
          debit: debit,
          credit: credit,
        ));
        sD += debit;
        sC += credit;
      }

      setState(() {
        _rows = out;
        _sumDebit = sD;
        _sumCredit = sC;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Trial balance load failed: $e');
      setState(() {
        _error = 'تعذر تحميل ميزان المراجعة. أعد المحاولة.';
        _loading = false;
      });
    }
  }

  void _openGLForAccount(_TBRow r) {
    Navigator.of(context).pushNamed(
      AppRoutes.financeGL,
      arguments: {
        'accountId': r.accountId,
        'from': _from?.toIso8601String(),
        'to': _to?.toIso8601String(),
        'query': _query,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !Responsive.isDesktop(context);

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
            Builder(
              builder: (menuContext) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(menuContext).openDrawer(),
              ),
            ),
          const Text(
            'ميزان المراجعة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          // الرصيد الصافي
          AdaptiveRow(
            children: [
              const Text('الرصيد الصافي',
                  style: TextStyle(color: Colors.white)),
              Switch(
                value: _showNetSide,
                activeColor: Colors.white,
                onChanged: (v) => setState(() => _showNetSide = v),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // إخفاء الحسابات الصفرية
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
              const Text('إخفاء الصفوف الصفرية',
                  style: TextStyle(color: Colors.white)),
              Switch(
                value: _hideZeroRows,
                activeColor: Colors.white,
                onChanged: (v) {
                  setState(() => _hideZeroRows = v);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(width: 8),
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
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off, color: Colors.white),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            onPressed: _loading ? null : _exportCsv,
            icon: const Icon(Icons.download, color: Colors.black87),
            label: const Text('CSV', style: TextStyle(color: Colors.black87)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            onPressed: _loading ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.black87),
            label: const Text('PDF', style: TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );

    final balanced = (_sumDebit - _sumCredit).abs() < 0.000001;

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
          _stat('إجمالي مدين', _showNetSide ? _sumNetDebit() : _sumDebit,
              AppColors.primary),
          _stat('إجمالي دائن', _showNetSide ? _sumNetCredit() : _sumCredit,
              Colors.red),
          Chip(
            backgroundColor:
                (balanced ? AppColors.primary : Colors.orange).withOpacity(.08),
            label: Text(
              balanced
                  ? '✅ الميزان متوازن'
                  : '⚠️ فرق: ${_money.format((_sumDebit - _sumCredit).abs())} (قبل وضع الصافي)',
              style: TextStyle(
                color: balanced ? AppColors.primary : Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
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
                    icon: Icons.balance,
                    title: 'لا توجد حركات ضمن الفلاتر الحالية',
                    subtitle:
                        'عدّل نطاق التاريخ أو أزل البحث لإظهار جميع الحسابات.',
                  )
                : (!Responsive.isDesktop(context) ? _cards() : _table());

    return Scaffold(
      drawer: !Responsive.isDesktop(context)
          ? const Drawer(child: YallaSidebar())
          : null,
      body: AdaptiveRow(
        children: [
          if (Responsive.isDesktop(context))
            const YallaSidebar(currentRoute: '/reports/trial-balance'),
          Expanded(
            child: SafeArea(
              child: NestedScrollView(
                  headerSliverBuilder: (_, __) => [
                        SliverToBoxAdapter(child: header),
                        SliverToBoxAdapter(child: totals)
                      ],
                  body: content),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Views =====

  Widget _table() {
    final cols = _showNetSide
        ? const [
            DataColumn(label: Text('الكود')),
            DataColumn(label: Text('الحساب')),
            DataColumn(label: Text('مدين')),
            DataColumn(label: Text('دائن')),
          ]
        : const [
            DataColumn(label: Text('الكود')),
            DataColumn(label: Text('الحساب')),
            DataColumn(label: Text('مدين')),
            DataColumn(label: Text('دائن')),
            DataColumn(label: Text('الصافي')),
          ];

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: AdaptiveDataTable(
          columns: cols,
          rows: _rows.map((r) {
            final net = r.debit - r.credit;

            double debit = r.debit;
            double credit = r.credit;
            if (_showNetSide) {
              if (net >= 0) {
                debit = net;
                credit = 0.0;
              } else {
                debit = 0.0;
                credit = -net;
              }
            }

            final cells = <DataCell>[
              DataCell(Text(r.code)),
              DataCell(
                InkWell(
                  onTap: () => _openGLForAccount(r),
                  child: Text(r.name, textAlign: TextAlign.right),
                ),
                onDoubleTap: () => _openGLForAccount(r),
              ),
              DataCell(Text(_money.format(debit),
                  style: const TextStyle(color: AppColors.primary))),
              DataCell(Text(_money.format(credit),
                  style: const TextStyle(color: Colors.red))),
              if (!_showNetSide)
                DataCell(Text(
                  _money.format(net),
                  style: TextStyle(
                    color: net >= 0 ? AppColors.primary : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                )),
            ];

            return DataRow(cells: cells);
          }).toList(),
        ),
      ),
    );
  }

  Widget _cards() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final net = r.debit - r.credit;

        double debit = r.debit;
        double credit = r.credit;
        if (_showNetSide) {
          if (net >= 0) {
            debit = net;
            credit = 0.0;
          } else {
            debit = 0.0;
            credit = -net;
          }
        }

        return Card(
          child: ListTile(
            onTap: () => _openGLForAccount(r),
            title: Text('${r.code} — ${r.name}', textAlign: TextAlign.right),
            subtitle: Text(
              _showNetSide
                  ? 'مدين: ${_money.format(debit)} • دائن: ${_money.format(credit)}'
                  : 'مدين: ${_money.format(r.debit)} • دائن: ${_money.format(r.credit)}',
              textAlign: TextAlign.right,
            ),
            trailing: !_showNetSide
                ? Text(
                    _money.format(net),
                    style: TextStyle(
                      color: net >= 0 ? AppColors.primary : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  // ===== Helpers (totals with net view) =====

  double _sumNetDebit() {
    double s = 0.0;
    for (final r in _rows) {
      final net = r.debit - r.credit;
      if (net > 0) s += net;
    }
    return s;
  }

  double _sumNetCredit() {
    double s = 0.0;
    for (final r in _rows) {
      final net = r.debit - r.credit;
      if (net < 0) s += -net;
    }
    return s;
  }

  // ===== Reusable UI bits =====

  Widget _stat(String label, double value, Color color) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_money.format(value),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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

// ===== Models =====

class _TBRow {
  final int accountId;
  final String code;
  final String name;
  final double debit;
  final double credit;

  _TBRow({
    required this.accountId,
    required this.code,
    required this.name,
    required this.debit,
    required this.credit,
  });
}

// ===== Empty State =====

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
