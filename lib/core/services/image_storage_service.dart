import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStorageService {
  // -------------------------------------------------------------------------
  // 1) اختيار القرص الأساسي (D ثم C)
  // -------------------------------------------------------------------------
  static Future<String> _getRootDirectory() async {
    // Mobile platforms are sandboxed: never write to Windows drive paths.
    if (Platform.isIOS || Platform.isAndroid) {
      final docs = await getApplicationDocumentsDirectory();
      final root = Directory(p.join(docs.path, 'YallaAccounts'));
      if (!await root.exists()) await root.create(recursive: true);
      return root.path;
    }

    // Preserve the existing desktop storage contract.
    if (Platform.isWindows) {
      final dDrive = Directory('D:\\');
      if (await dDrive.exists()) return 'D:\\YallaAccounts';
      return 'C:\\YallaAccounts';
    }

    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'YallaAccounts'));
    if (!await root.exists()) await root.create(recursive: true);
    return root.path;
  }

  // -------------------------------------------------------------------------
  // 2) تنظيف اسم المجلد — مسموح عربي + إنجليزي + أرقام + "_"
  // -------------------------------------------------------------------------
  static String _safeFolderName(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9_\u0600-\u06FF]'), '_');
  }

  // -------------------------------------------------------------------------
  // 2.1) تنظيف اسم الـ module (يفضل إنجليزي/أرقام/_ فقط)
  // -------------------------------------------------------------------------
  static String _safeModule(String input) {
    final s = input.trim().isEmpty ? 'repairs' : input.trim();
    return s.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  // -------------------------------------------------------------------------
  // 3) حفظ الصورة — النسخة الجديدة (بدون saveTo)
  //    تستخدم writeAsBytes لمنع تكرار نفس الصورة
  //
  // ✅ NEW: module (اختياري) للفصل بين الأقسام:
  //    repairs / insurance / ...
  // -------------------------------------------------------------------------
  static Future<String> saveImage({
    required XFile image,
    String module = 'repairs', // ✅ default keeps old repairs code working
    required String vehicleType,
    required String vehicleNumber,
    required String beneficiaryName,
    required DateTime receivedDate,
  }) async {
    try {
      final root = await _getRootDirectory();

      final year = receivedDate.year.toString();
      final month = receivedDate.month.toString().padLeft(2, '0');

      // اسم مجلد المركبة
      final rawFolder = '${vehicleType}_${vehicleNumber}_$beneficiaryName';
      final folderName = _safeFolderName(rawFolder);

      final safeModule = _safeModule(module);

      // ✅ المسار النهائي للمجلد (مع فصل repairs عن insurance)
      final dir = Directory(
        p.join(root, 'images', safeModule, year, month, folderName),
      );

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // اسم فريد للصورة — microseconds أفضل للتعدد السريع
      final fileName = 'img_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final savePath = p.join(dir.path, fileName);

      // ----------- الحل الحقيقي لمشكلة تكرار الصور -----------
      final bytes = await image.readAsBytes();
      await File(savePath).writeAsBytes(bytes);
      // ---------------------------------------------------------

      return savePath;
    } catch (e) {
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // 4) حذف الصورة من القرص
  // -------------------------------------------------------------------------
  static Future<void> deleteImage(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // تجاهل الخطأ
    }
  }

  // -------------------------------------------------------------------------
  // 5) "ضغط" شكلي — يمكنك لاحقاً إضافة ضغط حقيقي
  // -------------------------------------------------------------------------
  static Future<XFile> compressImage(XFile original) async {
    try {
      await original.length();
      return original;
    } catch (_) {
      return original;
    }
  }

  // -------------------------------------------------------------------------
  // 6) إنشاء Thumbnail (حالياً نسخة طبق الأصل — لاحقاً نضيف ضغط وتصغير)
  // -------------------------------------------------------------------------
  static Future<String> generateThumbnail(String originalPath) async {
    try {
      final file = File(originalPath);
      if (!await file.exists()) return originalPath;

      final dir = file.parent;
      final thumbPath =
          '${dir.path}/thumb_${DateTime.now().microsecondsSinceEpoch}.jpg';

      await file.copy(thumbPath);

      return thumbPath;
    } catch (_) {
      return originalPath;
    }
  }
}
