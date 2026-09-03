import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import '../services/p03_home_service.dart';
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
  P03HomeSnapshot? _phoneSnapshot;

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
    const maxFreeRepairs = 1000000000; // TEMP DEV BYPASS UNTIL P18
    final db = await DBService.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs');
    final count = (result.first['cnt'] as int?) ?? 0;
    if (count >= maxFreeRepairs) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title:
              const Text('ًں”’ ط§ظ†طھظ‡ط§ط، ط§ظ„ظ†ط³ط®ط© ط§ظ„طھط¬ط±ظٹط¨ظٹط©'),
          content: const Text(
            'ظ„ظ‚ط¯ ظˆطµظ„طھ ط¥ظ„ظ‰ ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ظ„ظ„ظ†ط³ط®ط© ط§ظ„طھط¬ط±ظٹط¨ظٹط© (10 ظ…ظ„ظپط§طھ ط¥طµظ„ط§ط­).\n\n'
            'ظ„طھطھظ…ظƒظ† ظ…ظ† ط¥ط¶ط§ظپط© ظ…ط±ظƒط¨ط§طھ ط¬ط¯ظٹط¯ط©طŒ ظٹط±ط¬ظ‰ طھظپط¹ظٹظ„ ط§ظ„ط§ط´طھط±ط§ظƒ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ظ„ط§ط­ظ‚ظ‹ط§'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, AppRoutes.technicalSupport);
              },
              child: const Text('طھظˆط§طµظ„ ظ„طھظپط¹ظٹظ„ ط§ظ„ط§ط´طھط±ط§ظƒ'),
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

    _phoneSnapshot = await P03HomeService.load();

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
    final snapshot = _phoneSnapshot ??
        const P03HomeSnapshot(
          workshopName: 'ظˆط±ط´طھظٹ',
          currencySymbol: 'â‚ھ',
          repairsReceivedToday: 0,
          receiptsToday: 0,
          paymentsToday: 0,
          chequesDueToday: 0,
          attentionCount: 0,
          attention: <P03AttentionItem>[],
          recentRepairs: <P03RecentRepair>[],
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const Drawer(
        child: SafeArea(
          child: YallaSidebar(currentRoute: AppRoutes.dashboard),
        ),
      ),
      body: SafeArea(
        child: Builder(
          builder: (headerContext) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadAll,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _phoneHeader(headerContext, snapshot),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _todaySummary(snapshot),
                      const SizedBox(height: 22),
                      _attentionSection(snapshot),
                      const SizedBox(height: 24),
                      _sectionHeader(
                        'ط¥ط¬ط±ط§ط،ط§طھ ط³ط±ظٹط¹ط©',
                        trailing: 'ط§ظ„ط£ظƒط«ط± ط§ط³طھط®ط¯ط§ظ…ظ‹ط§',
                      ),
                      const SizedBox(height: 12),
                      _quickActionsGrid(),
                      const SizedBox(height: 26),
                      _sectionHeader(
                        'ط¢ط®ط± ط§ظ„ظ…ظ„ظپط§طھ',
                        action: TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, AppRoutes.repairs),
                          child: const Text('ط¹ط±ط¶ ط§ظ„ظƒظ„'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _recentRepairs(snapshot),
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
    );
  }

  Widget _phoneHeader(
    BuildContext headerContext,
    P03HomeSnapshot snapshot,
  ) {
    final greeting = DateTime.now().hour < 12
        ? 'طµط¨ط§ط­ ط§ظ„ط®ظٹط±'
        : DateTime.now().hour < 18
            ? 'ظ…ط³ط§ط، ط§ظ„ط®ظٹط±'
            : 'ط£ظ‡ظ„ظ‹ط§ ط¨ظƒ';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 16),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: AdaptiveRow(
        children: [
          IconButton(
            key: const Key('yalla_mobile_menu_button'),
            tooltip: 'ط§ظ„ظ‚ط§ط¦ظ…ط©',
            onPressed: () => Scaffold.of(headerContext).openDrawer(),
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snapshot.workshopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                key: const Key('yalla_home_notifications_button'),
                tooltip: 'ط§ظ„طھظ†ط¨ظٹظ‡ط§طھ',
                onPressed: () => _showNotificationCenter(snapshot),
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                ),
              ),
              if (snapshot.attentionCount > 0)
                PositionedDirectional(
                  top: 3,
                  end: 2,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      snapshot.attentionCount > 99
                          ? '99+'
                          : '${snapshot.attentionCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todaySummary(P03HomeSnapshot snapshot) {
    final money = NumberFormat('#,##0.##');
    final net = snapshot.netCashToday;
    final netLabel = '${snapshot.currencySymbol} ${money.format(net.abs())}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _phoneCardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdaptiveRow(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.today_rounded,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'ظ…ظ„ط®طµ ط§ظ„ظٹظˆظ…',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'ظ…ط§ ظٹط­طھط§ط¬ ط£ظ† طھط¹ط±ظپظ‡ ط§ظ„ط¢ظ†',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            net >= 0
                ? 'طµط§ظپظٹ ط­ط±ظƒط© ط§ظ„ظ†ظ‚ط¯ ط§ظ„ظٹظˆظ…'
                : 'طµط§ظپظٹ ط§ظ„طµط±ظپ ط£ط¹ظ„ظ‰ ط§ظ„ظٹظˆظ…',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            net >= 0 ? netLabel : '- $netLabel',
            textAlign: TextAlign.right,
            textDirection: ui.TextDirection.ltr,
            style: TextStyle(
              color: net >= 0 ? AppColors.primary : AppColors.danger,
              fontSize: 31,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          AdaptiveRow(
            children: [
              Expanded(
                child: _todayMetric(
                  'ظ…ظ„ظپط§طھ ط¯ط®ظ„طھ ط§ظ„ظٹظˆظ…',
                  '${snapshot.repairsReceivedToday}',
                  Icons.car_repair_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _todayMetric(
                  'ظ‚ط¨ط¶ ط§ظ„ظٹظˆظ…',
                  '${snapshot.currencySymbol} ${money.format(snapshot.receiptsToday)}',
                  Icons.south_west_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AdaptiveRow(
            children: [
              Expanded(
                child: _todayMetric(
                  'طµط±ظپ ط§ظ„ظٹظˆظ…',
                  '${snapshot.currencySymbol} ${money.format(snapshot.paymentsToday)}',
                  Icons.north_east_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _todayMetric(
                  'ط´ظٹظƒط§طھ ط§ظ„ظٹظˆظ…',
                  '${snapshot.chequesDueToday}',
                  Icons.event_available_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todayMetric(String label, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: ui.TextDirection.ltr,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textDark,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _attentionSection(P03HomeSnapshot snapshot) {
    final visible = snapshot.attention.take(3).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'ظٹط­طھط§ط¬ ط§ظ†طھط¨ط§ظ‡ظƒ',
          trailing: snapshot.attentionCount == 0
              ? 'ظ„ط§ ظٹظˆط¬ط¯ ط¹ط§ط¬ظ„'
              : '${snapshot.attentionCount} ط¹ظ†طµط±',
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.lightGreen.withOpacity(.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(.18)),
            ),
            child: const Text(
              'ظ„ط§ طھظˆط¬ط¯ ط¹ظ†ط§طµط± ط¹ط§ط¬ظ„ط© ط§ظ„ط¢ظ†.',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        else
          ...visible.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _attentionTile(item, snapshot.currencySymbol),
            ),
          ),
      ],
    );
  }

  Widget _attentionTile(
    P03AttentionItem item,
    String currencySymbol, {
    VoidCallback? onTap,
  }) {
    final money = NumberFormat('#,##0.##');
    final isCheque = item.kind != P03AttentionKind.staleUnpaidRepair;
    final isOverdue = item.kind == P03AttentionKind.overdueCheque;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap ?? () => _openAttention(item),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isOverdue
                  ? AppColors.danger.withOpacity(.35)
                  : AppColors.lightGrey,
            ),
          ),
          child: AdaptiveRow(
            children: [
              Icon(
                isCheque
                    ? Icons.account_balance_wallet_outlined
                    : Icons.car_repair_outlined,
                color: isOverdue ? AppColors.danger : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.title,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.amount != null) ...[
                const SizedBox(width: 10),
                Text(
                  '$currencySymbol ${money.format(item.amount)}',
                  textDirection: ui.TextDirection.ltr,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(Icons.chevron_left_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _openAttention(P03AttentionItem item) {
    final isCheque = item.kind != P03AttentionKind.staleUnpaidRepair;
    Navigator.pushNamed(
      context,
      isCheque ? AppRoutes.chequesDashboard : AppRoutes.repairs,
    );
  }

  Widget _quickActionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.75,
      children: [
        _quickAction(
          icon: Icons.add_road_rounded,
          label: 'ط¥طµظ„ط§ط­ ط¬ط¯ظٹط¯',
          onTap: _openNewRepair,
        ),
        _quickAction(
          icon: Icons.payments_outlined,
          label: 'ط³ظ†ط¯ ظ‚ط¨ط¶',
          onTap: () => Navigator.pushNamed(context, AppRoutes.receiptVoucher),
        ),
        _quickAction(
          icon: Icons.person_add_alt_1_rounded,
          label: 'ط¥ط¶ط§ظپط© ط¹ظ…ظٹظ„',
          onTap: () => Navigator.pushNamed(context, AppRoutes.clientAdd),
        ),
        _quickAction(
          icon: Icons.edit_calendar_rounded,
          label: 'ط¥ط¶ط§ظپط© ط´ظٹظƒ',
          onTap: () => Navigator.pushNamed(context, AppRoutes.chequesAdd),
        ),
      ],
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightGrey),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 27),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentRepairs(P03HomeSnapshot snapshot) {
    if (snapshot.recentRepairs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _phoneCardStyle(),
        child: const Text(
          'ظ„ط§ طھظˆط¬ط¯ ظ…ظ„ظپط§طھ ط¥طµظ„ط§ط­ ط¨ط¹ط¯.',
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }

    return Container(
      decoration: _phoneCardStyle(),
      child: Column(
        children: [
          for (var index = 0;
              index < snapshot.recentRepairs.length;
              index++) ...[
            _recentRepairTile(snapshot.recentRepairs[index]),
            if (index < snapshot.recentRepairs.length - 1)
              const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _recentRepairTile(P03RecentRepair repair) {
    final displayDate =
        repair.date.length >= 10 ? repair.date.substring(0, 10) : repair.date;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      onTap: () => _openRepair(repair.id),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(
          Icons.directions_car_filled_rounded,
          color: AppColors.primary,
        ),
      ),
      title: Text(
        repair.title,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        [
          repair.subtitle,
          if (repair.status.isNotEmpty) repair.status,
          if (displayDate.isNotEmpty) displayDate,
        ].join(' â€¢ '),
        textAlign: TextAlign.right,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_left_rounded),
    );
  }

  Future<void> _openRepair(String id) async {
    final repair = await RepairDatabaseService.getRepairById(id);
    if (!mounted) return;
    if (repair == null) {
      Navigator.pushNamed(context, AppRoutes.repairs);
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.repairDetail,
      arguments: repair,
    );
  }

  Future<void> _openNewRepair() async {
    if (!await _canAddNewRepair() || !mounted) return;
    Navigator.pushNamed(context, AppRoutes.repairsAdd);
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'ط¥ط¶ط§ظپط© ط¬ط¯ظٹط¯ط©',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            _addSheetTile(
              sheetContext,
              icon: Icons.add_road_rounded,
              title: 'ط¥طµظ„ط§ط­ ط¬ط¯ظٹط¯',
              onOpen: _openNewRepair,
            ),
            _addSheetTile(
              sheetContext,
              icon: Icons.payments_outlined,
              title: 'ط³ظ†ط¯ ظ‚ط¨ط¶',
              route: AppRoutes.receiptVoucher,
            ),
            _addSheetTile(
              sheetContext,
              icon: Icons.person_add_alt_1_rounded,
              title: 'ط¥ط¶ط§ظپط© ط¹ظ…ظٹظ„',
              route: AppRoutes.clientAdd,
            ),
            _addSheetTile(
              sheetContext,
              icon: Icons.edit_calendar_rounded,
              title: 'ط¥ط¶ط§ظپط© ط´ظٹظƒ',
              route: AppRoutes.chequesAdd,
            ),
          ],
        ),
      ),
    );
  }

  Widget _addSheetTile(
    BuildContext sheetContext, {
    required IconData icon,
    required String title,
    String? route,
    Future<void> Function()? onOpen,
  }) {
    return ListTile(
      minTileHeight: 54,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        title,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: () {
        Navigator.pop(sheetContext);
        if (onOpen != null) {
          onOpen();
        } else if (route != null) {
          Navigator.pushNamed(context, route);
        }
      },
    );
  }

  void _showNotificationCenter(P03HomeSnapshot snapshot) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdaptiveRow(
                children: [
                  Text(
                    snapshot.attentionCount == 0
                        ? 'ظ„ط§ ظٹظˆط¬ط¯ ط¬ط¯ظٹط¯'
                        : '${snapshot.attentionCount} ظٹط­طھط§ط¬ ظ…طھط§ط¨ط¹ط©',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const Spacer(),
                  const Text(
                    'ط§ظ„طھظ†ط¨ظٹظ‡ط§طھ',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: snapshot.attention.isEmpty
                    ? const Center(
                        child: Text(
                          'ظ„ط§ طھظˆط¬ط¯ ط¹ظ†ط§طµط± ط¹ط§ط¬ظ„ط© ط§ظ„ط¢ظ†.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )
                    : ListView.separated(
                        itemCount: snapshot.attention.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final item = snapshot.attention[index];
                          return _attentionTile(
                            item,
                            snapshot.currencySymbol,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _openAttention(item);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(
    String title, {
    String? trailing,
    Widget? action,
  }) {
    return AdaptiveRow(
      children: [
        if (action != null)
          action
        else if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(color: Colors.black54),
          ),
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
                      tooltip: 'ط§ظ„ظ‚ط§ط¦ظ…ط©',
                      onPressed: () => Scaffold.of(headerContext).openDrawer(),
                      icon: const Icon(Icons.menu, color: Colors.white),
                    ),
                  ),
                const Text(
                  "ظ„ظˆط­ط© ط§ظ„طھط­ظƒظ…",
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
            constraints: const BoxConstraints(minHeight: 220),
            padding: const EdgeInsets.all(20),
            decoration: _boxStyle(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle("ط§ط®طھطµط§ط±ط§طھ ط³ط±ظٹط¹ط©"),
                const SizedBox(height: 14),
                AdaptiveRow(
                  children: [
                    Expanded(
                      child: ActionShortcutButton(
                        label: "ط¥ط¶ط§ظپط© ظ…ط±ظƒط¨ط©",
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
                        label: "ظپط§طھظˆط±ط© ط´ط±ط§ط،",
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.purchaseCreate,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionShortcutButton(
                        label: "ط³ظ†ط¯ ظ‚ط¨ط¶",
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
        const SectionTitle("طھط­ظ„ظٹظ„ ظ…ط§ظ„ظٹ ط´ظ‡ط±ظٹ"),
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
                      "ط§ظ„ظ…ظ„ط®طµ ط§ظ„ظ…ط§ظ„ظٹ ط§ظ„ط´ظ‡ط±ظٹ",
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _summaryLine(
                        "ط§ظ„ط¯ط®ظ„", monthlyIncomeTotal, AppColors.primary),
                    const SizedBox(height: 14),
                    _summaryLine(
                      "ط§ظ„ظ…طµط§ط±ظٹظپ",
                      monthlyExpensesTotal,
                      const Color(0xFFFF9800),
                    ),
                    const SizedBox(height: 14),
                    _summaryLine(
                      monthlyProfit >= 0 ? "ط§ظ„ط±ط¨ط­" : "ط§ظ„ط®ط³ط§ط±ط©",
                      monthlyProfit.abs(),
                      monthlyProfit >= 0 ? AppColors.success : AppColors.danger,
                    ),
                    const SizedBox(height: 14),
                    _summaryLine(
                      "ظ‡ط§ظ…ط´ ط§ظ„ط±ط¨ط­ظٹط©",
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
