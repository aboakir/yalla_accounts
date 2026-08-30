// 📁 lib/features/repairs/services/repair_pdf_generator.dart
//
// النسخة الجديدة — مرتبطة مباشرة بإعدادات الورشة (WorkshopSettings)
// ---------------------------------------------------------------
// • الترويسة تسحب (الشعار – الاسم التجاري – المدينة – العنوان – الهاتف – البريد)
// • إزالة كل النصوص الثابتة
// • تحميل الشعار الحقيقي من المسار logoPath
// • دعم RTL كامل
// • تحسين تصميم العناوين والجداول
// ---------------------------------------------------------------

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class RepairPdfGenerator {
  static late _FontSet _gFonts;

  // =====================================================================
  // GENERATE PDF
  // =====================================================================
  static Future<Uint8List> generate(Repair repair) async {
    _gFonts = await _loadArabicFontSet();

    final theme = pw.ThemeData.withFont(
      base: _gFonts.base,
      bold: _gFonts.bold,
      italic: _gFonts.base,
    ).copyWith(
      defaultTextStyle: pw.TextStyle(fontFallback: _gFonts.fallbacks),
    );

    final pdf = pw.Document(theme: theme);
    final dateFmt = DateFormat('yyyy-MM-dd');

    // ============================
    // Load Workshop Settings
    // ============================
    final WorkshopSettings ws =
        await WorkshopSettingsService.instance.getOrDefaults();

    final String workshopName = ws.workshopName?.trim().isNotEmpty == true
        ? ws.workshopName!.trim()
        : "ورشة غير محددة";

    final String workshopCity =
        ws.city?.trim().isNotEmpty == true ? ws.city!.trim() : "";

    final String workshopAddress =
        ws.address?.trim().isNotEmpty == true ? ws.address!.trim() : "";

    final String phone1 =
        ws.phone1?.trim().isNotEmpty == true ? ws.phone1!.trim() : "";

    final String phone2 =
        ws.phone2?.trim().isNotEmpty == true ? ws.phone2!.trim() : "";

    final String email =
        ws.email?.trim().isNotEmpty == true ? ws.email!.trim() : "";

    // ============================
    // Workshop logo
    // ============================
    pw.MemoryImage? workshopLogo;
    try {
      if (ws.logoPath != null && ws.logoPath!.isNotEmpty) {
        final file = File(ws.logoPath!);
        if (file.existsSync()) {
          workshopLogo = pw.MemoryImage(file.readAsBytesSync());
        }
      }
    } catch (_) {}

    // ============================
    // Totals
    // ============================
    final partsTotal = _sumList(repair.parts, 'price');
    final worksTotal = _sumList(repair.works, 'price');
    final grandTotal = partsTotal + worksTotal;

    final paid = (repair.paidAmount).toDouble();
    final remaining = grandTotal - paid;
    final isQuote = repair.invoiceId == null || repair.invoiceId!.isEmpty;

    // =====================================================================
    // PAGE 1 — MAIN PAGE
    // =====================================================================
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,

        // ======================
        //  FOOTER ثابت أسفل الصفحة
        // ======================
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            [
              if (workshopCity.isNotEmpty) "المدينة: $workshopCity",
              if (workshopAddress.isNotEmpty) "العنوان: $workshopAddress",
              if (phone1.isNotEmpty) "هاتف: $phone1",
              if (phone2.isNotEmpty) "هاتف إضافي: $phone2",
              if (email.isNotEmpty) "Email: $email",
            ].where((e) => e.trim().isNotEmpty).join(" • "),
            style: pw.TextStyle(fontSize: 10, font: _gFonts.bold),
            textAlign: pw.TextAlign.center,
          ),
        ),

        // ======================
        //   محتوى الصفحة
        // ======================
        build: (context) => [
          _buildHeader(
            workshopName: workshopName,
            workshopCity: workshopCity,
            workshopAddress: workshopAddress,
            phone1: phone1,
            phone2: phone2,
            email: email,
            logo: workshopLogo,
          ),

          pw.SizedBox(height: 10),
          _buildTitle(isQuote),
          pw.SizedBox(height: 10),

          if (repair.beneficiaryName.trim().isNotEmpty)
            pw.Align(
              alignment: pw.Alignment.center,
              child: _ar(
                "السادة: ${_beneficiaryText(repair.beneficiaryType)} - ${repair.beneficiaryName} المحترمين",
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),

          pw.SizedBox(height: 12),
          _buildVehicleInfo(repair, dateFmt),
          pw.SizedBox(height: 12),
          _buildStatusBar(repair, isQuote, paid, remaining),
          pw.SizedBox(height: 12),

          _ar(
            "أعمال الإصلاح",
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _buildPagedTable(repair.works),

          pw.SizedBox(height: 14),

          _ar(
            "القطع المطلوبة",
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _buildPagedTable(repair.parts),

          pw.SizedBox(height: 12),
          _buildTotalsSummary(partsTotal, worksTotal, grandTotal),

          if ((repair.notes ?? '').isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _ar("ملاحظات: ${repair.notes ?? ''}"),
          ],

          pw.SizedBox(height: 20),
          // لا تضع Footer هنا
        ],
      ),
    );
// =====================================================================
// IMAGES — SAFE PAGED GRID (NO MultiPage / NO Wrap / NO Freeze)
// =====================================================================

    final imageBytes = repair.imagePaths
        .where((p) => p.isNotEmpty && File(p).existsSync())
        .map((p) => File(p).readAsBytesSync())
        .toList();

    const imagesPerPage = 6; // شبكة ثابتة 2 × 3

    for (int i = 0; i < imageBytes.length; i += imagesPerPage) {
      final pageImages = imageBytes.skip(i).take(imagesPerPage).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          textDirection: pw.TextDirection.rtl,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _ar(
                  "صور المركبة",
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),

                // شبكة يدوية ثابتة (بدون GridView)
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(),
                    1: pw.FlexColumnWidth(),
                  },
                  children: List.generate(
                    (pageImages.length / 2).ceil(),
                    (row) {
                      final leftIndex = row * 2;
                      final rightIndex = leftIndex + 1;

                      return pw.TableRow(
                        children: [
                          _imageCell(pageImages, leftIndex),
                          _imageCell(pageImages, rightIndex),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  // =====================================================================
  // SAVE FILE
  // =====================================================================
  static Future<File> saveToFile(Repair repair) async {
    final bytes = await generate(repair);

    Directory? dir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
    }
    dir ??= await getApplicationDocumentsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);

    final cleanType = _cleanFs(repair.vehicleType);
    final cleanName = _cleanFs(repair.beneficiaryName);
    final cleanNumber = _cleanFs(repair.vehicleNumber);
    final date = DateFormat('yyyy-MM-dd').format(repair.receivedDate);

    final prefix = (repair.invoiceId == null || repair.invoiceId!.isEmpty)
        ? "QUOTE"
        : "INVOICE";

    final fileName = "$prefix-$cleanType-$cleanName-$cleanNumber-$date.pdf";

    final path = p.join(dir.path, fileName);
    final file = File(path);

    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<File> saveToFileAndOpen(Repair repair) async {
    final file = await saveToFile(repair);
    await OpenFile.open(file.path);
    return file;
  }

  // =====================================================================
  // HEADER
  // =====================================================================
  static pw.Widget _buildHeader({
    required String workshopName,
    required String workshopCity,
    required String workshopAddress,
    required String phone1,
    required String phone2,
    required String email,
    required pw.MemoryImage? logo,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null)
            pw.Container(
              width: 70,
              height: 70,
              margin: const pw.EdgeInsets.only(left: 12),
              child: pw.Image(logo),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _ar(
                  workshopName, // ← سيظهر: لؤي أبو عكر (صحيح 100%)
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (workshopCity.isNotEmpty)
                  _ar("المدينة: $workshopCity",
                      style: const pw.TextStyle(fontSize: 10)),
                if (workshopAddress.isNotEmpty)
                  _ar("العنوان: $workshopAddress",
                      style: const pw.TextStyle(fontSize: 10)),
                if (phone1.isNotEmpty)
                  _ar("هاتف: $phone1", style: const pw.TextStyle(fontSize: 10)),
                if (phone2.isNotEmpty)
                  _ar("هاتف إضافي: $phone2",
                      style: const pw.TextStyle(fontSize: 10)),
                if (email.isNotEmpty)
                  _ar("Email: $email", style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // TITLE BAR
  // =====================================================================
  static pw.Widget _buildTitle(bool isQuote) {
    return pw.Align(
      alignment: pw.Alignment.center,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: pw.BoxDecoration(
          color: isQuote ? PdfColors.amber200 : PdfColors.grey200,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(
            color: isQuote ? PdfColors.amber700 : PdfColors.grey600,
            width: .8,
          ),
        ),
        child: _ar(
          isQuote ? "عرض سعر لإصلاح مركبة" : "فاتورة إصلاح",
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // VEHICLE INFO TABLE
  // =====================================================================
  static pw.Widget _buildVehicleInfo(Repair repair, DateFormat df) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: .8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Table(
        border: pw.TableBorder.symmetric(
          inside: pw.BorderSide(color: PdfColors.grey500, width: .6),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4),
          1: pw.FlexColumnWidth(1.4),
          2: pw.FlexColumnWidth(1.4),
          3: pw.FlexColumnWidth(1.4),
        },
        children: [
          _headerRow(["نوع المركبة", "موديل", "رقم المركبة", "تاريخ الاستلام"]),
          pw.TableRow(
            children: [
              _cell(repair.vehicleType, arabic: true),
              _cell(repair.vehicleModel, arabic: true),
              _cell(repair.vehicleNumber, arabic: true),
              _cellWidget(_ltrText(df.format(repair.receivedDate))),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // STATUS BAR
  // =====================================================================
  static pw.Widget _buildStatusBar(
      Repair repair, bool isQuote, double paid, double remaining) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Wrap(
          spacing: 8,
          children: [
            if (_isInsurance(repair.beneficiaryType) &&
                (repair.insuranceFollowUpStatus ?? '').isNotEmpty)
              _chip(
                _ar("متابعة التأمين: ${repair.insuranceFollowUpStatus!}"),
              ),
            if (isQuote)
              _chip(
                _ar("عرض سعر",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
          ],
        ),
        pw.Wrap(
          spacing: 8,
          children: [
            _chip(_ar("الحالة: ${repair.paymentStatus}")),
            _chip(pw.Row(children: [_ar("مدفوع:"), _ltrText(_fmt(paid))])),
            _chip(
              pw.Row(
                children: [
                  _ar("المتبقي:"),
                  _ltrText(_fmt(remaining < 0 ? 0 : remaining)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =====================================================================
  // TOTAL SUMMARY
  // =====================================================================
  static pw.Widget _buildTotalsSummary(
      double parts, double works, double total) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Wrap(
        spacing: 10,
        children: [
          _chip(
              pw.Row(children: [_ar("مجموع الأجور:"), _ltrText(_fmt(works))])),
          _chip(pw.Row(children: [_ar("مجموع القطع:"), _ltrText(_fmt(parts))])),
          _chip(
            pw.Row(children: [
              _ar("الإجمالي:"),
              _ltrText(_fmt(total)),
              _ar(" ${MoneyFormatter.symbol}"),
            ]),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // FOOTER
  // =====================================================================
  static pw.Widget _buildFooter({
    required String workshopCity,
    required String workshopAddress,
    required String phone1,
    required String phone2,
    required String email,
  }) {
    final text = [
      if (workshopCity.isNotEmpty) "المدينة: $workshopCity",
      if (workshopAddress.isNotEmpty) "العنوان: $workshopAddress",
      if (phone1.isNotEmpty) "هاتف: $phone1",
      if (phone2.isNotEmpty) "هاتف إضافي: $phone2",
      if (email.isNotEmpty) "Email: $email",
    ].join(" • ");

    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: _ar(
        text,
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  }

  // =====================================================================
  // TABLE HELPERS
  // =====================================================================
  static pw.TableRow _headerRow(List<String> titles) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children:
          titles.map((t) => _cell(t, header: true, arabic: true)).toList(),
    );
  }

  static pw.Widget _cell(
    String text, {
    bool header = false,
    bool arabic = false,
    pw.Alignment? align,
  }) {
    final style = header
        ? pw.TextStyle(
            font: _gFonts.bold,
            fontWeight: pw.FontWeight.bold,
            fontSize: 11,
          )
        : (arabic
            ? pw.TextStyle(font: _gFonts.bold, fontSize: 11)
            : const pw.TextStyle(fontSize: 11));

    final content = arabic
        ? _ar(text, style: style)
        : pw.Text(text, style: style, textAlign: pw.TextAlign.right);

    return pw.Container(
      alignment: align ?? pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: content,
    );
  }

  static pw.Widget _cellWidget(pw.Widget child, {pw.Alignment? align}) {
    return pw.Container(
      alignment: align ?? pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: child,
    );
  }

  static pw.Widget _labeledTable(
      String title, List<Map<String, dynamic>>? items) {
    final rows = items ?? [];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _ar(
          title,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 13,
          ),
        ),
        pw.SizedBox(height: 6),
        if (rows.isEmpty)
          _ar("لا يوجد بيانات")
        else
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey600, width: .8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Table(
              border: pw.TableBorder.symmetric(
                inside: pw.BorderSide(color: PdfColors.grey500, width: .6),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.2),
              },
              children: [
                _headerRow(["الوصف", "الكمية", "السعر"]),
                ...rows.map(
                  (row) {
                    final name = "${row['name'] ?? ''}";
                    final qty =
                        ((row['qty'] as num?)?.toDouble() ?? 1).toString();
                    final price =
                        _fmt(((row['price'] as num?)?.toDouble() ?? 0.0));

                    return pw.TableRow(
                      children: [
                        _cell(name, arabic: true),
                        _cellWidget(_ltrText(qty), align: pw.Alignment.center),
                        _cellWidget(_ltrText(price),
                            align: pw.Alignment.centerLeft),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _chip(pw.Widget child) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
      ),
      child: child,
    );
  }

  static pw.Widget _buildPagedTable(List<Map<String, dynamic>>? items) {
    final rows = items ?? [];

    if (rows.isEmpty) {
      return _ar("لا يوجد بيانات");
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _cell("الوصف", header: true, arabic: true),
            _cell("الكمية", header: true, arabic: true),
            _cell("السعر", header: true, arabic: true),
          ],
        ),
        ...rows.map((row) {
          final name = "${row['name'] ?? ''}";
          final qty = ((row['qty'] as num?)?.toDouble() ?? 1).toString();
          final price = _fmt(((row['price'] as num?)?.toDouble() ?? 0.0));

          return pw.TableRow(
            children: [
              _cell(name, arabic: true),
              _cellWidget(_ltrText(qty), align: pw.Alignment.center),
              _cellWidget(
                _ltrText(price),
                align: pw.Alignment.centerLeft,
              ),
            ],
          );
        }),
      ],
    );
  }

  // =====================================================================
  // Utils
  // =====================================================================
  static bool _isInsurance(String t) {
    final v = t.trim();
    return v == "INSURANCE" || v == "شركة تأمين";
  }

  static String _beneficiaryText(String t) =>
      _isInsurance(t) ? "شركة تأمين" : "أفراد";

  static double _sumList(List<Map<String, dynamic>>? list, String key) {
    return (list ?? [])
        .map((e) => (e[key] as num?)?.toDouble() ?? 0.0)
        .fold(0.0, (a, b) => a + b);
  }

  static final NumberFormat _numFmt = NumberFormat("#,##0.00", "ar");

  static String _fmt(double v) => _numFmt.format(v);

  static String _cleanFs(String input) {
    final cleaned =
        input.replaceAll(RegExp(r"[^\u0600-\u06FF\w\s\-\._]+"), "_").trim();
    return cleaned.replaceAll(RegExp(r"[_\s\-]{2,}"), "_");
  }

  // Arabic text
  static pw.Widget _ar(String text, {pw.TextStyle? style}) {
    return pw.Text(
      text,
      textAlign: pw.TextAlign.right,
      style: (style ?? const pw.TextStyle()).copyWith(font: _gFonts.bold),
    );
  }

  // LTR text
  static pw.Widget _ltrText(String text, {pw.TextStyle? style}) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Text(text, style: style),
    );
  }

  // Load fonts
  static Future<_FontSet> _loadArabicFontSet() async {
    pw.Font? base;
    pw.Font? bold;

    try {
      base =
          pw.Font.ttf(await rootBundle.load("assets/fonts/Cairo-Regular.ttf"));
      bold = pw.Font.ttf(await rootBundle.load("assets/fonts/Cairo-Bold.ttf"));
    } catch (_) {
      try {
        base = pw.Font.ttf(
            await rootBundle.load("assets/fonts/NotoNaskhArabic-Regular.ttf"));
      } catch (_) {}
      try {
        bold = pw.Font.ttf(
            await rootBundle.load("assets/fonts/NotoNaskhArabic-Bold.ttf"));
      } catch (_) {}
    }
    base ??= pw.Font.helvetica();
    bold ??= base;

    final fallbacks = <pw.Font>[];
    for (final path in const [
      "assets/fonts/NotoNaskhArabic-Regular.ttf",
      "assets/fonts/Tahoma-Regular.ttf",
      "assets/fonts/TraditionalArabic-Regular.ttf",
      "assets/fonts/NotoSansArabic-Regular.ttf",
    ]) {
      try {
        fallbacks.add(pw.Font.ttf(await rootBundle.load(path)));
      } catch (_) {}
    }

    return _FontSet(base: base, bold: bold, fallbacks: fallbacks);
  }

  static pw.Widget _imageCell(List<Uint8List> images, int index) {
    if (index >= images.length) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Container(
        height: 180,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600, width: 0.8),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 4,
          verticalRadius: 4,
          child: pw.Image(
            pw.MemoryImage(images[index]),
            fit: pw.BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _FontSet {
  final pw.Font base;
  final pw.Font bold;
  final List<pw.Font> fallbacks;

  _FontSet({required this.base, required this.bold, required this.fallbacks});
}
