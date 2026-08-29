import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/y_glass.dart';

class WeeklySummary extends StatelessWidget {
  const WeeklySummary({super.key});

  Future<Map<String, num>> _load() async {
    final db = await DBService.database;

    // آخر 7 أيام شاملة اليوم
    final start = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 6)));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 1) إجمالي الفواتير خلال الأسبوع
    final invSumQ = await db.rawQuery("""
      SELECT IFNULL(SUM(total),0) v
      FROM invoices
      WHERE DATE(date) BETWEEN DATE(?) AND DATE(?)
    """, [start, today]);
    final invoicesTotal = ((invSumQ.first['v'] as num?) ?? 0).toDouble();

    // 2) عدد الفواتير خلال الأسبوع
    final invCntQ = await db.rawQuery("""
      SELECT COUNT(*) c
      FROM invoices
      WHERE DATE(date) BETWEEN DATE(?) AND DATE(?)
    """, [start, today]);
    final invoicesCount = ((invCntQ.first['c'] as num?) ?? 0).toInt();

    // 3) الإيراد من GL (حسابات 4xxx)
    final revQ = await db.rawQuery("""
      SELECT IFNULL(SUM(l.credit - l.debit),0) r
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE a.code LIKE '4%' AND DATE(e.date) BETWEEN DATE(?) AND DATE(?)
    """, [start, today]);
    final revenue = ((revQ.first['r'] as num?) ?? 0).toDouble();

    // 4) المصروف من GL (حسابات 5xxx)
    final expQ = await db.rawQuery("""
      SELECT IFNULL(SUM(l.debit - l.credit),0) x
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE a.code LIKE '5%' AND DATE(e.date) BETWEEN DATE(?) AND DATE(?)
    """, [start, today]);
    final expense = ((expQ.first['x'] as num?) ?? 0).toDouble();

    // 5) إصلاحات الأسبوع (حسب تاريخ الاستلام)
    final repairsQ = await db.rawQuery("""
      SELECT COUNT(*) c
      FROM repairs
      WHERE DATE(receivedDate) BETWEEN DATE(?) AND DATE(?)
    """, [start, today]);
    final repairsCount = ((repairsQ.first['c'] as num?) ?? 0).toInt();

    // 6) عدد المدفوعات الأسبوعية من GL:
    // نعدّ قيود GL التي لامست حسابات النقد/البنك (1000,1010) خلال المدة.
    const cashCodes = ['1000', '1010'];
    final placeholders = List.filled(cashCodes.length, '?').join(',');
    final args = <Object?>[start, today, ...cashCodes];
    final payCntQ = await db.rawQuery("""
      SELECT COUNT(DISTINCT e.id) c
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id = e.id
      JOIN accounts a ON a.id = l.account_id
      WHERE DATE(e.date) BETWEEN DATE(?) AND DATE(?)
        AND a.code IN ($placeholders)
    """, args);
    final paymentsCount = ((payCntQ.first['c'] as num?) ?? 0).toInt();

    return {
      'invoices_total': invoicesTotal,
      'invoices_count': invoicesCount,
      'revenue': revenue,
      'expense': expense,
      'profit': revenue - expense,
      'repairs_count': repairsCount,
      'payments_count': paymentsCount,
    };
  }

  @override
  Widget build(BuildContext context) {
    final nf0 = NumberFormat('#,##0');
    final nf2 = NumberFormat('#,##0.##');

    Widget tile(
      BuildContext ctx, {
      required String title,
      required IconData icon,
      required num value,
      required Color color,
      String? route,
      bool isMoney = false,
    }) {
      final text = isMoney ? nf2.format(value) : nf0.format(value);
      return Expanded(
        child: InkWell(
          onTap: route == null ? null : () => Navigator.pushNamed(ctx, route),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.black.withOpacity(0.06), width: 1),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(icon, size: 16, color: color),
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
                      Text(text,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: color)),
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

    return YGlassCard(
      child: FutureBuilder<Map<String, num>>(
        future: _load(),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 92);
          }
          if (snap.hasError || snap.data == null) {
            return const Text('تعذّر تحميل الملخص');
          }
          final m = snap.data!;

          final profitColor =
              (m['profit'] ?? 0) >= 0 ? Colors.green : Colors.red;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YSectionTitle('ملخص أسبوعي', icon: Icons.view_week),
              const SizedBox(height: 10),

              // الصف الأول: فواتير الإجمالي + الإيراد + المصروف + الصافي
              Row(
                children: [
                  tile(ctx,
                      title: 'الفواتير',
                      icon: Icons.receipt_long,
                      value: m['invoices_total'] ?? 0,
                      color: Colors.indigo,
                      route: '/finance/invoices?range=7d',
                      isMoney: true),
                  const SizedBox(width: 10),
                  tile(ctx,
                      title: 'الإيراد',
                      icon: Icons.trending_up,
                      value: m['revenue'] ?? 0,
                      color: Colors.green,
                      route: '/finance/pnl?range=7d',
                      isMoney: true),
                  const SizedBox(width: 10),
                  tile(ctx,
                      title: 'المصروف',
                      icon: Icons.trending_down,
                      value: m['expense'] ?? 0,
                      color: Colors.deepOrange,
                      route: '/finance/pnl?range=7d',
                      isMoney: true),
                  const SizedBox(width: 10),
                  tile(ctx,
                      title: 'الصافي',
                      icon: Icons.calculate,
                      value: m['profit'] ?? 0,
                      color: profitColor,
                      route: '/finance/pnl?range=7d',
                      isMoney: true),
                ],
              ),
              const SizedBox(height: 10),

              // الصف الثاني: عدد المدفوعات + إصلاحات + عدد الفواتير
              Row(
                children: [
                  tile(ctx,
                      title: 'عدد المدفوعات',
                      icon: Icons.payments,
                      value: m['payments_count'] ?? 0,
                      color: Colors.teal,
                      route: '/finance/cash-flow?range=7d'),
                  const SizedBox(width: 10),
                  tile(ctx,
                      title: 'إصلاحات',
                      icon: Icons.build,
                      value: m['repairs_count'] ?? 0,
                      color: Colors.orange,
                      route: '/repairs?range=7d'),
                  const SizedBox(width: 10),
                  tile(ctx,
                      title: 'عدد الفواتير',
                      icon: Icons.receipt,
                      value: m['invoices_count'] ?? 0,
                      color: Colors.indigo,
                      route: '/finance/invoices?range=7d'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
