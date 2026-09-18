import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

class RepairExcelExport {
  static Future<void> exportToExcel(List<Repair> repairs,
      [String? fileName]) async {
    final excel = Excel.createExcel();
    excel['الإصلاحات'];

    // اسم الملف
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(now);
    final finalFileName = fileName ?? 'كشف_الإصلاحات_$formattedDate.xlsx';

    // حفظ الملف في مجلد التنزيلات
    final dir = await getDownloadsDirectory();
    final file = File('${dir!.path}/$finalFileName');
    await file.writeAsBytes(excel.encode()!);
  }
}
