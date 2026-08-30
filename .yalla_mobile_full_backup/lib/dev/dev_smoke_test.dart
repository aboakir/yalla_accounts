// 📁 lib/dev/dev_smoke_test_screen.dart
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class DevSmokeTestScreen extends StatefulWidget {
  const DevSmokeTestScreen({super.key});

  @override
  State<DevSmokeTestScreen> createState() => _DevSmokeTestScreenState();
}

class _DevSmokeTestScreenState extends State<DevSmokeTestScreen> {
  final List<String> _logs = [];
  bool _running = false;

  void _log(String msg) {
    setState(() => _logs.add(msg));
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    _logs.clear();

    try {
      _log("تهيئة قاعدة البيانات...");
      final db = await DBService.database;

      // اختبار الحسابات الأساسية
      _log("فحص الحسابات الأساسية (1000 / 1010 / 1200 / 2000)...");
      final basic = await db.query(
        "accounts",
        columns: ["code"],
      );

      final need = {"1000", "1010", "1200", "2000"};
      final have = basic.map((e) => (e["code"] ?? "").toString()).toSet();

      for (final code in need) {
        if (!have.contains(code)) {
          throw "❌ الحساب $code غير موجود";
        }
      }

      _log("✔ الحسابات الأساسية موجودة");

      // فحص جداول GL الأساسية
      Future<void> mustCol(String table, String col) async {
        final info = await db.rawQuery("PRAGMA table_info($table)");
        final cols = info.map((m) => (m['name'] ?? '').toString()).toSet();
        if (!cols.contains(col)) throw "❌ $table.$col غير موجود";
      }

      _log("فحص بنية GL...");
      await mustCol("gl_entries", "source");
      await mustCol("gl_lines", "account_id");
      await mustCol("gl_lines", "debit");
      await mustCol("gl_lines", "credit");

      _log("✔ بنية GL سليمة");

      _log("🎯 Smoke Test اكتمل بدون أخطاء");
    } catch (e, st) {
      _log("❌ خطأ: $e");
      _log("$st");
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("[DEV] Smoke Test"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? "جارٍ الفحص..." : "Run Smoke Test"),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (_, i) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(_logs[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
