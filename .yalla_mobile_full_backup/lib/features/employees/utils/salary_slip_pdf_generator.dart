import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class SalarySlipPdfGenerator {
  static Future<void> generateAndPrint(Employee employee) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0.00', 'ar');
    final netSalary = employee.baseSalary +
        employee.allowances -
        employee.deductions -
        employee.advances;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(32),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'ورشة يلا – لإصلاح المركبات',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Icon(const pw.IconData(0xe8b8), size: 30),
                    ],
                  ),
                  pw.SizedBox(height: 16),
                  pw.Divider(),

                  // Employee Info
                  pw.Text(
                    'بيانات الموظف',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _row('الاسم:', employee.fullName),
                  _row('المسمى الوظيفي:', employee.jobTitle),
                  _row('الرقم الوظيفي:', employee.employeeCode),
                  _row('تاريخ التعيين:',
                      DateFormat('yyyy-MM-dd').format(employee.hireDate)),
                  pw.Divider(),

                  // Salary Info
                  pw.Text(
                    'تفاصيل الراتب',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _row('الراتب الأساسي:',
                      '${MoneyFormatter.format(employee.baseSalary)}'),
                  _row('البدلات:',
                      '${MoneyFormatter.format(employee.allowances)}'),
                  _row('الخصومات:',
                      '${MoneyFormatter.format(employee.deductions)}'),
                  _row(
                      'السلفة:', '${MoneyFormatter.format(employee.advances)}'),
                  pw.SizedBox(height: 8),
                  _row(
                    'صافي الراتب:',
                    '${MoneyFormatter.format(netSalary)}',
                    bold: true,
                    color: PdfColors.green800,
                  ),
                  pw.Divider(),

                  // Notes
                  pw.Text(
                    'ملاحظات',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    employee.notes.isEmpty ? 'لا توجد ملاحظات' : employee.notes,
                    style: const pw.TextStyle(fontSize: 12),
                  ),

                  pw.Spacer(),
                  pw.Text('_________________________'),
                  pw.Text('توقيع المدير',
                      style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );

    // Save to temporary file
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/salary_slip_${employee.id}.pdf');
    await file.writeAsBytes(await pdf.save());

    // Print or Share
    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'قسيمة_راتب.pdf');
  }

  static pw.Widget _row(String label, String value,
      {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
              flex: 2,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 12))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color ?? PdfColors.black,
                ),
              )),
        ],
      ),
    );
  }
}
