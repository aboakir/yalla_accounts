import 'dart:io';
import 'package:excel/excel.dart' as ex;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_print_service.dart';
import 'package:yalla_accounts/core/platform/yalla_path_provider.dart';
import 'package:yalla_accounts/features/employees/models/attendance.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';

class AttendanceExportService {
  /// تصدير تقرير الحضور الشهري إلى PDF
  static Future<void> exportToPdf({
    required Employee employee,
    required List<Attendance> records,
    required DateTime month,
  }) async {
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.amiriRegular(); // خط عربي واضح

    final title = 'تحليل الحضور الشهري - ${employee.fullName}';
    final subtitle = 'الشهر: ${DateFormat('yyyy-MM').format(month)}';

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Text(subtitle,
                  style: pw.TextStyle(font: arabicFont, fontSize: 14)),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: ['اليوم', 'الحالة', 'ملاحظات'],
                data: records.map((r) {
                  final day =
                      DateFormat('yyyy-MM-dd – EEEE', 'ar').format(r.date);
                  return [day, r.status, r.notes ?? ''];
                }).toList(),
                cellAlignment: pw.Alignment.centerRight,
                headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, font: arabicFont),
                cellStyle: pw.TextStyle(font: arabicFont),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(4),
                },
              ),
            ],
          ),
        ),
      ),
    );

    await YallaPdfPrintService.layoutPdf(onLayout: (format) => pdf.save());
  }

  /// تصدير تقرير الحضور الشهري إلى Excel
  static Future<void> exportToExcel({
    required Employee employee,
    required List<Attendance> records,
    required DateTime month,
  }) async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['الحضور'];

    sheet.appendRow([
      ex.TextCellValue('تحليل الحضور الشهري'),
      ex.TextCellValue(employee.fullName),
    ]);
    sheet.appendRow([
      ex.TextCellValue('الشهر'),
      ex.TextCellValue(DateFormat('yyyy-MM').format(month)),
    ]);
    sheet.appendRow([]);
    sheet.appendRow([
      ex.TextCellValue('اليوم'),
      ex.TextCellValue('الحالة'),
      ex.TextCellValue('ملاحظات'),
    ]);

    for (var record in records) {
      final formattedDate =
          DateFormat('yyyy-MM-dd – EEEE', 'ar').format(record.date);
      sheet.appendRow([
        ex.TextCellValue(formattedDate),
        ex.TextCellValue(record.status),
        ex.TextCellValue(record.notes ?? ''),
      ]);
    }

    final fileBytes = excel.encode();
    final downloadsDir = await getDownloadsDirectory();
    final safeFileName = employee.fullName
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9\s]'), '');
    final filePath =
        '${downloadsDir!.path}/حضور_${safeFileName}_${month.year}_${month.month}.xlsx';

    final file = File(filePath);
    await file.writeAsBytes(fileBytes!);

    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: file.path.split(Platform.pathSeparator).last,
    );
  }
}
