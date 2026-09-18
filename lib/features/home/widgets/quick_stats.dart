import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/y_glass.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class QuickStats extends StatelessWidget {
  const QuickStats({super.key});

  // ===== helpers
  Future<bool> _tableExists(String name) async {
    final db = await DBService.database;
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND LOWER(name)=LOWER(?) LIMIT 1",
      [name],
    );
    return r.isNotEmpty;
  }

  Future<int> _countRows(String table,
      {String where = '', List<Object?> args = const []}) async {
    final db = await DBService.database;
    final sql = where.trim().isEmpty
        ? "SELECT COUNT(*) c FROM $table"
        : "SELECT COUNT(*) c FROM $table WHERE $where";
    final r = await db.rawQuery(sql, args);
    return ((r.first['c'] as num?) ?? 0).toInt();
  }

  Future<int> _suppliersSmartCount() async {
    // 1) suppliers
    if (await _tableExists('suppliers')) return _countRows('suppliers');

    // 2) vendors
    if (await _tableExists('vendors')) return _countRows('vendors');

    // 3) insurance_companies (تُستخدم أحيانًا كمورّد خدمي)
    if (await _tableExists('insurance_companies')) {
      return _countRows('insurance_companies');
    }

    // 4) companies مع نوع
    if (await _tableExists('companies')) {
      return _countRows("companies",
          where: "LOWER(type) IN ('supplier','vendor')");
    }

    // لا يوجد مصدر معروف
    return 0;
  }

  Future<Map<String, num>> _load() async {
    final db = await DBService.database;
    DateFormat('yyyy-MM-dd').format(DateTime.now());
    final thisMonth = DateFormat('yyyy-MM').format(DateTime.now());

    // العملاء من جدول clients مباشرة، مع بدائل إن لزم
    int clientsTotal = 0;
    if (await _tableExists('clients')) {
      clientsTotal = await _countRows('clients');
    } else if (await _tableExists('customers')) {
      clientsTotal = await _countRows('customers');
    } else if (await _tableExists('companies')) {
      clientsTotal = await _countRows("companies",
          where: "LOWER(type) IN ('client','customer')");
    }

    final suppliersTotal = await _suppliersSmartCount();

    final invoices = await db.rawQuery("""
      SELECT COUNT(*) c, IFNULL(SUM(total),0) s
      FROM invoices
      WHERE strftime('%Y-%m', date)=?
    """, [thisMonth]);

    final cashFlow = await db.rawQuery("""
  SELECT
    IFNULL(SUM(CASE WHEN a.code IN('1000','1010') THEN l.debit  ELSE 0 END),0) d,
    IFNULL(SUM(CASE WHEN a.code IN('1000','1010') THEN l.credit ELSE 0 END),0) c
  FROM gl_lines l
  JOIN gl_entries e ON e.id = l.entry_id
  JOIN accounts a ON a.id = l.account_id
  WHERE DATE(e.date) >= DATE('now','-7 day')
""");

    final d = ((cashFlow.first['d'] as num?) ?? 0).toDouble();
    final c = ((cashFlow.first['c'] as num?) ?? 0).toDouble();

    return {
      'clients_total': clientsTotal,
      'suppliers_total': suppliersTotal,
      'invoices_count': ((invoices.first['c'] as num?) ?? 0),
      'cash_today': d - c,
    };
  }

  @override
  Widget build(BuildContext context) {
    final nf0 = NumberFormat('#,##0');

    return YGlassCard(
      child: FutureBuilder<Map<String, num>>(
        future: _load(),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 70);
          }
          if (snap.hasError || snap.data == null) {
            return const Text('تعذّر التحميل');
          }
          final m = snap.data!;

          Widget tile(
              String title, IconData ic, String v, Color c, String route) {
            return Expanded(
              child: InkWell(
                onTap: () => AppRoutes.pushNamedSafe(ctx, route),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.black.withOpacity(0.06), width: 1),
                  ),
                  child: AdaptiveRow(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: c.withOpacity(0.12),
                        child: Icon(ic, size: 16, color: c),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(v,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, color: c)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left),
                    ],
                  ),
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YSectionTitle('إحصاءات سريعة', icon: Icons.insights),
              const SizedBox(height: 10),
              AdaptiveRow(
                children: [
                  tile(
                      'العملاء',
                      Icons.people,
                      nf0.format(m['clients_total'] ?? 0),
                      Colors.indigo,
                      AppRoutes.clients),
                  const SizedBox(width: 10),
                  tile(
                      'الموردون',
                      Icons.warehouse,
                      nf0.format(m['suppliers_total'] ?? 0),
                      Colors.brown,
                      AppRoutes.suppliers),
                  const SizedBox(width: 10),
                  tile(
                    'الرصيد النقدي - الاسبوعي',
                    Icons.local_fire_department,
                    MoneyFormatter.format(m['cash_today'] ?? 0),
                    (m['cash_today'] ?? 0) >= 0
                        ? AppColors.primary
                        : Colors.red,
                    AppRoutes.cashAccount,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
