import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class LogsService {
  static final LogsService _instance = LogsService._internal();

  factory LogsService() {
    return _instance;
  }

  LogsService._internal();

  // مسار مجلد التخزين للملفات
  Future<Directory> get _logsDirectory async {
    final directory = await getApplicationDocumentsDirectory();
    final logsDir = Directory('${directory.path}/logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    return logsDir;
  }

  // اسم ملف السجل حسب التاريخ (مثلاً: log_2025-06-12.txt)
  Future<File> get _logFile async {
    final dir = await _logsDirectory;
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final path = '${dir.path}/log_$date.txt';
    return File(path);
  }

  // إضافة سجل جديد مع طابع زمني
  Future<void> writeLog(String message) async {
    try {
      final file = await _logFile;
      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final logLine = '[$timestamp] $message\n';
      await file.writeAsString(logLine, mode: FileMode.append, flush: true);
    } catch (e) {
      // يمكن معالجة الخطأ هنا أو تجاهله
    }
  }

  // قراءة جميع السجلات من ملف اليوم الحالي
  Future<String> readTodayLogs() async {
    try {
      final file = await _logFile;
      return await file.readAsString();
    } catch (e) {
      return '';
    }
  }

  // حذف ملفات السجل القديمة (اختياري)
  Future<void> clearOldLogs({int keepDays = 7}) async {
    try {
      final dir = await _logsDirectory;
      final files = dir.listSync();
      final cutoffDate = DateTime.now().subtract(Duration(days: keepDays));

      for (var file in files) {
        if (file is File) {
          final name = file.path.split('/').last;
          final datePart = name.replaceAll(RegExp(r'log_|\.txt'), '');
          DateTime? fileDate;
          try {
            fileDate = DateFormat('yyyy-MM-dd').parse(datePart);
          } catch (_) {}
          if (fileDate != null && fileDate.isBefore(cutoffDate)) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      // تجاهل الخطأ أو سجله
    }
  }
}
