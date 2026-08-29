// يستخدم عندما تكون مكتبات io متاحة (Windows/Linux/macOS)
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initFfiIfNeeded() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
