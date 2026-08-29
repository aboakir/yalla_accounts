// -----------------------------------------------------------------------------
// 📁 lib/features/home/screens/dashboard_screen.dart
// DashboardScreen — FINAL CLEAN VERSION (NO LICENSE / NO TRIAL / NO ALERTS)
// -----------------------------------------------------------------------------
// • Dashboard مالي كامل
// • لا ترخيص
// • لا فترة تجريبية
// • لا SnackBars
// • تشغيل نظيف ومستقر
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

import '../widgets/profit_indicator.dart';
import '../widgets/monthly_pie_chart.dart';
import '../widgets/action_shortcut_button.dart';
import '../widgets/section_title.dart';
import '../widgets/quick_stats.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
/*Trial Start*/
  Future<bool> _canAddNewRepair() async {
    const maxFreeRepairs = 10;

    final db = await DBService.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs');

    final count = (result.first['cnt'] as int?) ?? 0;

    if (count >= maxFreeRepairs) {
      if (!mounted) return false;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🔒 انتهاء النسخة التجريبية'),
          content: const Text(
            'لقد وصلت إلى الحد الأقصى للنسخة التجريبية (10 ملفات إصلاح).\n\n'
            'لتتمكن من إضافة مركبات جديدة، يرجى تفعيل الاشتراك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لاحقًا'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, AppRoutes.technicalSupport);
              },
              child: const Text('تواصل لتفعيل الاشتراك'),
            ),
          ],
        ),
      );

      return false;
    }

    return true;
  }

/* Trial End */

  bool _loading = true;

  double monthlyIncomeFiles = 0;
  double monthlyIncomePayments = 0;
  double monthlyExpensesPurchases = 0;
  double monthlyExpensesSalaries = 0;
  double monthlyExpensesOther = 0;

  double monthlyIncomeTotal = 0;
  double monthlyExpensesTotal = 0;
  double monthlyProfit = 0;
  double monthlyMargin = 0;

  late final String today;
  late final String startOfMonth;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    today = DateFormat('yyyy-MM-dd').format(now);
    startOfMonth = "${now.year}-${now.month.toString().padLeft(2, '0')}-01";

    _loadAll();
  }

  // ---------------------------------------------------------------------------
  // LOAD EVERYTHING
  // ---------------------------------------------------------------------------
  Future<void> _loadAll() async {
    setState(() => _loading = true);

    final db = await DBService.database;

    final now = DateTime.now();
    final monthStart = "${now.year}-${now.month.toString().padLeft(2, '0')}-01";

    monthlyIncomeFiles = await db.rawQuery(
      "SELECT SUM(fileValue + incomeAmount) AS total FROM repairs WHERE receivedDate >= ?",
      [monthStart],
    ).then((r) => (r.first["total"] as num? ?? 0).toDouble());

    monthlyIncomePayments = await db.rawQuery("""
      SELECT SUM(l.debit) AS total
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE DATE(e.date) >= ?
        AND a.code IN ('1000','1010')
    """, [monthStart]).then((r) => (r.first["total"] as num? ?? 0).toDouble());

    monthlyExpensesPurchases = await _sum(
      db,
      table: "purchase_invoices",
      column: "amount_total",
      where: "date >= ?",
      args: [monthStart],
    );

    monthlyExpensesSalaries = 0;

    monthlyExpensesOther = await db.rawQuery("""
      SELECT SUM(raw_materials + electricity + rent + other) AS total 
      FROM monthly_expenses 
      WHERE date >= ?
    """, [monthStart]).then((r) => (r.first["total"] as num? ?? 0).toDouble());

    monthlyIncomeTotal = monthlyIncomeFiles + monthlyIncomePayments;
    monthlyExpensesTotal = monthlyExpensesPurchases +
        monthlyExpensesSalaries +
        monthlyExpensesOther;

    monthlyProfit = monthlyIncomeTotal - monthlyExpensesTotal;
    monthlyMargin = monthlyIncomeTotal == 0
        ? 0
        : (monthlyProfit / monthlyIncomeTotal) * 100;

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // SUM HELPER
  // ---------------------------------------------------------------------------
  Future<double> _sum(
    db, {
    required String table,
    required String column,
    String? where,
    List<Object?>? args,
  }) async {
    final rows = await db.query(
      table,
      columns: ["SUM($column) AS total"],
      where: where,
      whereArgs: args,
    );

    final v = rows.first["total"];
    return v == null ? 0.0 : (v as num).toDouble();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),
      drawer: isDesktop ? null : const YallaSidebar(),
      body: Row(
        children: [
          if (isDesktop) const YallaSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const QuickStats(),
                        const SizedBox(height: 32),
                        _buildProfitAndShortcuts(),
                        const SizedBox(height: 32),
                        _buildMonthlyChart(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            blurRadius: 6,
            color: Colors.black.withOpacity(0.12),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text(
            "لوحة التحكم",
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROFIT + SHORTCUTS
  // ---------------------------------------------------------------------------
  Widget _buildProfitAndShortcuts() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 220,
            padding: const EdgeInsets.all(20),
            decoration: _boxStyle(),
            child: Center(
              child: ProfitIndicator(
                profit: monthlyProfit,
                margin: monthlyMargin,
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Container(
            height: 220,
            padding: const EdgeInsets.all(20),
            decoration: _boxStyle(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle("اختصارات سريعة"),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ActionShortcutButton(
                        label: "إضافة مركبة",
                        onTap: () async {
                          final allowed = await _canAddNewRepair();
                          if (!allowed) return;

                          if (!mounted) return;
                          Navigator.pushNamed(context, AppRoutes.repairsAdd);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionShortcutButton(
                        label: "فاتورة شراء",
                        onTap: () => Navigator.pushNamed(
                            context, AppRoutes.purchaseCreate),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionShortcutButton(
                        label: "سند قبض",
                        onTap: () => Navigator.pushNamed(
                            context, AppRoutes.receiptVoucher),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MONTHLY CHART
  // ---------------------------------------------------------------------------
  Widget _buildMonthlyChart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle("تحليل مالي شهري"),
        const SizedBox(height: 14),
        Container(
          height: 420,
          padding: const EdgeInsets.all(24),
          decoration: _boxStyle(),
          child: Row(
            children: [
              Expanded(
                child: MonthlyPieChart(
                  income: monthlyIncomeTotal,
                  expenses: monthlyExpensesTotal,
                  profit: monthlyProfit,
                ),
              ),
              Container(
                width: 1.2,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: Colors.black.withOpacity(0.08),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "الملخص المالي الشهري",
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _summaryLine(
                        "الدخل", monthlyIncomeTotal, AppColors.primary),
                    const SizedBox(height: 14),
                    _summaryLine("المصاريف", monthlyExpensesTotal,
                        const Color(0xFFFF9800)),
                    const SizedBox(height: 14),
                    _summaryLine(
                      monthlyProfit >= 0 ? "الربح" : "الخسارة",
                      monthlyProfit.abs(),
                      monthlyProfit >= 0 ? AppColors.success : AppColors.danger,
                    ),
                    const SizedBox(height: 14),
                    _summaryLine(
                      "هامش الربحية",
                      monthlyMargin,
                      AppColors.secondary,
                      percent: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY LINE
  // ---------------------------------------------------------------------------
  Widget _summaryLine(
    String title,
    double value,
    Color color, {
    bool percent = false,
  }) {
    final f = NumberFormat("#,###.##", "ar");
    final formatted =
        percent ? "${value.toStringAsFixed(2)}%" : f.format(value);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          formatted,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          "$title:",
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BOX STYLE
  // ---------------------------------------------------------------------------
  BoxDecoration _boxStyle() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
