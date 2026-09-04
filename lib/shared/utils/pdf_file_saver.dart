import 'dart:typed_data';

import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';

class PdfFileSaver {
  static Future<String> saveToDownloads(
    Uint8List pdfBytes,
    String fileName,
  ) async {
    final file = await YallaStorageService.savePdf(
      bytes: pdfBytes,
      module: 'exports',
      fileName: fileName,
    );
    return file.path;
  }
}
