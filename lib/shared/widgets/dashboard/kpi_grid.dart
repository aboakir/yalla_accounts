// 📁 lib/shared/widgets/dashboard/kpi_grid.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/shared/layouts/responsive_builder.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class KPIGrid extends StatefulWidget {
  const KPIGrid({super.key});

  @override
  State<KPIGrid> createState() => _KPIGridState();
}

class _KPIGridState extends State<KPIGrid> {
  late Future<List<KPIData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchKpiData();
  }

  @override
  Widget build(BuildContext context) {
    final device = context.deviceType();
    final crossAxisCount = switch (device) {
      DeviceType.desktop => 4,
      DeviceType.tablet => 2,
      DeviceType.mobile => 1,
    };

    return FutureBuilder<List<KPIData>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _KpiLoadingSkeleton();
        }

        if (snapshot.hasError) {
          return _KpiErrorState(
            message: 'تعذّر تحميل مؤشرات الأداء',
            details: snapshot.error.toString(),
            onRetry: () {
              setState(() => _future = _fetchKpiData());
            },
          );
        }

        final items = snapshot.data ?? const <KPIData>[];
        if (items.isEmpty) return const _KpiEmptyState();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, index) => _KpiCard(item: items[index]),
        );
      },
    );
  }

  Future<List<KPIData>> _fetchKpiData() async {
    final db = await DBService.database;

    // نطاق الشهر الحالي
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();

    // 1) عدد إصلاحات هذا الشهر (من جدول repairs بالعمود receivedDate)
    final repairsCount = await _countRepairsThisMonth(db, startIso, endIso);

    // 2) عدد العملاء (Distinct beneficiaryName من جدول repairs)
    final clientsCount = await _countUniqueClients(db);

    // 3) عدد الفواتير هذا الشهر (من جدول invoices)
    final invoicesCount = await _countInvoicesThisMonth(db, startIso, endIso);

    // 4) إجمالي الإيرادات هذا الشهر (SUM(total) من جدول invoices)
    final totalRevenue = await _sumInvoicesThisMonth(db, startIso, endIso);

    final compact = NumberFormat.compact(locale: 'ar');

    return [
      KPIData(
        title: 'إصلاحات هذا الشهر',
        value: compact.format(repairsCount),
        icon: Icons.build,
        color: AppColors.primary,
      ),
      KPIData(
        title: 'فواتير هذا الشهر',
        value: compact.format(invoicesCount),
        icon: Icons.receipt_long,
        color: Colors.orange,
      ),
      KPIData(
        title: 'عدد العملاء',
        value: compact.format(clientsCount),
        icon: Icons.people,
        color: Colors.teal,
      ),
      KPIData(
        title: 'الإيرادات',
        value: MoneyFormatter.format(totalRevenue),
        icon: Icons.attach_money,
        color: Colors.green,
      ),
    ];
  }

  // ===== SQL helpers (بدون الاعتماد على RepairDatabaseService) =====

  Future<int> _countRepairsThisMonth(
      Database db, String startIso, String endIso) async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM repairs WHERE receivedDate BETWEEN ? AND ?;",
      [startIso, endIso],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> _countUniqueClients(Database db) async {
    final rows = await db.rawQuery(
      "SELECT COUNT(DISTINCT beneficiaryName) AS c FROM repairs;",
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> _countInvoicesThisMonth(
      Database db, String startIso, String endIso) async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM invoices WHERE date BETWEEN ? AND ?;",
      [startIso, endIso],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<double> _sumInvoicesThisMonth(
      Database db, String startIso, String endIso) async {
    final rows = await db.rawQuery(
      "SELECT SUM(total) AS s FROM invoices WHERE date BETWEEN ? AND ?;",
      [startIso, endIso],
    );
    final v = rows.isNotEmpty ? rows.first['s'] : null;
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

class _KpiCard extends StatelessWidget {
  final KPIData item;
  const _KpiCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: item.color.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : item.color).withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: AdaptiveRow(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // أيقونة
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 26, color: item.color),
          ),

          // البيانات
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                builder: (context, value, _) => Opacity(
                  opacity: value,
                  child: Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: item.color,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiLoadingSkeleton extends StatelessWidget {
  const _KpiLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final device = context.deviceType();
    final crossAxisCount = switch (device) {
      DeviceType.desktop => 4,
      DeviceType.tablet => 2,
      DeviceType.mobile => 1,
    };

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: crossAxisCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[200]!;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: base),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: AdaptiveRow(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          _ShimmerBox(diameter: 46, isCircle: true),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ShimmerBox(width: 100, height: 12),
              SizedBox(height: 8),
              _ShimmerBox(width: 80, height: 18),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double diameter;
  final bool isCircle;

  const _ShimmerBox({
    this.width = 60,
    this.height = 16,
    this.diameter = 40,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[200]!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: isCircle ? diameter : width,
      height: isCircle ? diameter : height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(isCircle ? diameter : 6),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}

class _KpiErrorState extends StatelessWidget {
  final String message;
  final String? details;
  final VoidCallback onRetry;

  const _KpiErrorState({
    required this.message,
    this.details,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.redAccent : Colors.red).withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            message,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
            textAlign: TextAlign.right,
          ),
          if (details != null) ...[
            const SizedBox(height: 8),
            Text(
              details!,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.right,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiEmptyState extends StatelessWidget {
  const _KpiEmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
      ),
      child: const Center(
        child: Text(
          'لا توجد بيانات لعرضها حتى الآن.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class KPIData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const KPIData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
}
