// 📁 lib/features/finance/vouchers/pdf/receipt_voucher_pdf.dart
//
// ReceiptVoucherPDF — Final Version (Direct Save, No Dialog)
// --------------------------------------------------------------
// - حفظ PDF مباشرة في Documents/YallaAccounts/receipts
// - دعم شعار الورشة WorkshopSettings
// - خطوط عربية Cairo
// - تصميم RTL احترافي
// - إرجاع مسار الملف بعد الإنشاء
// --------------------------------------------------------------

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import '../../settings/services/workshop_settings_service.dart';
import '../../settings/models/workshop_settings.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class ReceiptVoucherPDF {
  /// ينشئ PDF ويحفظه مباشرة ويعيد مسار الملف
  static Future<String> generate({
    required String paymentId,
    required double amount,
    required String date,
    required String clientName,
    required String method,
    String? notes,
  }) async {
    // ----------------------------------------------------------
    // تحميل إعدادات الورشة
    // ----------------------------------------------------------
    final WorkshopSettings settings =
        (await WorkshopSettingsService.instance.getSettings()) ??
            WorkshopSettings.defaults();

    Uint8List? logoBytes;
    if (settings.logoPath != null &&
        settings.logoPath!.trim().isNotEmpty &&
        File(settings.logoPath!).existsSync()) {
      logoBytes = await File(settings.logoPath!).readAsBytes();
    }

    // ----------------------------------------------------------
    // تحميل الخطوط العربية
    // ----------------------------------------------------------
    final fontReg =
        pw.Font.ttf(await rootBundle.load("assets/fonts/Cairo-Regular.ttf"));
    final fontBold =
        pw.Font.ttf(await rootBundle.load("assets/fonts/Cairo-Bold.ttf"));

    final pdf = pw.Document();

    // ----------------------------------------------------------
    // التاريخ بصيغة جميلة
    // ----------------------------------------------------------
    final formattedDate = _formatDate(date);

    // ----------------------------------------------------------
    // بناء الصفحة
    // ----------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ------------------------------------------------------
                // الرأس + شعار الورشة
                // ------------------------------------------------------
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          settings.workshopName ?? "اسم الورشة غير محدد",
                          style: pw.TextStyle(font: fontBold, fontSize: 20),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          "سند قبض",
                          style: pw.TextStyle(font: fontReg, fontSize: 16),
                        ),
                      ],
                    ),
                    if (logoBytes != null)
                      pw.Container(
                        height: 60,
                        width: 60,
                        child: pw.Image(pw.MemoryImage(logoBytes),
                            fit: pw.BoxFit.contain),
                      ),
                  ],
                ),

                pw.SizedBox(height: 20),

                // ------------------------------------------------------
                // معلومات السند
                // ------------------------------------------------------
                _info("رقم السند:", paymentId, fontReg, fontBold),
                _info("التاريخ:", formattedDate, fontReg, fontBold),
                _info("العميل:", clientName, fontReg, fontBold),
                _info("طريقة الدفع:", _arabicMethod(method), fontReg, fontBold),
                _info("المبلغ:", "${MoneyFormatter.format(amount)}", fontReg,
                    fontBold),

                pw.SizedBox(height: 16),

                // ------------------------------------------------------
                // الملاحظات
                // ------------------------------------------------------
                if (notes != null && notes.trim().isNotEmpty) ...[
                  pw.Text("الملاحظات:",
                      style: pw.TextStyle(font: fontBold, fontSize: 14)),
                  pw.SizedBox(height: 4),
                  pw.Text(notes,
                      style: pw.TextStyle(font: fontReg, fontSize: 12)),
                  pw.SizedBox(height: 12),
                ],

                pw.Divider(),

                pw.SizedBox(height: 24),

                // ------------------------------------------------------
                // التوقيعات
                // ------------------------------------------------------
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _signatureBox("توقيع المستلم", fontReg),
                    _signatureBox("توقيع المحاسب", fontReg),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    // ----------------------------------------------------------
    // حفظ الملف مباشرة بدون طباعة
    // ----------------------------------------------------------
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, "YallaAccounts", "receipts"));

    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    final filePath = p.join(folder.path, "Receipt_$paymentId.pdf");

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return filePath;
  }

  // ----------------------------------------------------------
  // Widgets داخل PDF
  // ----------------------------------------------------------

  static pw.Widget _info(
      String label, String value, pw.Font font, pw.Font bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 14)),
          pw.SizedBox(width: 6),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 14)),
        ],
      ),
    );
  }

  static pw.Widget _signatureBox(String text, pw.Font font) {
    return pw.Column(
      children: [
        pw.Text(text, style: pw.TextStyle(font: font, fontSize: 13)),
        pw.SizedBox(height: 40),
        pw.Container(width: 120, height: 1, color: PdfColors.grey),
      ],
    );
  }

  static String _arabicMethod(String m) {
    final x = m.toLowerCase();
    if (x == "cash") return "نقدًا";
    if (x == "bank" || x == "bank_transfer" || x == "transfer")
      return "تحويل بنكي";
    if (x == "card" || x == "credit") return "بطاقة";
    if (x == "cheque") return "شيك";
    return m;
  }

  static String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return DateFormat("yyyy-MM-dd").format(d);
    } catch (_) {
      return iso;
    }
  }
}
