import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class ImageHelper {
  /// التقاط صورة من الكاميرا أو المعرض
  static Future<File?> pickImage({required ImageSource source}) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80);
    return pickedFile != null ? File(pickedFile.path) : null;
  }

  /// تحويل صورة إلى Uint8List
  static Future<Uint8List?> fileToBytes(File file) async {
    return await file.readAsBytes();
  }

  /// قراءة صورة من الأصول كـ Uint8List
  static Future<Uint8List> loadAsset(String path) async {
    return await rootBundle
        .load(path)
        .then((value) => value.buffer.asUint8List());
  }
}
