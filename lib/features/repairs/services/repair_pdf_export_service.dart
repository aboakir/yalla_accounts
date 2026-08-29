// 📁 lib/features/repairs/services/repair_pdf_export_service.dart
//
// RepairPdfExportService — غلاف بسيط فوق RepairPdfGenerator
// - يولد PDF من Repair، يحفظه، ويفتحه عند الطلب.

import 'dart:io';
import 'dart:typed_data';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';

class RepairPdfExportService {
  /// يرجع بايتات ملف الـ PDF فقط.
  static Future<Uint8List> exportBytes(Repair repair) async {
    return RepairPdfGenerator.generate(repair);
  }

  /// ينشئ ويحفظ كملف ويعيد كائن File.
  static Future<File> exportToFile(Repair repair) async {
    return RepairPdfGenerator.saveToFile(repair);
  }

  /// ينشئ، يحفظ، ثم يفتح الملف عبر النظام.
  static Future<File> exportAndOpen(Repair repair) async {
    return RepairPdfGenerator.saveToFileAndOpen(repair);
  }
}
