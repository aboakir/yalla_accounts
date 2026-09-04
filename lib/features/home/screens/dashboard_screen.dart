import 'dart:io';
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
          workshopName: 'ورشتي',
          currencySymbol: '₪',
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
                    child: _phoneHeader(headerContext, snapshot)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _todaySummary(snapshot),
                      const SizedBox(height: 16),
                      _attentionSection(snapshot),
                      const SizedBox(height: 18),
                      _sectionHeader('إجراءات سريعة'),
                      const SizedBox(height: 8),
                      _quickActionsGrid(),
                      const SizedBox(height: 20),
                      _sectionHeader(
                        'آخر الملفات',
                        action: TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, AppRoutes.repairs),
                          child: const Text('عرض الكل'),
                        ),
                      ),
                      const SizedBox(height: 8),
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
        ? 'صباح الخير'
        : DateTime.now().hour < 18
            ? 'مساء الخير'
            : 'أهلًا بك';

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
            tooltip: 'القائمة',
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
                tooltip: 'التنبيهات',
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _phoneCardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.today_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('ملخص اليوم',
                    textAlign: TextAlign.right,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              Text(
                '${net < 0 ? '-' : ''}${snapshot.currencySymbol} ${money.format(net.abs())}',
                textDirection: ui.TextDirection.ltr,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: net > 0
                      ? AppColors.success
                      : net < 0
                          ? AppColors.danger
                          : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _todayMetric(
                      'ملفات دخلت',
                      '${snapshot.repairsReceivedToday}',
                      Icons.car_repair_rounded,
                      AppColors.primary)),
              const SizedBox(width: 7),
              Expanded(
                  child: _todayMetric(
                      'قبض',
                      '${snapshot.currencySymbol} ${money.format(snapshot.receiptsToday)}',
                      Icons.south_west_rounded,
                      AppColors.success)),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                  child: _todayMetric(
                      'صرف',
                      '${snapshot.currencySymbol} ${money.format(snapshot.paymentsToday)}',
                      Icons.north_east_rounded,
                      AppColors.danger)),
              const SizedBox(width: 7),
              Expanded(
                  child: _todayMetric('شيكات', '${snapshot.chequesDueToday}',
                      Icons.event_available_rounded, AppColors.info)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todayMetric(String label, String value, IconData icon, Color color) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: ui.TextDirection.ltr,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 10.5)),
              ],
            ),
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
          'يحتاج انتباهك',
          trailing: snapshot.attentionCount == 0
              ? 'لا يوجد عاجل'
              : '${snapshot.attentionCount} عنصر',
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
              'لا توجد عناصر عاجلة الآن.',
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
    final reason = item.kind == P03AttentionKind.staleUnpaidRepair
        ? 'لا توجد دفعة حديثة على هذا الملف — افتحه للمراجعة'
        : isOverdue
            ? 'موعد الشيك متأخر — راجع التحصيل الآن'
            : 'شيك يحتاج متابعة — راجع موعد الاستحقاق';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap ?? () => _openAttention(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: isOverdue
                    ? AppColors.danger.withOpacity(.35)
                    : AppColors.lightGrey),
          ),
          child: Row(
            children: [
              Icon(
                  isCheque
                      ? Icons.account_balance_wallet_outlined
                      : Icons.car_repair_outlined,
                  color: isOverdue ? AppColors.danger : AppColors.primary,
                  size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(item.title,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color:
                                isOverdue ? AppColors.danger : Colors.black87)),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.black45, fontSize: 10.5)),
                    ],
                  ],
                ),
              ),
              if (item.amount != null) ...[
                const SizedBox(width: 8),
                Text('$currencySymbol ${money.format(item.amount)}',
                    textDirection: ui.TextDirection.ltr,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 12)),
              ],
              const Icon(Icons.chevron_left_rounded, size: 18),
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
    return Row(
      children: [
        Expanded(
            child: _quickAction(
                icon: Icons.add_road_rounded,
                label: 'إصلاح',
                onTap: _openNewRepair)),
        const SizedBox(width: 7),
        Expanded(
            child: _quickAction(
                icon: Icons.payments_outlined,
                label: 'قبض',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.receiptVoucher))),
        const SizedBox(width: 7),
        Expanded(
            child: _quickAction(
                icon: Icons.person_add_alt_1_rounded,
                label: 'عميل',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.clientAdd))),
        const SizedBox(width: 7),
        Expanded(
            child: _quickAction(
                icon: Icons.edit_calendar_rounded,
                label: 'شيك',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.chequesAdd))),
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightGrey),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 11.5)),
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
          'لا توجد ملفات إصلاح بعد.',
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

  Widget _recentRepairImageFallback() {
    return Container(
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
    );
  }

  Widget _recentRepairTile(P03RecentRepair repair) {
    final displayDate =
        repair.date.length >= 10 ? repair.date.substring(0, 10) : repair.date;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      onTap: () => _openRepair(repair.id),
      leading: FutureBuilder<String?>(
        future: DBService.getRepairThumbnailPath(repair.id),
        builder: (context, snapshot) {
          final profilePath = snapshot.data?.trim();

          if (profilePath != null &&
              profilePath.isNotEmpty &&
              File(profilePath).existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.file(
                File(profilePath),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                cacheWidth: 180,
                errorBuilder: (_, __, ___) => _recentRepairImageFallback(),
              ),
            );
          }

          return _recentRepairImageFallback();
        },
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
        ].join(' • '),
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
                'إضافة جديدة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            _addSheetTile(
              sheetContext,
              icon: Icons.add_road_rounded,
              title: 'إصلاح جديد',
              onOpen: _openNewRepair,
            ),
            _addSheetTile(
              sheetContext,
              icon: Icons.payments_outlined,
              title: 'سند قبض',
              route: AppRoutes.receiptVoucher,
            ),
            _addSheetTile(
              sheetContext,
              icon: Icons.person_add_alt_1_rounded,
              title: 'إضافة عميل',
              route: AppRoutes.clientAdd,
            ),
            _addSheetTile(
              sheetContext,
              icon: Icons.edit_calendar_rounded,
              title: 'إضافة شيك',
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
                        ? 'لا يوجد جديد'
                        : '${snapshot.attentionCount} يحتاج متابعة',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const Spacer(),
                  const Text(
                    'التنبيهات',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: snapshot.attention.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد عناصر عاجلة الآن.',
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
