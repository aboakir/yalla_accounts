import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import '../widgets/action_shortcut_button.dart';
import '../widgets/monthly_pie_chart.dart';
import '../widgets/profit_indicator.dart';
import '../widgets/quick_stats.dart';
import '../widgets/section_title.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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

  int repairCount = 0;
  int readyRepairCount = 0;
  double repairFilesValue = 0;
  double repairPaid = 0;
  double repairRemaining = 0;

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

  Future<bool> _canAddNewRepair() async {
    const maxFreeRepairs = 10;
    final db = await DBService.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs');
    final count = (result.first['cnt'] as int?) ?? 0;
    if (count >= maxFreeRepairs) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
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

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
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

    final repairSummary = await db.rawQuery("""
      SELECT
        COUNT(*) AS cnt,
        COALESCE(SUM(fileValue + incomeAmount), 0) AS total
      FROM repairs
    """);
    repairCount = (repairSummary.first['cnt'] as num? ?? 0).toInt();
    repairFilesValue = (repairSummary.first['total'] as num? ?? 0).toDouble();

    // M1 intentionally does not invent accounting semantics.
    // Paid/ready values will be wired to the authoritative repair fields in M2.
    repairPaid = 0;
    repairRemaining = repairFilesValue;
    readyRepairCount = 0;

    if (mounted) setState(() => _loading = false);
  }

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

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return isPhone ? _buildPhoneDashboard() : _buildLegacyDashboard();
  }

  Widget _buildPhoneDashboard() {
    final money = NumberFormat('#,##0.##');
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const Drawer(
        child: SafeArea(
          child: YallaSidebar(currentRoute: AppRoutes.dashboard),
        ),
      ),
      body: SafeArea(
        child: Builder(
          builder: (scaffoldContext) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadAll,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _phoneHeader(scaffoldContext)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Row(
                        children: [
                          Expanded(
                            child: _kpiCard(
                              'ملفات مفتوحة',
                              '$repairCount',
                              Icons.folder_open_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _kpiCard(
                              'جاهزة للتسليم',
                              '$readyRepairCount',
                              Icons.task_alt_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _kpiCard(
                              'إجمالي الملفات',
                              '₪ ${money.format(repairFilesValue)}',
                              Icons.receipt_long_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _kpiCard(
                              'متبقي للتحصيل',
                              '₪ ${money.format(repairRemaining)}',
                              Icons.account_balance_wallet_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _sectionHeader('إجراءات سريعة',
                          trailing: 'الأكثر استخدامًا'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _quickAction(
                              icon: Icons.directions_car_filled_rounded,
                              label: 'ملفات الإصلاح',
                              onTap: () => Navigator.pushNamed(
                                context,
                                AppRoutes.repairs,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _quickAction(
                              icon: Icons.add_rounded,
                              label: 'ملف جديد',
                              onTap: () async {
                                if (!await _canAddNewRepair() || !mounted) {
                                  return;
                                }
                                Navigator.pushNamed(
                                    context, AppRoutes.repairsAdd);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _quickAction(
                              icon: Icons.payments_outlined,
                              label: 'تحصيل دفعة',
                              onTap: () => Navigator.pushNamed(
                                context,
                                AppRoutes.receiptVoucher,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _collectionCard(money),
                      const SizedBox(height: 26),
                      _sectionHeader(
                        'آخر الملفات',
                        action: TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, AppRoutes.repairs),
                          child: const Text('عرض الكل'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _recentRepairPlaceholder(),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (navContext) => YallaMobileBottomNav(
          currentRoute: AppRoutes.dashboard,
          onMore: () => Scaffold.of(navContext).openDrawer(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          if (!await _canAddNewRepair() || !mounted) {
            return;
          }
          Navigator.pushNamed(context, AppRoutes.repairsAdd);
        },
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _phoneHeader(BuildContext scaffoldContext) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('yalla_mobile_menu_button'),
            tooltip: 'القائمة',
            onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'YALLA ACCOUNTS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: .8,
                  ),
                ),
                Text(
                  'لوحة التحكم',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(16),
      decoration: _phoneCardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const Spacer(),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Directionality(
            textDirection: ui.TextDirection.ltr,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 104,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightGrey),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collectionCard(NumberFormat money) {
    final pct = repairFilesValue <= 0
        ? 0.0
        : (repairPaid / repairFilesValue * 100).clamp(0, 100).toDouble();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _phoneCardStyle(),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'حالة التحصيل',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'نسبة المدفوع من الملفات',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          LinearProgressIndicator(
            value: pct / 100,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: AppColors.lightGrey,
            color: AppColors.primary,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                  child: _miniValue('مدفوع', '₪ ${money.format(repairPaid)}')),
              Expanded(
                  child: _miniValue(
                      'متبقي', '₪ ${money.format(repairRemaining)}')),
              Expanded(child: _miniValue('ملف', '$repairCount')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniValue(String label, String value) {
    return Column(
      children: [
        Directionality(
          textDirection: ui.TextDirection.ltr,
          child: Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  Widget _recentRepairPlaceholder() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.pushNamed(context, AppRoutes.repairs),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightGrey),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  repairCount == 0
                      ? 'لا توجد ملفات إصلاح بعد'
                      : 'لديك $repairCount ملف إصلاح — افتح القائمة لعرض التفاصيل',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? trailing, Widget? action}) {
    return Row(
      children: [
        if (action != null)
          action
        else if (trailing != null)
          Text(trailing, style: const TextStyle(color: Colors.black54)),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  BoxDecoration _phoneCardStyle() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.lightGrey),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.035),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // Existing tablet/desktop dashboard is preserved.
  Widget _buildLegacyDashboard() {
    final isDesktop = context.isDesktopWidth;
    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),
      drawer: isDesktop
          ? null
          : const Drawer(
              child: SafeArea(
                child: YallaSidebar(currentRoute: AppRoutes.dashboard),
              ),
            ),
      body: SafeArea(
        child: AdaptiveRow(
          children: [
            if (isDesktop)
              const SizedBox(
                width: 300,
                child: YallaSidebar(currentRoute: AppRoutes.dashboard),
              ),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(isDesktop),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 20,
                      ),
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
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
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
      child: AdaptiveRow(
        children: [
          Expanded(
            child: AdaptiveRow(
              children: [
                if (!isDesktop)
                  Builder(
                    builder: (headerContext) => IconButton(
                      key: const Key('yalla_mobile_menu_button'),
                      tooltip: 'القائمة',
                      onPressed: () => Scaffold.of(headerContext).openDrawer(),
                      icon: const Icon(Icons.menu, color: Colors.white),
                    ),
                  ),
                const Text(
                  "لوحة التحكم",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitAndShortcuts() {
    return AdaptiveRow(
      children: [
        Expanded(
          child: Container(
            height: 220,
            padding: const EdgeInsets.all(20),
            decoration: _boxStyle(),
            child: Center(
              child:
                  ProfitIndicator(profit: monthlyProfit, margin: monthlyMargin),
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
                AdaptiveRow(
                  children: [
                    Expanded(
                      child: ActionShortcutButton(
                        label: "إضافة مركبة",
                        onTap: () async {
                          final allowed = await _canAddNewRepair();
                          if (!allowed || !mounted) return;
                          Navigator.pushNamed(context, AppRoutes.repairsAdd);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionShortcutButton(
                        label: "فاتورة شراء",
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.purchaseCreate,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionShortcutButton(
                        label: "سند قبض",
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.receiptVoucher,
                        ),
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
          child: AdaptiveRow(
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
                    _summaryLine(
                      "المصاريف",
                      monthlyExpensesTotal,
                      const Color(0xFFFF9800),
                    ),
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

  Widget _summaryLine(
    String title,
    double value,
    Color color, {
    bool percent = false,
  }) {
    final f = NumberFormat("#,###.##", "ar");
    final formatted =
        percent ? "${value.toStringAsFixed(2)}%" : f.format(value);
    return AdaptiveRow(
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
