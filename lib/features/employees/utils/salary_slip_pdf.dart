import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

Future<Uint8List> generateSalarySlipPdf(Employee employee) async {
  final pdf = pw.Document();
  final formatter = NumberFormat('#,##0.00', 'ar');
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  final netSalary = employee.baseSalary +
      employee.allowances -
      employee.deductions -
      employee.advances;

  final barcode = Barcode.code128();
  final barcodeWidget = pw.BarcodeWidget(
    barcode: barcode,
    data: employee.employeeCode,
    width: 150,
    height: 40,
    drawText: false,
  );

  final header = await _buildHeader(today);

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Container(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              header,
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _sectionTitle('بيانات الموظف'),
              pw.SizedBox(height: 8),
              _row('الاسم الكامل:', employee.fullName),
              _row('المسمى الوظيفي:', employee.jobTitle),
              _row('الرقم الوظيفي:', employee.employeeCode),
              _row('تاريخ التعيين:',
                  DateFormat('yyyy-MM-dd').format(employee.hireDate)),
              pw.SizedBox(height: 16),
              barcodeWidget,
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _sectionTitle('تفاصيل الراتب'),
              pw.SizedBox(height: 8),
              _row('الراتب الأساسي:',
                  '${MoneyFormatter.format(employee.baseSalary)}'),
              _row('البدلات:', '${MoneyFormatter.format(employee.allowances)}'),
              _row(
                  'الخصومات:', '${MoneyFormatter.format(employee.deductions)}'),
              _row('السلف:', '${MoneyFormatter.format(employee.advances)}'),
              pw.SizedBox(height: 8),
              _row('صافي الراتب:', '${MoneyFormatter.format(netSalary)}',
                  bold: true, color: PdfColors.green800),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _sectionTitle('ملاحظات'),
              pw.SizedBox(height: 4),
              pw.Text(
                employee.notes.isNotEmpty ? employee.notes : 'لا توجد ملاحظات',
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('_________________________'),
                    pw.Text('توقيع المدير'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  return pdf.save();
}

Future<Uint8List> _getLogoBytes() async {
  // ضع هنا صورة الشعار لاحقًا إن توفر
  return Uint8List(0);
}

Future<pw.Widget> _buildHeader(String today) async {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ورشة يلا – لإصلاح المركبات',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'تاريخ الطباعة: $today',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
      pw.Container(
        width: 50,
        height: 50,
        child: pw.Image(
          pw.MemoryImage(await _getLogoBytes()),
          fit: pw.BoxFit.contain,
        ),
      ),
    ],
  );
}

pw.Widget _sectionTitle(String title) {
  return pw.Text(
    title,
    style: pw.TextStyle(
      // أزلنا const من هنا
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      decoration: pw.TextDecoration.underline,
    ),
  );
}

pw.Widget _row(String label, String value,
    {bool bold = false, PdfColor? color}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black,
            ),
          ),
        ),
      ],
    ),
  );
}
