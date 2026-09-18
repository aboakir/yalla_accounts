// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/screens/cheques_report_screen.dart
//
// ChequesReportScreen — تقرير الشيكات (PRO MAX v3 - Fixed const issues)
// -----------------------------------------------------------------------------
// • فلترة متقدمة: بحث – نوع – حالة – بنك – فرع – عملة – مبلغ من/إلى – إصدار/استحقاق من/إلى
// • أزرار ذكية: المستحقة خلال 3 أيام – المتأخرة – اليوم – الأسبوع – الشهر الحالي
// • ملخصات عليا: عدد الشيكات + إجمالي القيمة + مجاميع حسب النوع + مجاميع حسب الحالة
// • "رسوم" مبسطة (Bars) لتوزيع الشيكات حسب النوع والحالة بدون باكدجات إضافية
// • قراءة مباشرة من SQLite عبر DBService فقط
// • عرض DataTable احترافي + مجموع إجمالي قيم الشيكات (بالواجهة وبـ PDF/Excel)
// • تصدير PDF بخط عربي Cairo-Bold + ملخصات أعلى التقرير + مجاميع لكل حالة
// • تصدير Excel مع نفس الملخصات
// • Sidebar ثابت للديسكتوب / Drawer للموبايل
// • بدون RTL عام — فقط TextAlign.right حيث يلزم
// -----------------------------------------------------------------------------

import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class ChequesReportScreen extends ConsumerStatefulWidget {
  const ChequesReportScreen({super.key});

  @override
  ConsumerState<ChequesReportScreen> createState() =>
      _ChequesReportScreenState();
}

class _ChequesReportScreenState extends ConsumerState<ChequesReportScreen> {
  final df = DateFormat("yyyy-MM-dd");

  // ===== Filters =====
  String search = '';
  String? typeFilter;
  String? statusFilter;
  String? bankFilter;
  String? branchFilter;
  String? currencyFilter;
  double? amountMin;
  double? amountMax;

  DateTime? issueFrom;
  DateTime? issueTo;
  DateTime? dueFrom;
  DateTime? dueTo;

  // ===== Data =====
  List<Map<String, dynamic>> rows = [];
  bool loading = false;

  // ===== Stats =====
  int totalCount = 0;
  double totalAmount = 0;

  double incomingSum = 0;
  double outgoingSum = 0;
  double collectionSum = 0;

  double pendingSum = 0;
  double collectedSum = 0;
  double returnedSum = 0;
  double cancelledSum = 0;
  double deliveredSum = 0;
  double depositedSum = 0;
  double overdueSum = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // =============================================================================
  // LOAD DATA + STATS
  // =============================================================================
  Future<void> _load() async {
    setState(() => loading = true);

    final db = await DBService.database;

    final where = <String>[];
    final args = <Object?>[];

    // بحث شامل
    if (search.isNotEmpty) {
      where.add(
        "("
        "cheque_no LIKE ? OR "
        "drawer_name LIKE ? OR "
        "bank_name LIKE ? OR "
        "bank_branch LIKE ? OR "
        "currency LIKE ? OR "
        "status LIKE ? OR "
        "cheque_type LIKE ?"
        ")",
      );
      final like = "%$search%";
      args.addAll([like, like, like, like, like, like, like]);
    }

    // نوع الشيك
    if (typeFilter != null) {
      where.add("cheque_type = ?");
      args.add(typeFilter);
    }

    // حالة الشيك
    if (statusFilter != null) {
      where.add("status = ?");
      args.add(statusFilter);
    }

    // بنك / فرع / عملة
    if (bankFilter != null && bankFilter!.trim().isNotEmpty) {
      where.add("bank_name LIKE ?");
      args.add("%${bankFilter!.trim()}%");
    }
    if (branchFilter != null && branchFilter!.trim().isNotEmpty) {
      where.add("bank_branch LIKE ?");
      args.add("%${branchFilter!.trim()}%");
    }
    if (currencyFilter != null && currencyFilter!.trim().isNotEmpty) {
      where.add("currency LIKE ?");
      args.add("%${currencyFilter!.trim()}%");
    }

    // مبلغ من/إلى
    if (amountMin != null) {
      where.add("amount >= ?");
      args.add(amountMin);
    }
    if (amountMax != null) {
      where.add("amount <= ?");
      args.add(amountMax);
    }

    // تواريخ إصدار
    if (issueFrom != null) {
      where.add("DATE(issue_date) >= DATE(?)");
      args.add(df.format(issueFrom!));
    }

    if (issueTo != null) {
      where.add("DATE(issue_date) <= DATE(?)");
      args.add(df.format(issueTo!));
    }

    // تواريخ استحقاق
    if (dueFrom != null) {
      where.add("DATE(due_date) >= DATE(?)");
      args.add(df.format(dueFrom!));
    }

    if (dueTo != null) {
      where.add("DATE(due_date) <= DATE(?)");
      args.add(df.format(dueTo!));
    }

    final sql = """
      SELECT *
      FROM cheques
      ${where.isEmpty ? "" : "WHERE ${where.join(" AND ")}"}
      ORDER BY DATE(due_date) ASC, DATE(issue_date) ASC
    """;

    rows = await db.rawQuery(sql, args);

    _recalcStats();

    setState(() => loading = false);
  }

  void _recalcStats() {
    totalCount = rows.length;
    totalAmount = 0;

    incomingSum = 0;
    outgoingSum = 0;
    collectionSum = 0;

    pendingSum = 0;
    collectedSum = 0;
    returnedSum = 0;
    cancelledSum = 0;
    deliveredSum = 0;
    depositedSum = 0;
    overdueSum = 0;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    for (final r in rows) {
      final rawAmount = r['amount'];
      double amount = 0;
      if (rawAmount is num) {
        amount = rawAmount.toDouble();
      } else if (rawAmount is String) {
        amount = double.tryParse(rawAmount.replaceAll(",", "")) ?? 0;
      }

      totalAmount += amount;

      final type = (r['cheque_type'] ?? '').toString();
      final status = (r['status'] ?? '').toString();

      switch (type) {
        case 'incoming':
          incomingSum += amount;
          break;
        case 'outgoing':
          outgoingSum += amount;
          break;
        case 'collection':
          collectionSum += amount;
          break;
      }

      switch (status) {
        case 'pending':
          pendingSum += amount;
          break;
        case 'collected':
          collectedSum += amount;
          break;
        case 'returned':
          returnedSum += amount;
          break;
        case 'cancelled':
          cancelledSum += amount;
          break;
        case 'delivered':
          deliveredSum += amount;
          break;
        case 'deposited':
          depositedSum += amount;
          break;
      }

      // متأخرة: استحقاق قبل اليوم الحالي
      final dueStr = (r['due_date'] ?? '').toString();
      if (dueStr.isNotEmpty) {
        try {
          final d = DateTime.parse(dueStr);
          final dd = DateTime(d.year, d.month, d.day);
          if (dd.isBefore(todayDate)) {
            overdueSum += amount;
          }
        } catch (_) {
          // تجاهل خطأ التاريخ
        }
      }
    }
  }

  String _fmtAmount(double v) {
    final nf = NumberFormat('#,##0.00', 'en');
    return nf.format(v);
  }

  // =============================================================================
  // PDF EXPORT — Cairo-Bold + ملخصات + مجاميع لكل حالة
  // =============================================================================
  Future<void> _exportPDF() async {
    try {
      final fonts = await _loadArabicFontSet();

      final theme = pw.ThemeData.withFont(
        base: fonts.base,
        bold: fonts.bold,
        italic: fonts.base,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(fontFallback: fonts.fallbacks),
      );

      pw.Widget ar(String text, {pw.TextStyle? style}) {
        return pw.Text(
          text,
          textAlign: pw.TextAlign.right,
          style: (style ?? pw.TextStyle())
              .copyWith(font: fonts.bold, fontSize: (style?.fontSize ?? 11)),
        );
      }

      pw.Widget ltr(String text, {pw.TextStyle? style}) {
        return pw.Text(
          text,
          textAlign: pw.TextAlign.left,
          style: style,
        );
      }

      pw.Widget headerCell(String text) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: pw.Alignment.centerRight,
          child: ar(
            text,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      }

      pw.Widget cellWidget(pw.Widget child,
          {pw.Alignment alignment = pw.Alignment.centerRight}) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: alignment,
          child: child,
        );
      }

      final pdf = pw.Document(theme: theme);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // العنوان الرئيسي
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: ar(
                    "تقرير الشيكات",
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      font: fonts.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),

                // التاريخ (إنجليزي)
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: ltr(
                    "Generated at: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}",
                    style: pw.TextStyle(fontSize: 9),
                  ),
                ),
                pw.SizedBox(height: 10),

                // ملخص علوي
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          ar("عدد الشيكات: $totalCount",
                              style: pw.TextStyle(fontSize: 11)),
                          ar("إجمالي القيمة: ${_fmtAmount(totalAmount)}",
                              style: pw.TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          ar("إجمالي الواردة: ${_fmtAmount(incomingSum)}",
                              style: pw.TextStyle(fontSize: 10)),
                          ar("إجمالي الصادرة: ${_fmtAmount(outgoingSum)}",
                              style: pw.TextStyle(fontSize: 10)),
                          ar("إجمالي قيد التحصيل: ${_fmtAmount(collectionSum)}",
                              style: pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          ar("إجمالي المتأخرة: ${_fmtAmount(overdueSum)}",
                              style: pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.red,
                              )),
                          ar("إجمالي المُحصّلة: ${_fmtAmount(collectedSum)}",
                              style: pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 14),

                // جدول مجاميع حسب الحالة
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: ar(
                    "مجاميع حسب حالة الشيك",
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey600,
                    width: 0.6,
                  ),
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        headerCell("الحالة"),
                        headerCell("إجمالي القيمة"),
                      ],
                    ),
                    _statusSummaryRow(ar, cellWidget, "معلّق", pendingSum),
                    _statusSummaryRow(ar, cellWidget, "مُحصّل", collectedSum),
                    _statusSummaryRow(ar, cellWidget, "راجع", returnedSum),
                    _statusSummaryRow(ar, cellWidget, "ملغى", cancelledSum),
                    _statusSummaryRow(ar, cellWidget, "مُسلّم", deliveredSum),
                    _statusSummaryRow(ar, cellWidget, "مودع", depositedSum),
                    _statusSummaryRow(ar, cellWidget, "متأخر", overdueSum),
                  ],
                ),

                pw.SizedBox(height: 16),

                // جدول الشيكات التفصيلي
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey600,
                    width: 0.7,
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.2), // رقم الشيك
                    1: pw.FlexColumnWidth(1.3), // القيمة
                    2: pw.FlexColumnWidth(1.1), // النوع
                    3: pw.FlexColumnWidth(1.1), // الحالة
                    4: pw.FlexColumnWidth(1.8), // البنك
                    5: pw.FlexColumnWidth(1.3), // الإصدار
                    6: pw.FlexColumnWidth(1.3), // الاستحقاق
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      children: [
                        headerCell("رقم الشيك"),
                        headerCell("القيمة"),
                        headerCell("النوع"),
                        headerCell("الحالة"),
                        headerCell("البنك"),
                        headerCell("الإصدار"),
                        headerCell("الاستحقاق"),
                      ],
                    ),
                    ...rows.map((r) {
                      final chequeNo = (r['cheque_no'] ?? '').toString();
                      final amountStr =
                          "${r['amount'] ?? ''} ${r['currency'] ?? ''}";
                      final type = (r['cheque_type'] ?? '').toString();
                      final status = (r['status'] ?? '').toString();
                      final bankName = (r['bank_name'] ?? '').toString();
                      final bankBranch = (r['bank_branch'] ?? '').toString();
                      final issue = (r['issue_date'] ?? '').toString();
                      final due = (r['due_date'] ?? '').toString();

                      return pw.TableRow(
                        children: [
                          cellWidget(ar(chequeNo)),
                          cellWidget(
                            ltr(amountStr),
                            alignment: pw.Alignment.centerRight,
                          ),
                          cellWidget(ar(_typeLabel(type))),
                          cellWidget(ar(_statusLabel(status))),
                          cellWidget(
                            ar(
                              bankBranch.isEmpty
                                  ? bankName
                                  : "$bankName - $bankBranch",
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          cellWidget(ltr(issue)),
                          cellWidget(ltr(due)),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            );
          },
        ),
      );

      Directory baseDir;
      try {
        baseDir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final ts = DateTime.now();
      final name =
          "cheques_report_${DateFormat('yyyyMMdd_HHmmss').format(ts)}.pdf";
      final file = File("${baseDir.path}/$name");
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "تم حفظ التقرير:\n${file.path}",
            textAlign: TextAlign.right,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "خطأ أثناء إنشاء PDF: $e",
            textAlign: TextAlign.right,
          ),
        ),
      );
    }
  }

  pw.TableRow _statusSummaryRow(
    pw.Widget Function(String, {pw.TextStyle? style}) ar,
    pw.Widget Function(pw.Widget child, {pw.Alignment alignment}) cellWidget,
    String statusLabel,
    double sum,
  ) {
    return pw.TableRow(
      children: [
        cellWidget(ar(statusLabel)),
        cellWidget(
          ar(_fmtAmount(sum)),
        ),
      ],
    );
  }

  // =============================================================================
  // EXCEL EXPORT — مع ملخصات
  // =============================================================================
  Future<void> _exportExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['ChequesReport'];

      // ملخص علوي
      sheet.appendRow([
        TextCellValue("تقرير الشيكات (Yallah Accounts)"),
      ]);
      sheet.appendRow([
        TextCellValue("عدد الشيكات"),
        TextCellValue(totalCount.toString()),
        TextCellValue("إجمالي القيمة"),
        TextCellValue(_fmtAmount(totalAmount)),
      ]);
      sheet.appendRow([
        TextCellValue("إجمالي الواردة"),
        TextCellValue(_fmtAmount(incomingSum)),
        TextCellValue("إجمالي الصادرة"),
        TextCellValue(_fmtAmount(outgoingSum)),
        TextCellValue("إجمالي قيد التحصيل"),
        TextCellValue(_fmtAmount(collectionSum)),
      ]);
      sheet.appendRow([
        TextCellValue("إجمالي المتأخرة"),
        TextCellValue(_fmtAmount(overdueSum)),
        TextCellValue("إجمالي المُحصّلة"),
        TextCellValue(_fmtAmount(collectedSum)),
      ]);

      sheet.appendRow([]); // سطر فارغ

      // رؤوس الجدول
      final headerRowIndex = sheet.rows.length;
      sheet.appendRow([
        TextCellValue("رقم الشيك"),
        TextCellValue("القيمة"),
        TextCellValue("النوع"),
        TextCellValue("الحالة"),
        TextCellValue("البنك"),
        TextCellValue("الإصدار"),
        TextCellValue("الاستحقاق"),
      ]);

      // بيانات الشيكات
      for (final r in rows) {
        final chequeNo = (r['cheque_no'] ?? '').toString();
        final amountStr = "${r['amount'] ?? ''} ${r['currency'] ?? ''}";
        final type = (r['cheque_type'] ?? '').toString();
        final status = (r['status'] ?? '').toString();
        final bankName = (r['bank_name'] ?? '').toString();
        final bankBranch = (r['bank_branch'] ?? '').toString();
        final issue = (r['issue_date'] ?? '').toString();
        final due = (r['due_date'] ?? '').toString();

        sheet.appendRow([
          TextCellValue(chequeNo),
          TextCellValue(amountStr),
          TextCellValue(_typeLabel(type)),
          TextCellValue(_statusLabel(status)),
          TextCellValue(
              bankBranch.isEmpty ? bankName : "$bankName - $bankBranch"),
          TextCellValue(issue),
          TextCellValue(due),
        ]);
      }

      // تنسيق بسيط للرؤوس (إن أمكن)
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.grey50,
      );
      final headerRow = sheet.row(headerRowIndex);
      for (final cell in headerRow) {
        cell?.cellStyle = headerStyle;
      }

      Directory baseDir;
      try {
        baseDir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final ts = DateTime.now();
      final name =
          "cheques_report_${DateFormat('yyyyMMdd_HHmmss').format(ts)}.xlsx";
      final file = File("${baseDir.path}/$name");
      final bytes = excel.encode();
      if (bytes == null) {
        _snack("Excel encoding failed");
        return;
      }
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      _snack("تم حفظ ملف Excel:\n${file.path}");
    } catch (e) {
      if (!mounted) return;
      _snack("خطأ أثناء تصدير Excel: $e");
    }
  }

  // =============================================================================
  // UI
  // =============================================================================
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const YallaAppBar(
        workshopName: "Yallah Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequesReport),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const YallaSidebar(currentRoute: AppRoutes.chequesReport),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1350),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // HEADER
                      const Text(
                        "تقرير الشيكات",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                        textAlign: TextAlign.right,
                      ),

                      const SizedBox(height: 24),

                      // ====== STATS ROW ======
                      _statsRow(),

                      const SizedBox(height: 24),

                      // ====== FILTERS ======
                      _filters(),

                      const SizedBox(height: 14),

                      // ====== QUICK FILTERS ======
                      _quickFiltersRow(),

                      const SizedBox(height: 20),

                      // ====== BAR CHARTS ======
                      Center(child: _simpleChartsRow()),

                      const SizedBox(height: 20),

                      // ====== EXPORT BUTTONS ======
                      _exports(),

                      const SizedBox(height: 20),

                      // ====== TABLE ======
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1350),
                          child: _table(),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================================
  // KPIs ROW — تصميم جديد صغير وأنيق
  // ==================================================================
  Widget _statsRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        _statCard(
          title: "عدد الشيكات",
          value: totalCount.toString(),
          color: AppColors.primary,
        ),
        _statCard(
          title: "إجمالي القيمة",
          value: _fmtAmount(totalAmount),
          color: Colors.teal.shade700,
        ),
        _statCard(
          title: "إجمالي الواردة",
          value: _fmtAmount(incomingSum),
          color: AppColors.primary,
        ),
        _statCard(
          title: "إجمالي الصادرة",
          value: _fmtAmount(outgoingSum),
          color: Colors.red.shade600,
        ),
        _statCard(
          title: "المتأخرة",
          value: _fmtAmount(overdueSum),
          color: Colors.orange.shade700,
        ),
      ],
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required Color color,
  }) {
    return SizedBox(
      width: 160,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // فلاتر أساسية + متقدمة
  Widget _filters() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 1350),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // -------------------------
              // ROW 1 — البحث + نوع الشيك + حالة الشيك
              // -------------------------
              Wrap(
                runSpacing: 12,
                spacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  // Search
                  SizedBox(
                    width: 240,
                    child: TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: const InputDecoration(
                        labelText: "بحث شامل...",
                        prefixIcon: Icon(Icons.search),
                      ),
                      textAlign: TextAlign.right,
                      onChanged: (v) {
                        search = v.trim();
                        _load();
                      },
                    ),
                  ),

                  // Cheque type
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: "نوع الشيك"),
                      value: typeFilter,
                      items: const [
                        DropdownMenuItem(value: null, child: Text("الكل")),
                        DropdownMenuItem(
                            value: "incoming", child: Text("وارد")),
                        DropdownMenuItem(
                            value: "outgoing", child: Text("صادر")),
                        DropdownMenuItem(
                            value: "collection", child: Text("قيد التحصيل")),
                      ],
                      onChanged: (v) {
                        typeFilter = v;
                        _load();
                      },
                    ),
                  ),

                  // Status
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: "حالة الشيك"),
                      value: statusFilter,
                      items: const [
                        DropdownMenuItem(value: null, child: Text("الكل")),
                        DropdownMenuItem(
                            value: "pending", child: Text("معلّق")),
                        DropdownMenuItem(
                            value: "collected", child: Text("مُحصّل")),
                        DropdownMenuItem(
                            value: "returned", child: Text("راجع")),
                        DropdownMenuItem(
                            value: "cancelled", child: Text("ملغى")),
                        DropdownMenuItem(
                            value: "delivered", child: Text("مُسلّم")),
                        DropdownMenuItem(
                            value: "deposited", child: Text("مودع")),
                      ],
                      onChanged: (v) {
                        statusFilter = v;
                        _load();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // -------------------------
              // ROW 2 — البنك + الفرع + العملة + مبلغ من/إلى
              // -------------------------
              Wrap(
                runSpacing: 12,
                spacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  // Bank
                  SizedBox(
                    width: 200,
                    child: TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: const InputDecoration(labelText: "البنك"),
                      textAlign: TextAlign.right,
                      onChanged: (v) {
                        bankFilter = v.trim().isEmpty ? null : v;
                        _load();
                      },
                    ),
                  ),

                  // Branch
                  SizedBox(
                    width: 200,
                    child: TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: const InputDecoration(labelText: "الفرع"),
                      textAlign: TextAlign.right,
                      onChanged: (v) {
                        branchFilter = v.trim().isEmpty ? null : v;
                        _load();
                      },
                    ),
                  ),

                  // Currency
                  SizedBox(
                    width: 150,
                    child: TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: const InputDecoration(labelText: "العملة"),
                      textAlign: TextAlign.right,
                      onChanged: (v) {
                        currencyFilter = v.trim().isEmpty ? null : v;
                        _load();
                      },
                    ),
                  ),

                  // Amount min
                  SizedBox(
                    width: 150,
                    child: TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: const InputDecoration(labelText: "مبلغ من"),
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        amountMin =
                            v.trim().isEmpty ? null : double.tryParse(v.trim());
                        _load();
                      },
                    ),
                  ),

                  // Amount max
                  SizedBox(
                    width: 150,
                    child: TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      decoration: const InputDecoration(labelText: "مبلغ إلى"),
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        amountMax =
                            v.trim().isEmpty ? null : double.tryParse(v.trim());
                        _load();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // -------------------------
              // ROW 3 — تواريخ الإصدار والاستحقاق (من / إلى)
              // -------------------------
              Wrap(
                runSpacing: 12,
                spacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  _date("إصدار من", issueFrom, (v) {
                    issueFrom = v;
                    _load();
                  }),
                  _date("إصدار إلى", issueTo, (v) {
                    issueTo = v;
                    _load();
                  }),
                  _date("استحقاق من", dueFrom, (v) {
                    dueFrom = v;
                    _load();
                  }),
                  _date("استحقاق إلى", dueTo, (v) {
                    dueTo = v;
                    _load();
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _date(String label, DateTime? value, Function(DateTime?) set) {
    return SizedBox(
      width: 180,
      child: GestureDetector(
        onTap: () async {
          final pick = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (pick != null) {
            set(pick);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(
            value == null ? "غير محدد" : df.format(value),
            textAlign: TextAlign.right,
          ),
        ),
      ),
    );
  }

  // فلاتر ذكية (زر واحد)
  Widget _quickFiltersRow() {
    return Wrap(
      alignment: WrapAlignment.end,
      runSpacing: 8,
      children: [
        _quickBtn("3 أيام", Colors.orange, () {
          final now = DateTime.now();
          dueFrom = DateTime(now.year, now.month, now.day);
          dueTo = dueFrom!.add(const Duration(days: 3));
          _load();
        }),
        const SizedBox(width: 8),
        _quickBtn("متأخرة", Colors.red, () {
          final now = DateTime.now();
          dueTo = DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 1));
          _load();
        }),
        const SizedBox(width: 8),
        _quickBtn("اليوم", AppColors.primary, () {
          final now = DateTime.now();
          final t = DateTime(now.year, now.month, now.day);
          dueFrom = t;
          dueTo = t;
          _load();
        }),
        const SizedBox(width: 8),
        _quickBtn("الأسبوع", Colors.blueGrey, () {
          final now = DateTime.now();
          final startOfWeek = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          dueFrom = startOfWeek;
          dueTo = endOfWeek;
          _load();
        }),
        const SizedBox(width: 8),
        _quickBtn("الشهر الحالي", Colors.indigo, () {
          final now = DateTime.now();
          final start = DateTime(now.year, now.month, 1);
          final end = DateTime(now.year, now.month + 1, 1)
              .subtract(const Duration(days: 1));
          dueFrom = start;
          dueTo = end;
          _load();
        }),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () {
            issueFrom = null;
            issueTo = null;
            dueFrom = null;
            dueTo = null;
            _load();
          },
          child: const Text("مسح التواريخ"),
        ),
      ],
    );
  }

  Widget _quickBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }

  // "رسوم" مبسطة: توزيع حسب النوع والحالة
  Widget _simpleChartsRow() {
    final totalForType = incomingSum + outgoingSum + collectionSum;
    final totalForStatus = pendingSum +
        collectedSum +
        returnedSum +
        cancelledSum +
        deliveredSum +
        depositedSum;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.end,
      children: [
        _barChartCard(
          title: "توزيع حسب نوع الشيك",
          rows: [
            _BarRow("وارد", incomingSum, totalForType, AppColors.primary),
            _BarRow("صادر", outgoingSum, totalForType, Colors.red),
            _BarRow("قيد التحصيل", collectionSum, totalForType, Colors.blue),
          ],
        ),
        _barChartCard(
          title: "توزيع حسب حالة الشيك",
          rows: [
            _BarRow("معلّق", pendingSum, totalForStatus, Colors.orange),
            _BarRow("مُحصّل", collectedSum, totalForStatus, AppColors.primary),
            _BarRow("راجع", returnedSum, totalForStatus, Colors.red),
            _BarRow("ملغى", cancelledSum, totalForStatus, Colors.grey),
            _BarRow("مُسلّم", deliveredSum, totalForStatus, Colors.blueGrey),
            _BarRow("مودع", depositedSum, totalForStatus, Colors.blue),
          ],
        ),
      ],
    );
  }

  Widget _barChartCard({
    required String title,
    required List<_BarRow> rows,
  }) {
    return SizedBox(
      width: 340,
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...rows
                  .where((r) => r.total > 0 && r.value > 0)
                  .map((r) => _barRowWidget(r)),
              if (rows.every((r) => r.value <= 0 || r.total <= 0))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "لا توجد بيانات كافية",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barRowWidget(_BarRow r) {
    final ratio = r.total <= 0 ? 0.0 : (r.value / r.total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AdaptiveRow(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(r.color),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: Text(
                  _fmtAmount(r.value),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    color: r.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            r.label,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  // أزرار التصدير
  Widget _exports() {
    return Wrap(
      alignment: WrapAlignment.end,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text("تصدير PDF"),
          onPressed: rows.isEmpty ? null : _exportPDF,
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.table_chart),
          label: const Text("تصدير Excel"),
          onPressed: rows.isEmpty ? null : _exportExcel,
        ),
      ],
    );
  }

  Widget _table() {
    if (rows.isEmpty) {
      return const Center(child: Text("لا توجد نتائج مطابقة"));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        headingRowColor:
            MaterialStateColor.resolveWith((_) => AppColors.primary),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        columns: const [
          DataColumn(label: Text("رقم الشيك")),
          DataColumn(label: Text("القيمة")),
          DataColumn(label: Text("النوع")),
          DataColumn(label: Text("الحالة")),
          DataColumn(label: Text("البنك")),
          DataColumn(label: Text("الإصدار")),
          DataColumn(label: Text("الاستحقاق")),
        ],
        rows: rows.map((r) {
          final type = (r['cheque_type'] ?? '').toString();
          final status = (r['status'] ?? '').toString();
          final bankName = (r['bank_name'] ?? '').toString();
          final bankBranch = (r['bank_branch'] ?? '').toString();

          return DataRow(
            cells: [
              DataCell(Text(r['cheque_no']?.toString() ?? "")),
              DataCell(Text("${r['amount']} ${r['currency'] ?? ''}")),
              DataCell(Text(_typeLabel(type))),
              DataCell(Text(_statusLabel(status))),
              DataCell(
                Text(
                  bankBranch.isEmpty ? bankName : "$bankName - $bankBranch",
                ),
              ),
              DataCell(Text(r['issue_date']?.toString() ?? "")),
              DataCell(Text(r['due_date']?.toString() ?? "")),
            ],
          );
        }).toList(),
      ),
    );
  }

  // =============================================================================
  // Helpers: نوع/حالة بالعربي + Snack
  // =============================================================================
  String _typeLabel(String v) {
    switch (v) {
      case 'incoming':
        return "وارد";
      case 'outgoing':
        return "صادر";
      case 'collection':
        return "قيد التحصيل";
      default:
        return v;
    }
  }

  String _statusLabel(String v) {
    switch (v) {
      case 'pending':
        return "معلّق";
      case 'collected':
        return "مُحصّل";
      case 'returned':
        return "راجع";
      case 'cancelled':
        return "ملغى";
      case 'delivered':
        return "مُسلّم";
      case 'deposited':
        return "مودع";
      default:
        return v;
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          textAlign: TextAlign.right,
        ),
      ),
    );
  }
}

// ===== Fonts loader with fallbacks (Cairo أولاً) =====

class _FontSet {
  final pw.Font base;
  final pw.Font bold;
  final List<pw.Font> fallbacks;
  _FontSet({
    required this.base,
    required this.bold,
    required this.fallbacks,
  });
}

Future<_FontSet> _loadArabicFontSet() async {
  pw.Font? base;
  pw.Font? bold;

  // نحاول أولاً Cairo
  try {
    base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
  } catch (_) {}

  try {
    bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
  } catch (_) {}

  // بدائل في حال فشل Cairo
  base ??= await _tryFirstFont([
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
        'assets/fonts/NotoSansArabic-Regular.ttf',
      ]) ??
      pw.Font.helvetica();
  bold ??= await _tryFirstFont([
        'assets/fonts/NotoNaskhArabic-Bold.ttf',
        'assets/fonts/NotoSansArabic-Bold.ttf',
      ]) ??
      base;

  final fallbacks = <pw.Font>[];
  for (final path in const [
    'assets/fonts/NotoNaskhArabic-Regular.ttf',
    'assets/fonts/NotoSansArabic-Regular.ttf',
    'assets/fonts/TraditionalArabic-Regular.ttf',
    'assets/fonts/Tahoma-Regular.ttf',
  ]) {
    try {
      fallbacks.add(pw.Font.ttf(await rootBundle.load(path)));
    } catch (_) {}
  }

  return _FontSet(base: base, bold: bold, fallbacks: fallbacks);
}

Future<pw.Font?> _tryFirstFont(List<String> paths) async {
  for (final pth in paths) {
    try {
      return pw.Font.ttf(await rootBundle.load(pth));
    } catch (_) {}
  }
  return null;
}

// هيكل بسيط لصفوف "الرسوم" (Bar-like)
class _BarRow {
  final String label;
  final double value;
  final double total;
  final Color color;

  _BarRow(this.label, this.value, this.total, this.color);
}
