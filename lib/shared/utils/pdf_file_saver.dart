// Mobile-safe PDF file saver. Desktop Downloads behavior is preserved.
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PdfFileSaver {
  static Future<String> saveToDownloads(
      Uint8List pdfBytes, String fileName) async {
    Directory? dir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
    }
    // iOS has no app-writable public Downloads directory. Keep the generated
    // file in the app sandbox; callers can open/share/export it normally.
    dir ??= await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'YallaAccounts', 'exports'));
    if (!await exportDir.exists()) await exportDir.create(recursive: true);
    final safeName =
        fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf';
    final file = File(p.join(exportDir.path, safeName));
    await file.writeAsBytes(pdfBytes, flush: true);
    return file.path;
  }
}
