// 📁 lib/features/repairs/services/repair_export_excel.dart
//
// ====================== ملخص (What’s new/fixed) ======================
// 1) Export Excel: إنشاء .xlsx مع فلاتر: تاريخ/حالة إصلاح/حالة سداد/تأمين/بحث.
// 2) Export PDF Batch: توليد PDF لكل ملف داخل ZIP واحد.
// 3) إصلاح خطأ النوع: تحويل List<int> ➜ Uint8List عبر Uint8List.fromList(...).
// 4) حفظ في Downloads ثم Documents كبديل. أسماء ملفات واضحة مع المرشِّحات.
// 5) يعتمد RepairsService.list و RepairPdfGenerator. بدون بيانات وهمية.
// ---------------------------------------------------------------
// تبعيات مطلوبة في pubspec.yaml:
//   excel: ^2.0.0
//   archive: ^3.4.0
// ---------------------------------------------------------------

import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';

class RepairExportService {
  // --------------------- Public API ---------------------

  /// إنشاء ملف Excel للملفات. يرجّع كائن File.
  /// الفلاتر اختيارية. القيم نفسها كما في RepairsService.list.
  static Future<File> exportExcel({
    String? from, // yyyy-MM-dd
    String? to, // yyyy-MM-dd
    String? repairStatus,
    String? paymentStatus,
    bool insuranceOnly = false,
    String? search,
  }) async {
    final svc = await RepairsService.instance();
    final items = await svc.list(
      from: from,
      to: to,
      repairStatus: repairStatus,
      paymentStatus: paymentStatus,
      insuranceOnly: insuranceOnly,
      search: search,
      newestFirst: false,
    );

    final excel = Excel.createExcel();
    final Sheet sheet = excel['Repairs'];

    // Header
    final headers = [
      'ID',
      'رقم الفاتورة',
      'نوع المركبة',
      'موديل المركبة',
      'رقم المركبة',
      'تاريخ الاستلام',
      'نوع المستفيد',
      'اسم المستفيد',
      'متابعة التأمين',
      'نوع العمل',
      'حالة المركبة',
      'قيمة القطع',
      'قيمة الأعمال',
      'إجمالي الملف',
      'مدفوع',
      'المتبقي',
      'حالة الدفع',
      'ملاحظات',
    ];
    sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

    for (final r in items) {
      final partsTotal = _sum(r.parts, 'price');
      final worksTotal = _sum(r.works, 'price');
      final total = partsTotal + worksTotal;
      final paid = (r.paidAmount).toDouble();
      final remain = total - paid;

      sheet.appendRow([
        TextCellValue(r.id),
        TextCellValue(r.invoiceNumber),
        TextCellValue(r.vehicleType),
        TextCellValue(r.vehicleModel),
        TextCellValue(r.vehicleNumber),
        TextCellValue(_fmtDate(r.receivedDate)),
        TextCellValue(_beneficiaryText(r.beneficiaryType)),
        TextCellValue(r.beneficiaryName),
        TextCellValue(r.insuranceFollowUpStatus ?? ''),
        TextCellValue(r.repairType),
        TextCellValue(r.vehicleStatus),
        TextCellValue(_fmtNum(partsTotal)),
        TextCellValue(_fmtNum(worksTotal)),
        TextCellValue(_fmtNum(total)),
        TextCellValue(_fmtNum(paid)),
        TextCellValue(_fmtNum(remain)),
        TextCellValue(r.paymentStatus ?? r.computedPaymentStatus),
        TextCellValue(r.notes ?? ''),
      ]);
    }

    excel.setDefaultSheet('Repairs');

    // excel.encode() ➜ List<int> => نُحوله إلى Uint8List
    final bytesList = excel.encode()!;
    final out = await _saveBytes(
      Uint8List.fromList(bytesList),
      _buildFileName(
        base: 'repairs_export',
        ext: 'xlsx',
        from: from,
        to: to,
        repairStatus: repairStatus,
        paymentStatus: paymentStatus,
        insuranceOnly: insuranceOnly,
        search: search,
      ),
    );
    return out;
  }

  /// تصدير PDF جماعي داخل ملف ZIP واحد.
  /// سيُنشئ لكل Repair ملف PDF منفصل ثم يضغط الجميع.
  static Future<File> exportPdfZip({
    String? from,
    String? to,
    String? repairStatus,
    String? paymentStatus,
    bool insuranceOnly = false,
    String? search,
  }) async {
    final svc = await RepairsService.instance();
    final items = await svc.list(
      from: from,
      to: to,
      repairStatus: repairStatus,
      paymentStatus: paymentStatus,
      insuranceOnly: insuranceOnly,
      search: search,
      newestFirst: false,
    );

    final archive = Archive();
    final df = DateFormat('yyyy-MM-dd');

    for (final r in items) {
      final bytes = await RepairPdfGenerator.generate(r); // Uint8List
      final safeType = _cleanFs(r.vehicleType);
      final safeName = _cleanFs(r.beneficiaryName);
      final safeNumber = _cleanFs(r.vehicleNumber);
      final date = df.format(r.receivedDate);
      final name = '$safeType-$safeName-$safeNumber-$date.pdf';

      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    // encode() ➜ List<int> → حوّله إلى Uint8List
    final zipList = ZipEncoder().encode(archive)!;
    final out = await _saveBytes(
      Uint8List.fromList(zipList),
      _buildFileName(
        base: 'repairs_pdfs',
        ext: 'zip',
        from: from,
        to: to,
        repairStatus: repairStatus,
        paymentStatus: paymentStatus,
        insuranceOnly: insuranceOnly,
        search: search,
      ),
    );
    return out;
  }

  // --------------------- Helpers ---------------------

  static double _sum(List<Map<String, dynamic>> list, String key) {
    return list.fold<double>(
        0.0, (s, e) => s + ((e[key] as num?)?.toDouble() ?? 0.0));
  }

  static String _fmtNum(double v) {
    final f = NumberFormat('#,##0.00', 'ar');
    return f.format(v);
  }

  static String _fmtDate(DateTime d) {
    return DateFormat('yyyy-MM-dd').format(d);
  }

  static String _beneficiaryText(String t) {
    final v = t.trim();
    return (v == 'INSURANCE' || v == 'شركة تأمين') ? 'شركة تأمين' : 'أفراد';
  }

  static Future<Directory> _downloadsOrDocs() async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _saveBytes(Uint8List bytes, String fileName) async {
    final dir = await _downloadsOrDocs();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _buildFileName({
    required String base,
    required String ext,
    String? from,
    String? to,
    String? repairStatus,
    String? paymentStatus,
    bool insuranceOnly = false,
    String? search,
  }) {
    final parts = <String>[];
    parts.add(base);
    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    parts.add(now);
    if (from != null && from.isNotEmpty) parts.add('from_$from');
    if (to != null && to.isNotEmpty) parts.add('to_$to');
    if (repairStatus != null && repairStatus.isNotEmpty) {
      parts.add('rs_${_cleanFs(repairStatus)}');
    }
    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      parts.add('ps_${_cleanFs(paymentStatus)}');
    }
    if (insuranceOnly) parts.add('insuranceOnly');
    if (search != null && search.trim().isNotEmpty) {
      parts.add('q_${_cleanFs(search.trim())}');
    }
    return '${parts.join('_')}.$ext';
  }

  static String _cleanFs(String input) {
    final cleaned =
        input.replaceAll(RegExp(r'[^\u0600-\u06FF\w\s\-\._]+'), '_').trim();
    return cleaned.replaceAll(RegExp(r'[_\s\-]{2,}'), '_');
  }
}
