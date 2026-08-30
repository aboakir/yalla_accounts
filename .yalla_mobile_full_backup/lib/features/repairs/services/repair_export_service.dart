import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

class RepairExportService {
  static Future<void> exportRepairsToExcel(List<Repair> repairs) async {
    final excel = Excel.createExcel();

    final fileBytes = excel.encode();
    if (fileBytes == null) return;

    await Printing.sharePdf(
      bytes: Uint8List.fromList(fileBytes),
      filename: 'تقرير_الإصلاح.xlsx',
    );
  }

  static Future<void> exportRepairsToPdf(List<Repair> repairs) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('📊 تقرير الإصلاح', style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: [
              'رقم المركبة',
              'نوع المركبة',
              'نوع الإصلاح',
              'قيمة الملف',
              'المدفوع',
              'المتبقي',
              'تاريخ الاستلام',
              'حالة السداد',
            ],
            data: repairs
                .map((r) => [
                      r.vehicleNumber,
                      r.vehicleType,
                      r.repairType,
                      r.fileValue.toStringAsFixed(0),
                      r.totalPaidAmount.toStringAsFixed(0),
                      r.remainingAmount.toStringAsFixed(0),
                      DateFormat('yyyy-MM-dd').format(r.receivedDate),
                      r.computedPaymentStatus,
                    ])
                .toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}
