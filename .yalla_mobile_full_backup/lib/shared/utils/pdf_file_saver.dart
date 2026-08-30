// lib/features/repairs/utils/pdf_file_saver.dart

import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PdfFileSaver {
  static Future<String> saveToDownloads(
      Uint8List pdfBytes, String fileName) async {
    final dir = await getDownloadsDirectory();
    final file = File('${dir!.path}/$fileName.pdf');
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }
}
