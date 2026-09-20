import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// المفتاح السري المستخدم في نظام التفعيل (يجب مطابقته مع التطبيق)
const String secret = "YALLA-ACTIVATION-SECRET-2025";

/// عدد الأكواد المراد توليدها
const int totalCodes = 2000;

/// مدة الصلاحية الافتراضية — عدلها كما تريد
final DateTime expiryDate = DateTime(2026, 12, 31);

/// عدد الأجهزة المسموح بها
const int maxDevices = 2;

/// توليد جزء من الكود مثل ABCD أو 12EF
String randomPart(int length) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  final rand = Random.secure();

  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}

/// توليد الكود الخام YA-XXXX-YYYY-ZZZZ
String generateRawCode() {
  return "YA-${randomPart(4)}-${randomPart(4)}-${randomPart(4)}";
}

/// توليد الهاش الخاص بالكود
String generateHash(String code, DateTime expiry, int maxDevices) {
  final buffer = "$code|${expiry.toIso8601String()}|$maxDevices|$secret";
  return sha256.convert(utf8.encode(buffer)).toString();
}

/// بناء الكود الكامل النهائي:
/// RAW:EXPIRY:DEVICES:HASH
String buildFullCode(String raw, String hash) {
  return "$raw:${expiryDate.toIso8601String()}:$maxDevices:$hash";
}

void main() async {
  final file = File("activation_codes.csv");
  final sink = file.openWrite();

  // كتابة رأس الملف
  sink.writeln("RawCode,Expiry,MaxDevices,Hash,FullCode");

  for (int i = 0; i < totalCodes; i++) {
    final raw = generateRawCode();
    final hash = generateHash(raw, expiryDate, maxDevices);
    final full = buildFullCode(raw, hash);

    sink.writeln(
        "$raw,${expiryDate.toIso8601String()},$maxDevices,$hash,$full");
  }

  await sink.close();

  stdout.writeln("✔ تمت عملية توليد 2000 كود تفعيل بنجاح");
  stdout.writeln("✔ الملف جاهز: activation_codes.csv");
}
