import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

Future<String> savePdfToFile(Uint8List pdfBytes, String baseName) async {
  final downloadsDir = await getApplicationDocumentsDirectory();
  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final fileName = '${baseName}_$timestamp.pdf';
  final filePath = '${downloadsDir.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(pdfBytes);
  return filePath;
}
