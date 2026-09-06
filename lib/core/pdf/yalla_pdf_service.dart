// -----------------------------------------------------------------------------
// 📁 lib/core/pdf/yalla_pdf_service.dart
// FINAL VERSION — Arabic + Workshop Header/Footer (No Logo Errors)
// -----------------------------------------------------------------------------

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/utils/public_text_sanitizer.dart';

// -----------------------------------------------------------------------------
class YallaPdfService {
  static late _FontSet _fonts;
  static bool _loaded = false;

  // ---------------------------------------------------------------------------
  // تحميل الخطوط
  // ---------------------------------------------------------------------------
  static Future<void> ensureFontsLoaded() async {
    if (_loaded) return;

    final base = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoNaskhArabic-Regular.ttf"),
    );

    final bold = pw.Font.ttf(
      await rootBundle.load("assets/fonts/NotoNaskhArabic-Bold.ttf"),
    );

    final fallbacks = <pw.Font>[
      pw.Font.ttf(
          await rootBundle.load("assets/fonts/TraditionalArabic-Regular.ttf")),
      pw.Font.ttf(await rootBundle.load("assets/fonts/Tahoma-Regular.ttf")),
      pw.Font.ttf(
          await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf")),
    ];

    _fonts = _FontSet(base: base, bold: bold, fallbacks: fallbacks);
    _loaded = true;
  }

  // ---------------------------------------------------------------------------
  // جلب بيانات الورشة
  // ---------------------------------------------------------------------------
  static Future<WorkshopSettings> _getWorkshop() async {
    return await WorkshopSettingsService.instance.getOrDefaults();
  }

  // ---------------------------------------------------------------------------
  // إنشاء مستند PDF
  // ---------------------------------------------------------------------------
  static Future<pw.Document> createDocument() async {
    await ensureFontsLoaded();

    final theme = pw.ThemeData.withFont(
      base: _fonts.base,
      bold: _fonts.bold,
      italic: _fonts.base,
    ).copyWith(
      defaultTextStyle: pw.TextStyle(
        fontFallback: _fonts.fallbacks,
        fontSize: 12,
      ),
    );

    return pw.Document(theme: theme);
  }

  // ---------------------------------------------------------------------------
  // الترويسة — بدون أي خطأ إذا لم يوجد لوجو
  // ---------------------------------------------------------------------------
  static Future<pw.Widget> buildHeader() async {
    final ws = await _getWorkshop();

    pw.Widget? logoWidget;

    // منطق لوجو آمن 100%
    try {
      if (ws.logoPath != null &&
          ws.logoPath!.trim().isNotEmpty &&
          ws.logoPath!.contains(RegExp(r'[:\\/]'))) {
        final file = File(ws.logoPath!);
        if (file.existsSync()) {
          final img = pw.MemoryImage(await file.readAsBytes());
          logoWidget = pw.Image(img, width: 80, height: 80);
        }
      }
    } catch (_) {
      // تجاهل أي خطأ نهائياً
      logoWidget = null;
    }

    // إذا لا يوجد لوجو → لا تعرض أي صورة
    logoWidget ??= pw.SizedBox(width: 80, height: 80);

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        logoWidget,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              ws.workshopName ?? "",
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: _fonts.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // التذييل
  // ---------------------------------------------------------------------------
  static Future<pw.Widget> buildFooter() async {
    final ws = await _getWorkshop();

    final address =
        "${ws.city ?? ""} - ${ws.address ?? ""}".replaceAll("null", "").trim();
    final phone = ws.phone1 ?? "";

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            address,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _fonts.base, fontSize: 10),
          ),
          pw.Text(
            phone,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _fonts.base, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // حفظ وفتح
  // ---------------------------------------------------------------------------
  static Future<File> saveToDownloads({
    required Uint8List bytes,
    required String fileName,
    String module = 'exports',
    DateTime? date,
  }) {
    return YallaStorageService.savePdf(
      bytes: bytes,
      module: module,
      fileName: fileName,
      date: date,
    );
  }

  static Future<File> saveAndOpen({
    required Uint8List bytes,
    required String fileName,
    String module = 'exports',
    DateTime? date,
  }) async {
    final f = await saveToDownloads(
      bytes: bytes,
      fileName: fileName,
      module: module,
      date: date,
    );
    await OpenFile.open(f.path);
    return f;
  }

  // ---------------------------------------------------------------------------
  // عناصر جاهزة
  // ---------------------------------------------------------------------------
  static pw.Widget ar(String text, {pw.TextStyle? style}) {
    return pw.Text(
      normalizePdfText(text),
      textDirection: pw.TextDirection.rtl,
      textAlign: pw.TextAlign.right,
      style: (style ?? const pw.TextStyle()).copyWith(font: _fonts.base),
    );
  }

  static pw.TableRow headerRow(List<String> titles) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: titles.map((t) => cell(t, header: true)).toList(),
    );
  }

  static pw.Widget cell(
    String text, {
    bool header = false,
  }) {
    final clean = normalizePdfText(text); // ✅ تنظيف إجباري
    final isAscii = RegExp(r'^[\x00-\x7F]+$').hasMatch(clean);

    return pw.Container(
      alignment: isAscii ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: pw.Text(
        clean, // ✅ النص بعد التنظيف
        textDirection: isAscii ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        textAlign: isAscii ? pw.TextAlign.left : pw.TextAlign.right,
        style: pw.TextStyle(
          font: isAscii
              ? _fonts.fallbacks.first // Tahoma
              : (header ? _fonts.bold : _fonts.base),
          fontSize: header ? 12 : 11,
          fontFallback: _fonts.fallbacks,
        ),
      ),
    );
  }

  static String normalizePdfText(String input) {
    if (input.isEmpty) return input;

    input = PublicTextSanitizer.sanitize(input);
    input = input.replaceAll('−', '-'); // ✅ حل U+2212
    input = latinNumbers(input); // ✅ أرقام إنجليزية

    return input;
  }

  // ---------------------------------------------------------------------------
  // PDF جدول عام
  // ---------------------------------------------------------------------------
  static Future<Uint8List> generateTablePdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final doc = await createDocument();
    final header = await buildHeader();
    final footer = await buildFooter();

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (ctx) => header,
        footer: (ctx) => footer,
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              title,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: _fonts.bold, fontSize: 20),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
            children: [
              headerRow(headers),
              ...rows.map(
                (r) => pw.TableRow(
                  children: List.generate(
                    headers.length,
                    (i) => cell(r[i]),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // PDF فاتورة مشتريات كاملة
  // ---------------------------------------------------------------------------
  static Future<Uint8List> generateFullInvoicePdf({
    required String invoiceNumber,
    required String date,
    required String supplierName,
    required String purchaseType,
    required String paymentMethod,
    required double totalAmount,
    required double paidAmount,
    required double remainAmount,
    required List<List<String>> rows,
  }) async {
    final doc = await createDocument();
    final header = await buildHeader();
    final footer = await buildFooter();

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (ctx) => header,
        footer: (ctx) => footer,
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              'فاتورة شراء رقم $invoiceNumber',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: _fonts.bold, fontSize: 22),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
            children: [
              pw.TableRow(children: [
                cell('رقم الفاتورة', header: true),
                cell(invoiceNumber),
              ]),
              pw.TableRow(children: [
                cell('التاريخ', header: true),
                cell(date),
              ]),
              pw.TableRow(children: [
                cell('اسم المورد', header: true),
                cell(supplierName),
              ]),
              pw.TableRow(children: [
                cell('نوع الشراء', header: true),
                cell(purchaseType),
              ]),
              pw.TableRow(children: [
                cell('طريقة الدفع', header: true),
                cell(paymentMethod),
              ]),
            ],
          ),
          pw.SizedBox(height: 25),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .6),
            children: [
              headerRow([
                'الصنف',
                'الكمية',
                'سعر الوحدة',
                'الإجمالي',
                'التصنيف',
              ]),
              ...rows.map(
                (r) => pw.TableRow(
                  children: List.generate(
                    5,
                    (i) => cell(r[i]),
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 25),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey700, width: .6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                      'إجمالي الفاتورة: ${YallaPdfService.fmt(totalAmount)}'),
                  pw.Text('المدفوع: ${YallaPdfService.fmt(paidAmount)}'),
                  pw.Text('المتبقي: ${YallaPdfService.fmt(remainAmount)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // // -----------------------------------------------------------------------------
// PDF — سند قبض (نسخة احترافية بالكامل)
// -----------------------------------------------------------------------------
  static Future<Uint8List> generateReceiptVoucherPdf({
    required String voucherId,
    required String date,
    required String clientName,
    required double amount,
    required String method,
    String? notes,
  }) async {
    await ensureFontsLoaded();
    final ws = await WorkshopSettingsService.instance.getOrDefaults();

    final doc = await createDocument();

    final header = await buildHeader();
    final footer = await buildFooter();

    final formattedDate = latinNumbers(
      DateFormat('yyyy-MM-dd')
          .format(DateTime.tryParse(date) ?? DateTime.now()),
    );
    final publicNotes = PublicTextSanitizer.sanitize(notes);

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        header: (ctx) => header,
        footer: (ctx) => footer,
        build: (ctx) => [
          // ----------------------------------------------------------
          // العنوان
          // ----------------------------------------------------------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                "سند قبض رقم ",
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _fonts.bold,
                  fontSize: 22,
                  fontFallback: _fonts.fallbacks,
                ),
              ),
              pw.Text(
                voucherId,
                textDirection: pw.TextDirection.ltr, // ← لأن UUID إنجليزي
                style: pw.TextStyle(
                  font: _fonts.bold,
                  fontSize: 22,
                  fontFallback: _fonts.fallbacks, // ← أهم شيء
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 25),

          pw.SizedBox(height: 25),

          // ----------------------------------------------------------
          // جدول البيانات الأساسية
          // ----------------------------------------------------------
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .7),
            children: [
              pw.TableRow(children: [
                cell("رقم السند", header: true),
                cell(voucherId),
              ]),
              headerRow(["التاريخ", formattedDate]),
              headerRow(["اسم العميل", clientName]),
              headerRow(["المبلغ المقبوض", fmt(amount)]),
              headerRow(["طريقة الدفع", method.toUpperCase()]),
            ],
          ),

          pw.SizedBox(height: 25),

          // ----------------------------------------------------------
          // الملاحظات إن وجدت
          // ----------------------------------------------------------
          if (publicNotes.isNotEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey700, width: .7),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                "ملاحظات: $publicNotes",
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<pw.ImageProvider?> _tryLoadLogo(String? path) async {
    if (path == null || path.trim().isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    return pw.MemoryImage(bytes);
  }

// =====================================================================
// PDF – Accounts Receivable (ذمم العملاء) — نسخة نهائية متوافقة 100%
// =====================================================================
  static Future<void> generateAccountsReceivablePdf(
    List<Map<String, dynamic>> rows, {
    required String workshopName,
    String? logoPath,
  }) async {
    await ensureFontsLoaded();

    final doc = await createDocument();

    // تجهيز صفوف الجدول
    final List<List<String>> tableRows = rows.map((r) {
      return [
        r['name']?.toString() ?? '',
        fmt(r['total'] ?? 0),
        fmt(r['paid'] ?? 0),
        fmt(r['remain'] ?? 0),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          // --------------------------------------------------------------
          // الترويسة
          // --------------------------------------------------------------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    workshopName,
                    style: pw.TextStyle(
                      font: _fonts.bold,
                      fontSize: 18,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    "كشف ذمم العملاء",
                    style: pw.TextStyle(fontSize: 14),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
              ),
              if (logoPath != null &&
                  logoPath.trim().isNotEmpty &&
                  File(logoPath).existsSync())
                pw.Container(
                  width: 60,
                  height: 60,
                  child: pw.Image(
                    pw.MemoryImage(File(logoPath).readAsBytesSync()),
                  ),
                ),
            ],
          ),

          pw.SizedBox(height: 25),

          // --------------------------------------------------------------
          // جدول البيانات
          // --------------------------------------------------------------
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .7),
            children: [
              headerRow(["العميل", "الإجمالي", "المدفوع", "المتبقي"]),
              ...tableRows.map(
                (r) => pw.TableRow(
                  children: [
                    cell(r[0]),
                    cell(r[1]),
                    cell(r[2]),
                    cell(r[3]),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // --------------------------------------------------------------
          // تاريخ التقرير
          // --------------------------------------------------------------
          pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                "تاريخ التقرير: ${latinNumbers(DateFormat('yyyy-MM-dd').format(DateTime.now()))}",
                style: pw.TextStyle(
                  font: _fonts.fallbacks.first, // Tahoma
                  fontFallback: _fonts.fallbacks,
                ),
              )),
        ],
      ),
    );

    // حفظ
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/accounts_receivable.pdf");
    await file.writeAsBytes(await doc.save());
    await OpenFile.open(file.path);
  }

// -----------------------------------------------------------------------------
// PDF — تقرير ذمم الموردين (نسخة منقّحة 100% بدون مربعات)
// -----------------------------------------------------------------------------
  static Future<void> generateSupplierPayablesPdf(
      List<Map<String, dynamic>> rows) async {
    await ensureFontsLoaded();

    final settings = await WorkshopSettingsService.instance.getOrDefaults();
    final doc = await createDocument();
    final header = await buildHeader();
    final footer = await buildFooter();

    final tableRows = rows.map<List<String>>((r) {
      return [
        r['name']?.toString() ?? '',
        fmt(r['total'] ?? 0),
        fmt(r['paid'] ?? 0),
        fmt(r['remain'] ?? 0),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(20),
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: _fonts.base,
          bold: _fonts.bold,
        ),
        build: (context) => [
          // --------------------------------------------------------------
          // HEADER — مع معالجة الخطوط
          // --------------------------------------------------------------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    settings.workshopName ?? "ورشة غير محددة",
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: _fonts.bold,
                      fontSize: 18,
                      fontFallback: _fonts.fallbacks,
                    ),
                  ),
                  if (settings.address != null)
                    pw.Text(
                      settings.address!,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        font: _fonts.base,
                        fontSize: 12,
                        fontFallback: _fonts.fallbacks,
                      ),
                    ),
                  pw.Text(
                    "الهاتف: ${settings.phone1 ?? ''}${settings.phone2 != null ? " / ${settings.phone2}" : ""}",
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: _fonts.base,
                      fontSize: 12,
                      fontFallback: _fonts.fallbacks,
                    ),
                  ),
                ],
              ),
              if (settings.logoPath != null &&
                  settings.logoPath!.trim().isNotEmpty &&
                  File(settings.logoPath!).existsSync())
                pw.Container(
                  width: 60,
                  height: 60,
                  child: pw.Image(
                    pw.MemoryImage(File(settings.logoPath!).readAsBytesSync()),
                    fit: pw.BoxFit.contain,
                  ),
                ),
            ],
          ),

          pw.SizedBox(height: 25),

          pw.Center(
            child: pw.Text(
              "تقرير ذمم الموردين",
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: _fonts.bold,
                fontSize: 20,
                fontFallback: _fonts.fallbacks,
              ),
            ),
          ),

          pw.SizedBox(height: 25),

          // --------------------------------------------------------------
          // جدول البيانات — Arabic 100%
          // --------------------------------------------------------------
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .7),
            children: [
              headerRow(["المورد", "الإجمالي", "المدفوع", "المتبقي"]),
              ...tableRows.map(
                (r) => pw.TableRow(
                  children: [
                    cell(r[0]),
                    cell(r[1]),
                    cell(r[2]),
                    cell(r[3]),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // --------------------------------------------------------------
          // FOOTER — إصلاح المربعات بالكامل
          // --------------------------------------------------------------
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              "تاريخ التقرير: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}",
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: _fonts.base,
                fontSize: 10,
                fontFallback: _fonts.fallbacks,
              ),
            ),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/supplier_payables.pdf");
    await file.writeAsBytes(await doc.save());
    await OpenFile.open(file.path);
  }

// -----------------------------------------------------------------------------
// PDF — سند صرف (Payment Voucher) بدون لوجو – نسخة مستقرة 100%
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// PDF — سند صرف احترافي مع جدول وتنسيق RTL كامل
// -----------------------------------------------------------------------------
  static Future<Uint8List> generatePaymentVoucherPdf({
    required String voucherId,
    required DateTime date,
    required double amount,
    required String method,
    required String partyName,
    required String notes,
    required int? glEntryId,
  }) async {
    await ensureFontsLoaded();

    final doc = await createDocument();
    final header = await buildHeader();
    final footer = await buildFooter();

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        header: (ctx) => header,
        footer: (ctx) => footer,
        build: (ctx) => [
          // ----------------------------------------------------------
          // العنوان الرئيسي
          // ----------------------------------------------------------
          pw.Center(
            child: pw.Text(
              "سند صرف",
              style: pw.TextStyle(
                font: _fonts.bold,
                fontSize: 26,
              ),
            ),
          ),
          pw.SizedBox(height: 25),

          // ----------------------------------------------------------
          // جدول معلومات السند
          // ----------------------------------------------------------
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: .9),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(7),
            },
            children: [
              _pdfTableRow("رقم السند", voucherId),
              _pdfTableRow("التاريخ", _pdfFormat(date)),
              _pdfTableRow("الطرف", partyName),
              _pdfTableRow("طريقة الدفع", method.toUpperCase()),
              _pdfTableRow("قيمة السند", "${MoneyFormatter.format(amount)}"),
              _pdfTableRow("رقم القيد المحاسبي", glEntryId?.toString() ?? "-"),
            ],
          ),

          pw.SizedBox(height: 25),

          // ----------------------------------------------------------
          // الملاحظات
          // ----------------------------------------------------------
          if (notes.trim().isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  "ملاحظات:",
                  style: pw.TextStyle(
                    font: _fonts.bold,
                    fontSize: 14,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.grey600),
                  ),
                  child: pw.Text(
                    notes,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),

          pw.SizedBox(height: 40),

          // ----------------------------------------------------------
          // التواقيع
          // ----------------------------------------------------------
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [
                pw.Text("المحاسب", style: pw.TextStyle(font: _fonts.bold)),
                pw.SizedBox(height: 30),
                pw.Container(width: 120, height: 1, color: PdfColors.black),
              ]),
              pw.Column(children: [
                pw.Text("المدير", style: pw.TextStyle(font: _fonts.bold)),
                pw.SizedBox(height: 30),
                pw.Container(width: 120, height: 1, color: PdfColors.black),
              ]),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

// -----------------------------------------------------------------------------
// صف جدول جاهز
// -----------------------------------------------------------------------------
  static pw.TableRow _pdfTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            label,
            style: pw.TextStyle(font: _fonts.bold, fontSize: 13),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            value,
            style: pw.TextStyle(font: _fonts.base, fontSize: 12),
            textDirection: RegExp(r'^[\x00-\x7F]+$').hasMatch(value)
                ? pw.TextDirection.ltr
                : pw.TextDirection.rtl,
          ),
        ),
      ],
    );
  }

// -----------------------------------------------------------------------------
// عناصر مساعدة لسند الصرف
// -----------------------------------------------------------------------------
  static pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              value,
              textDirection: pw.TextDirection.ltr,
              style: pw.TextStyle(font: _fonts.base, fontSize: 13),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _fonts.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  static String _pdfFormat(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  // -----------------------------------------------------------------------------
// PDF — كشف دوام شهري للموظفين (Attendance Report)
// -----------------------------------------------------------------------------
  static Future<void> generateMonthlyAttendancePdf({
    required String employeeName,
    required DateTime month,
    required List<Map<String, String>> rows,
    required double totalHours,
    required double totalDays,
    required double totalSalary,
  }) async {
    await ensureFontsLoaded();

    final doc = await createDocument();
    final header = await buildHeader();
    final footer = await buildFooter();

    final monthTitle = DateFormat('MMMM yyyy', 'ar').format(month);

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (ctx) => header,
        footer: (ctx) => footer,
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              'كشف دوام شهري',
              style: pw.TextStyle(font: _fonts.bold, fontSize: 22),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              '$employeeName — $monthTitle',
              style: pw.TextStyle(fontSize: 14),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey700),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'ملخص الدوام الشهري',
                  style: pw.TextStyle(font: _fonts.bold, fontSize: 14),
                ),
                pw.SizedBox(height: 8),
                pw.Text('إجمالي الساعات: ${fmt(totalHours)} ساعة'),
                pw.Text('إجمالي الأيام المدفوعة: ${fmt(totalDays)} يوم'),
                pw.SizedBox(height: 6),
                pw.Text(
                  'الراتب المستحق: ${MoneyFormatter.format(totalSalary)}',
                  style: pw.TextStyle(font: _fonts.bold),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .7),
            children: [
              headerRow([
                'التاريخ',
                'الدخول',
                'الخروج',
                'الساعات',
                'الحالة',
              ]),
              ...rows.map(
                (r) => pw.TableRow(
                  children: [
                    cell(r['date'] ?? ''),
                    cell(r['in'] ?? '-'),
                    cell(r['out'] ?? '-'),
                    cell(r['hours'] ?? '-'),
                    cell(r['status'] ?? ''),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();

    final fileName =
        'attendance_${employeeName}_${month.year}_${month.month}.pdf';

    await saveAndOpen(bytes: bytes, fileName: fileName);
  }

  static Future<void> generateClientDetailsPdf({
    required String clientName,
    required String clientType,
    required double total,
    required double paid,
    required double remain,
    required List repairs,
    required String workshopName,
    String? logoPath,
  }) async {
    print('PDF CLICKED FOR $clientName');
  }

  static Future<void> generateClientArDetailsPdf({
    required String clientName,
    required String clientType,
    required double total,
    required double paid,
    required double remain,
    required List<Map<String, dynamic>> rows,
    required String workshopName,
    String? logoPath,
  }) async {
    await ensureFontsLoaded();

    final doc = await createDocument();

    String money(num v) => NumberFormat('#,##0.00', 'ar').format(v);

    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(
          base: _fonts.base,
          bold: _fonts.bold,
        ),
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'كشف ذمم عميل',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('العميل: $clientName'),
          pw.Text('النوع: $clientType'),
          pw.SizedBox(height: 10),

          // ملخص
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ملخص',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('إجمالي: ${money(total)}'),
                pw.Text('مدفوع: ${money(paid)}'),
                pw.Text('متبقي: ${money(remain)}'),
              ],
            ),
          ),

          pw.SizedBox(height: 12),

          // الجدول
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: .7),
            children: [
              headerRow([
                'الملف / المركبة',
                'تاريخ الاستلام',
                'الإجمالي',
                'المدفوع',
                'المتبقي',
              ]),
              ...rows.map(
                (r) => pw.TableRow(
                  children: [
                    cell(r['label'] ?? ''),
                    cell(r['received'] ?? ''),
                    cell(fmt(r['total'] ?? 0)),
                    cell(fmt(r['paid'] ?? 0)),
                    cell(fmt(r['remain'] ?? 0)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();

    await saveAndOpen(
      bytes: bytes,
      fileName: 'client_ar_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static String latinNumbers(String input) {
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const latin = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    for (int i = 0; i < arabic.length; i++) {
      input = input.replaceAll(arabic[i], latin[i]);
    }
    return input;
  }

  // ---------------------------------------------------------------------------
  // تنسيق أرقام آمن للـ PDF (بدون مربعات)
  // ---------------------------------------------------------------------------
  static String fmt(num v) {
    return normalizePdfText(
      NumberFormat("#,##0.00", "en").format(v),
    );
  }

  static Future<void> exportGeneralLedgerPdf({
    required String accountName,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> rows,
  }) async {
    await ensureFontsLoaded();

    final pdf = await createDocument();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(
          base: _fonts.base,
          bold: _fonts.bold,
        ),
        build: (context) => [
          pw.Text(
            'دفتر الأستاذ العام',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'الحساب: $accountName',
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text(
            'الفترة: ${DateFormat('yyyy-MM-dd').format(from)} → ${DateFormat('yyyy-MM-dd').format(to)}',
            textDirection: pw.TextDirection.rtl,
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: .5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(5),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _th('التاريخ'),
                  _th('الوصف'),
                  _th('مدين'),
                  _th('دائن'),
                  _th('الرصيد'),
                ],
              ),
              ...rows.map((r) => pw.TableRow(
                    children: [
                      _td(r['date']),
                      _td(r['description']),
                      _td(r['debit']),
                      _td(r['credit']),
                      _td(r['balance']),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/general_ledger.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);
  }

  static pw.Widget _th(String t) {
    final clean = normalizePdfText(t);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        clean,
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          font: _fonts.bold,
          fontSize: 12,
          fontFallback: _fonts.fallbacks,
        ),
      ),
    );
  }

  static pw.Widget _td(dynamic t) {
    final text = normalizePdfText(t?.toString() ?? '');
    final isAscii = RegExp(r'^[\x00-\x7F]+$').hasMatch(text);

    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textDirection: isAscii ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        textAlign: isAscii ? pw.TextAlign.left : pw.TextAlign.right,
        style: pw.TextStyle(
          font: isAscii
              ? _fonts.fallbacks.first // Tahoma للأرقام/EN
              : _fonts.base, // عربي
          fontSize: 11,
          fontFallback: _fonts.fallbacks,
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------------
// PDF — Smart Image Grid (NO EMPTY SPACES EVER)
// -----------------------------------------------------------------------------
  static pw.Widget buildSmartImageGrid(
    List<Uint8List> images, {
    double spacing = 6,
  }) {
    if (images.isEmpty) {
      return pw.SizedBox();
    }

    int columns;
    final count = images.length;

    if (count == 1) {
      columns = 1;
    } else if (count == 2 || count == 4) {
      columns = 2;
    } else {
      columns = 3;
    }

    final rows = <pw.TableRow>[];

    for (int i = 0; i < images.length; i += columns) {
      final rowImages = images.skip(i).take(columns).toList();

      rows.add(
        pw.TableRow(
          children: List.generate(columns, (index) {
            if (index >= rowImages.length) {
              // لا نترك أعمدة فارغة
              return pw.SizedBox();
            }

            return pw.Padding(
              padding: pw.EdgeInsets.all(spacing / 2),
              child: pw.ClipRRect(
                horizontalRadius: 4,
                verticalRadius: 4,
                child: pw.Image(
                  pw.MemoryImage(rowImages[index]),
                  fit: pw.BoxFit.cover,
                ),
              ),
            );
          }),
        ),
      );
    }

    return pw.Table(
      columnWidths: {
        for (int i = 0; i < columns; i++) i: const pw.FlexColumnWidth(),
      },
      children: rows,
    );
  }

  static Future<Uint8List> generatePaymentVoucherListPdf({
    required List<Map<String, Object?>> rows,
    required double totalToday,
    required double totalMonth,
    required DateTime generatedAt,
  }) async {
    final doc = await createDocument();
    final header = await buildHeader();
    final footer = await buildFooter();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => header,
        footer: (ctx) => footer,
        build: (context) => [
          pw.Center(
            child: ar(
              "كشف سندات الصرف",
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          ar("تاريخ الإصدار: ${DateFormat('yyyy-MM-dd HH:mm').format(generatedAt)}"),
          ar("عدد السندات: ${rows.length}"),
          ar("إجمالي اليوم: ${MoneyFormatter.format(totalToday)}"),
          ar("إجمالي الشهر: ${MoneyFormatter.format(totalMonth)}"),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(4),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(3),
              5: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  cell("ID", header: true),
                  cell("التاريخ", header: true),
                  cell("الطرف", header: true),
                  cell("النوع", header: true),
                  cell("المبلغ", header: true),
                  cell("الطريقة", header: true),
                ],
              ),
              ...rows.map((row) => pw.TableRow(
                    children: [
                      cell(row["voucher_number"]?.toString() ?? ""),
                      cell(row["date"].toString().substring(0, 10)),
                      cell(row["party_name"]?.toString() ?? ""),
                      cell(
                        row["source"] == "EMP_ADV"
                            ? "سلفة"
                            : row["party_name"] == "مصاريف تشغيلية"
                                ? "مصروف"
                                : "دفع",
                      ),
                      cell(fmt(row["amount"] as num)),
                      cell(row["method"].toString().toUpperCase()),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateReceiptVoucherListPdf({
    required List<Map<String, Object?>> rows,
    required double totalToday,
    required double totalMonth,
    required DateTime generatedAt,
  }) async {
    final doc = await createDocument();
    final header = await buildHeader();
    final footer = await buildFooter();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => header,
        footer: (ctx) => footer,
        build: (context) => [
          pw.Center(
            child: ar(
              "كشف سندات القبض",
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          ar("تاريخ الإصدار: ${DateFormat('yyyy-MM-dd HH:mm').format(generatedAt)}"),
          ar("عدد السندات: ${rows.length}"),
          ar("إجمالي اليوم: ${MoneyFormatter.format(totalToday)}"),
          ar("إجمالي الشهر: ${MoneyFormatter.format(totalMonth)}"),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(4),
              3: const pw.FlexColumnWidth(3),
              4: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  cell("ID", header: true),
                  cell("التاريخ", header: true),
                  cell("العميل", header: true),
                  cell("المبلغ", header: true),
                  cell("الطريقة", header: true),
                ],
              ),
              ...rows.map((row) => pw.TableRow(
                    children: [
                      cell(row["id"]?.toString() ?? ""),
                      cell(
                        row["date"] != null
                            ? row["date"].toString().substring(0, 10)
                            : "",
                      ),
                      cell(row["clientName"]?.toString() ?? ""),
                      cell(fmt(row["amount"] as num)),
                      cell(row["method"].toString().toUpperCase()),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }
}

// -----------------------------------------------------------------------------
// FONT HOLDER
// -----------------------------------------------------------------------------
class _FontSet {
  final pw.Font base;
  final pw.Font bold;
  final List<pw.Font> fallbacks;
  _FontSet({required this.base, required this.bold, required this.fallbacks});
}
