// 📁 lib/features/finance/vouchers/pdf/payment_voucher_pdf.dart
//
// توليد PDF احترافي لسند الصرف
// - استخدام خطوط Cairo
// - دعم RTL بالكامل
// - إدراج شعار YALLAH ACCOUNTS
// - تصميم حديث يناسب مستوى التطبيق
// - دالة generate() تُرجع Uint8List جاهز للطباعة أو الحفظ

import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class PaymentVoucherPdf {
  /// توليد PDF لسند صرف
  static Future<Uint8List> generate({
    required String voucherId,
    required DateTime date,
    required String expenseType,
    required double amount,
    required String method,
    required String partyName,
    required String notes,
    required int? glEntryId,
    String? chequeNumber,
    String? chequeBank,
    String? chequeBranch,
    String? chequePayee,
    String? chequeCurrency,
    String? chequeStatus,
    DateTime? chequeIssueDate,
    DateTime? chequeDueDate,
  }) async {
    final pdf = pw.Document();

    // تحميل خط عربي
    final fontData = await rootBundle.load("assets/fonts/Cairo-Regular.ttf");
    final ttf = pw.Font.ttf(fontData);

    final fontBoldData = await rootBundle.load("assets/fonts/Cairo-Bold.ttf");
    final ttfBold = pw.Font.ttf(fontBoldData);

    // تحميل شعار YALLAH ACCOUNTS
    final logoData = await rootBundle
        .load("assets/branding/yallah_mark.png")
        .then((v) => v.buffer.asUint8List());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // ------------------------------ HEADER ------------------------------
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 120,
                          height: 120,
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(
                            color: const PdfColor.fromInt(0xFFDFF5D2),
                            borderRadius: pw.BorderRadius.circular(12),
                          ),
                          child: pw.Image(pw.MemoryImage(logoData)),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("YALLAH ACCOUNTS",
                            style: pw.TextStyle(font: ttfBold, fontSize: 18)),
                        pw.SizedBox(height: 4),
                        pw.Text("سند صرف",
                            style: pw.TextStyle(font: ttfBold, fontSize: 26)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),

                // ------------------------------ INFO BOX ------------------------------
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(color: PdfColors.grey, width: 1),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      infoRow("رقم السند:", voucherId, ttf, ttfBold),
                      infoRow("التاريخ:", _format(date), ttf, ttfBold),
                      infoRow("نوع المصروف:", expenseType, ttf, ttfBold),
                      infoRow(
                        "طريقة الدفع:",
                        _methodLabel(method),
                        ttf,
                        ttfBold,
                      ),
                      infoRow("الطرف:", partyName, ttf, ttfBold),
                      infoRow("قيمة السند:", MoneyFormatter.format(amount), ttf,
                          ttfBold),
                      infoRow("رقم القيد المحاسبي (GL):",
                          glEntryId?.toString() ?? "—", ttf, ttfBold),
                      if (_isCheque(method) &&
                          (chequeNumber ?? '').trim().isNotEmpty) ...[
                        pw.Divider(),
                        pw.Text(
                          "بيانات الشيك",
                          style: pw.TextStyle(font: ttfBold, fontSize: 15),
                        ),
                        infoRow(
                            "رقم الشيك:", chequeNumber ?? "—", ttf, ttfBold),
                        infoRow(
                          "البنك:",
                          [
                            chequeBank,
                            chequeBranch,
                          ]
                              .whereType<String>()
                              .where((v) => v.trim().isNotEmpty)
                              .join(" — "),
                          ttf,
                          ttfBold,
                        ),
                        infoRow("المستفيد:", chequePayee ?? partyName, ttf,
                            ttfBold),
                        infoRow(
                          "العملة:",
                          (chequeCurrency ?? '').trim().isEmpty
                              ? "ILS"
                              : chequeCurrency!,
                          ttf,
                          ttfBold,
                        ),
                        infoRow(
                          "تاريخ الإصدار:",
                          chequeIssueDate == null
                              ? "—"
                              : _format(chequeIssueDate),
                          ttf,
                          ttfBold,
                        ),
                        infoRow(
                          "تاريخ الاستحقاق:",
                          chequeDueDate == null ? "—" : _format(chequeDueDate),
                          ttf,
                          ttfBold,
                        ),
                        infoRow("الحالة:", chequeStatus ?? "—", ttf, ttfBold),
                      ],
                    ],
                  ),
                ),

                pw.SizedBox(height: 20),

                // ------------------------------ NOTES ------------------------------
                if (notes.trim().isNotEmpty)
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(12),
                      border: pw.Border.all(color: PdfColors.grey500, width: 1),
                      color: PdfColors.grey200,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("ملاحظات",
                            style: pw.TextStyle(font: ttfBold, fontSize: 16)),
                        pw.SizedBox(height: 8),
                        pw.Text(notes,
                            style: pw.TextStyle(font: ttf, fontSize: 14)),
                      ],
                    ),
                  ),

                pw.Spacer(),

                // ------------------------------ FOOTER ------------------------------
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Column(
                    children: [
                      pw.Divider(),
                      pw.Text(
                        "تم إنشاء السند بواسطة نظام YALLAH ACCOUNTS",
                        style: pw.TextStyle(
                            font: ttf, fontSize: 12, color: PdfColors.grey600),
                      ),
                      pw.Text(
                        "www.yalla.ps",
                        style: pw.TextStyle(
                            font: ttfBold, fontSize: 12, color: PdfColors.blue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // قالب جاهز لصف واحد من البيانات
  static pw.Widget infoRow(
      String label, String value, pw.Font ttf, pw.Font ttfBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.left,
              style: pw.TextStyle(font: ttf, fontSize: 14),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Text(label, style: pw.TextStyle(font: ttfBold, fontSize: 14)),
        ],
      ),
    );
  }

  static bool _isCheque(String method) {
    final value = method.trim().toLowerCase();
    return value == 'cheque' || value == 'check' || value.contains('شيك');
  }

  static String _methodLabel(String method) {
    final value = method.trim().toLowerCase();
    if (value == 'cash') return 'نقدي';
    if (_isCheque(value)) return 'شيك';
    if (value == 'bank' || value == 'transfer' || value == 'bank_transfer') {
      return 'تحويل بنكي';
    }
    return method;
  }

  static String _format(DateTime d) {
    return "${d.year}-${_two(d.month)}-${_two(d.day)}";
  }

  static String _two(int v) => v < 10 ? "0$v" : "$v";
}
