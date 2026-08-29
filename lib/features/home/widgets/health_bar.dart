// 📁 lib/features/home/widgets/health_bar.dart
//
// HealthBar — شريط الحالة الذكي في الصفحة الرئيسية
// AR: استعلامات خفيفة من DBService فقط + حُرّاس للأخطاء.
// EN: Lightweight DB reads with guards, no dummy data.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class HealthBar extends StatefulWidget {
  const HealthBar({super.key});
  @override
  State<HealthBar> createState() => _HealthBarState();
}

class _HealthBarState extends State<HealthBar> {
  bool _loading = true;

  double cashFlow = 0.0; // اليوم: In - Out على 1000/1010
  int repairsDone = 0; // اليوم: تم التسليم
  bool glBalanced = true; // GL: SUM(debit) == SUM(credit)
  String lastSync = '-'; // من SharedPreferences

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final r = await db.rawQuery('PRAGMA table_info($table);');
    for (final m in r) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      if (name == column.toLowerCase()) return true;
    }
    return false;
  }

  Future<void> _loadData() async {
    final db = await DBService.database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // ===== التدفق النقدي اليومي (1000 + 1010) =====
      final cashRes = await db.rawQuery('''
        SELECT 
          IFNULL(SUM(debit),0)  AS inflow,
          IFNULL(SUM(credit),0) AS outflow
        FROM gl_lines
        WHERE account_code IN ('1000','1010')
          AND date = DATE('now')
      ''');
      final inflow = (cashRes.first['inflow'] as num?)?.toDouble() ?? 0.0;
      final outflow = (cashRes.first['outflow'] as num?)?.toDouble() ?? 0.0;
      cashFlow = inflow - outflow;

      // ===== الإصلاحات المنجزة اليوم =====
      // نحترم وجود/عدم وجود عمود updated_at.
      final hasUpdated = await _hasColumn(db, 'repairs', 'updated_at');
      final repairsRes = await db.rawQuery('''
        SELECT COUNT(*) AS c
        FROM repairs
        WHERE status IN ('تم التسليم','CLOSED','مغلق')
          AND DATE(${hasUpdated ? 'updated_at' : 'date'}) = DATE(?)
      ''', [today]);
      repairsDone = ((repairsRes.first['c'] as num?) ?? 0).toInt();

      // ===== توازن GL =====
      final glRes = await db.rawQuery('''
        SELECT ABS(IFNULL(SUM(debit),0) - IFNULL(SUM(credit),0)) AS diff
        FROM gl_lines
      ''');
      final diff = (glRes.first['diff'] as num?)?.toDouble() ?? 0.0;
      glBalanced = diff < 0.01;

      // ===== آخر مزامنة (SharedPreferences) =====
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTime = prefs.getInt('lastSyncTime');
      if (lastSyncTime != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(lastSyncTime);
        lastSync = DateFormat('yyyy/MM/dd HH:mm').format(dt);
      } else {
        lastSync = 'لم تتم بعد';
      }
    } catch (_) {
      // فشل آمن: نُبقي القيم الحالية ولا نعلّق الواجهة.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: AdaptiveRow(
            children: List.generate(
                4,
                (_) => Expanded(
                      child: Container(
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    )),
          ),
        ),
      );
    }

    return Card(
      color: Theme.of(context).cardColor.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: AdaptiveRow(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _item(
              label: '💰 التدفق النقدي',
              value: '${MoneyFormatter.format(cashFlow)}',
              color: cashFlow >= 0 ? Colors.green : Colors.redAccent,
            ),
            _divider(),
            _item(
              label: '🚗 الإصلاحات المنجزة',
              value: repairsDone.toString(),
              color: AppColors.primary,
            ),
            _divider(),
            _item(
              label: '⚖️ توازن GL',
              value: glBalanced ? 'متوازن' : 'خلل',
              color: glBalanced ? Colors.green : Colors.redAccent,
            ),
            _divider(),
            _item(
              label: '🔄 آخر مزامنة',
              value: lastSync,
              color: Colors.blueGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _item({required String label, required String value, Color? color}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(height: 30, width: 1, color: Colors.grey.withOpacity(0.3));
  }
}
