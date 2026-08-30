// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/screens/purchases_dashboard_screen.dart
//
// Purchases Dashboard — v51 FINAL
// - يدعم purchase_invoices + purchase_invoice_lines + purchase_payments
// - يعتمد supplier_id + supplier_name
// - حساب total من الفاتورة (عمود total جاهز)
// - KPIs كاملة: مجموع آخر 30 يوم، عدد الفواتير، رصيد AP من GL
// - تفكيك حسب التصنيف من purchase_invoice_lines
// - واجهة عربية + متوافقة مع تصميم Yalla
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/finance/purchases/providers/purchase_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PurchasesDashboardScreen extends ConsumerStatefulWidget {
  const PurchasesDashboardScreen({super.key});

  @override
  ConsumerState<PurchasesDashboardScreen> createState() =>
      _PurchasesDashboardScreenState();
}

class _PurchasesDashboardScreenState
    extends ConsumerState<PurchasesDashboardScreen> {
  bool _loading = true;

  // KPIs
  double _sumLast30 = 0.0;
  int _count = 0;
  double _apBalance = 0.0;

  // Breakdown
  double _raw30 = 0.0;
  double _parts30 = 0.0;
  double _tools30 = 0.0;
  double _other30 = 0.0;

  @override
  void initState() {
    super.initState();
    ref.listen(purchaseProvider, (_, __) {
      _recalcFromProvider();
      if (mounted) setState(() {});
    });
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);

    await ref.read(purchaseProvider.notifier).loadAll();

    await Future.wait([
      _loadApFromGL(),
      _loadCategoryBreakdown30d(),
    ]);

    _recalcFromProvider();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadApFromGL() async {
    final db = await DBService.database;
    final rows = await db.rawQuery('''
      SELECT IFNULL(SUM(l.credit - l.debit), 0) AS total
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE l.party_type='SUPPLIER'
    ''');
    _apBalance = ((rows.first['total'] as num?) ?? 0).toDouble();
  }

  Future<void> _loadCategoryBreakdown30d() async {
    final db = await DBService.database;

    final sinceIso =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    final rows = await db.rawQuery('''
      SELECT pl.category, IFNULL(SUM(pl.total),0) AS total
      FROM purchase_invoice_lines pl
      JOIN purchase_invoices p ON p.id = pl.invoice_id
      WHERE p.date >= ?
      GROUP BY pl.category
    ''', [sinceIso]);

    double raw = 0, parts = 0, tools = 0, other = 0;

    for (final r in rows) {
      final cat = (r['category'] ?? '').toString().toUpperCase();
      final t = ((r['total'] as num?) ?? 0).toDouble();
      switch (cat) {
        case 'RAW':
          raw = t;
          break;
        case 'PARTS':
          parts = t;
          break;
        case 'TOOLS':
          tools = t;
          break;
        default:
          other = other + t;
      }
    }

    _raw30 = raw;
    _parts30 = parts;
    _tools30 = tools;
    _other30 = other;
  }

  void _recalcFromProvider() {
    final items = ref.read(purchaseProvider);

    _count = items.length;

    final since = DateTime.now().subtract(const Duration(days: 30));
    _sumLast30 = items
        .where((p) => p.date.isAfter(since))
        .fold<double>(0.0, (s, p) => s + p.total);
  }

  void _goList() => Navigator.of(context).pushNamed(AppRoutes.purchasesList);
  void _goCreate() =>
      Navigator.of(context).pushNamed(AppRoutes.purchaseCreate).then((_) {
        _reload();
      });
  void _goPayments() =>
      Navigator.of(context).pushNamed(AppRoutes.purchasePayments);
  void _goTools() => Navigator.of(context).pushNamed(AppRoutes.purchaseTools);
  void _goOther() => Navigator.of(context).pushNamed(AppRoutes.purchaseOther);
  void _goPaint() => Navigator.of(context).pushNamed(AppRoutes.purchasePaint);
  void _goInsurance() =>
      Navigator.of(context).pushNamed(AppRoutes.purchaseInsurance);
  void _goAging() =>
      Navigator.of(context).pushNamed(AppRoutes.purchasesSuppliersAging);
  void _goAudit() =>
      Navigator.of(context).pushNamed(AppRoutes.purchasesGLAudit);

  @override
  Widget build(BuildContext context) {
    final n = NumberFormat('#,##0.00', 'ar');
    final isDesktop = Responsive.isDesktop(context);

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _KpiCard(
                      title: 'مشتريات آخر 30 يوم',
                      value: n.format(_sumLast30),
                      icon: Icons.shopping_cart_outlined,
                      color: AppColors.primary,
                    ),
                    _KpiCard(
                      title: 'عدد الفواتير',
                      value: '$_count',
                      icon: Icons.receipt_long,
                      color: AppColors.primary,
                    ),
                    _KpiCard(
                      title: 'رصيد ذمم الموردين',
                      subtitle: 'من الدفتر العام',
                      value: n.format(_apBalance),
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MiniKpiChip(label: 'مواد خام', value: n.format(_raw30)),
                    _MiniKpiChip(label: 'قطع', value: n.format(_parts30)),
                    _MiniKpiChip(label: 'عدة', value: n.format(_tools30)),
                    _MiniKpiChip(label: 'أخرى', value: n.format(_other30)),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _QuickButton(
                          label: 'قائمة المشتريات',
                          icon: Icons.list_alt,
                          onTap: _goList),
                      _QuickButton(
                          label: 'عملية جديدة',
                          icon: Icons.add,
                          onTap: _goCreate,
                          filled: true),
                      _QuickButton(
                          label: 'مدفوعات',
                          icon: Icons.payments_outlined,
                          onTap: _goPayments),
                      _QuickButton(
                          label: 'أعمار الموردين',
                          icon: Icons.timeline_outlined,
                          onTap: _goAging),
                      _QuickButton(
                          label: 'تدقيق القيود',
                          icon: Icons.fact_check_outlined,
                          onTap: _goAudit),
                      _QuickButton(
                          label: 'دهان', icon: Icons.brush, onTap: _goPaint),
                      _QuickButton(
                          label: 'تأمين',
                          icon: Icons.verified_user_outlined,
                          onTap: _goInsurance),
                      _QuickButton(
                          label: 'أخرى',
                          icon: Icons.category_outlined,
                          onTap: _goOther),
                      _QuickButton(
                          label: 'أدوات', icon: Icons.build, onTap: _goTools),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: _SummaryBlock(),
                  ),
                ),
                if (!isDesktop) const SizedBox(height: 80),
              ],
            ),
          );

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/purchases/dashboard')),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('المشتريات', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
                width: 260,
                child: YallaSidebar(currentRoute: '/purchases/dashboard')),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goCreate,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// UI WIDGETS -------------------------------------------------------

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final String? subtitle;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: color.withOpacity(0.10),
          ),
          child: AdaptiveRow(
            children: [
              CircleAvatar(
                backgroundColor: color,
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      value,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniKpiChip extends StatelessWidget {
  final String label;
  final String value;

  const _MiniKpiChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(value),
        ],
      ),
      side: const BorderSide(color: AppColors.primary),
      backgroundColor: AppColors.primary.withOpacity(.08),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _QuickButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = AdaptiveRow(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18),
      const SizedBox(width: 6),
      Text(label),
    ]);

    if (filled) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: child,
      );
    }
    return OutlinedButton(onPressed: onTap, child: child);
  }
}

class _SummaryBlock extends ConsumerWidget {
  const _SummaryBlock();

  static final DateFormat _df = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(purchaseProvider);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('لا توجد مشتريات بعد',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('آخر 10 مشتريات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {
            0: FixedColumnWidth(120),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(140),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            const TableRow(
              children: [
                Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('التاريخ',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('المورد',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('المبلغ',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...items.take(10).map((p) {
              return TableRow(children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(_df.format(p.date)),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(p.supplierId.toString() ?? '-'),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(MoneyFormatter.format(p.total)),
                ),
              ]);
            }),
          ],
        ),
      ],
    );
  }
}
