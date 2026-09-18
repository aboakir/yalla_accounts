import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  String? _error;
  List<_ExpenseRow> _rows = const [];
  double _total = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await DBService.database;
      final totals = await FinancialOverviewService.accountTotalsOn(
        db,
        from: _from,
        to: _to,
      );
      final rows = <_ExpenseRow>[];
      var total = 0.0;
      for (final row in totals) {
        final code = (row['code'] ?? '').toString();
        final type = (row['type'] ?? '').toString().toUpperCase();
        if (type != 'EXPENSE' && !code.startsWith('5')) continue;
        final debit = _d(row['debit']);
        final credit = _d(row['credit']);
        final amount = _round(debit - credit);
        if (amount.abs() < 0.005) continue;
        rows.add(_ExpenseRow(
          code: code,
          name: (row['name'] ?? '').toString(),
          amount: amount,
        ));
        total += amount;
      }
      rows.sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _total = _round(total);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  double _round(double value) => double.parse(value.toStringAsFixed(2));

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('المصروفات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: desktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/finance/expenses')),
      body: AdaptiveRow(
        children: [
          if (desktop) const YallaSidebar(currentRoute: '/finance/expenses'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(error: _error!, retry: _load)
                    : _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FinancialPeriodFilter(
                from: _from,
                to: _to,
                onChanged: (range) {
                  setState(() {
                    _from = range.start;
                    _to = range.end;
                  });
                  _load();
                },
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamed(AppRoutes.paymentVoucher)
                    .then((_) => _load()),
                icon: const Icon(Icons.arrow_upward),
                label: const Text('سند صرف جديد'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamed(AppRoutes.paymentVouchersList),
                icon: const Icon(Icons.list_alt),
                label: const Text('قائمة سندات الصرف'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('إجمالي المصروفات',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          MoneyFormatter.format(_total),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text('${_rows.length} حساب مصروف نشط خلال الفترة'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'التفصيل حسب الحساب المحاسبي',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_rows.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child:
                    Center(child: Text('لا توجد مصروفات ضمن الفترة المحددة')),
              ),
            )
          else
            ..._rows.map(
              (row) => Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(row.name.isEmpty ? 'حساب ${row.code}' : row.name),
                  subtitle: Text('رقم الحساب ${row.code}'),
                  trailing: Text(
                    MoneyFormatter.format(row.amount),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'ملاحظة: يعرض هذا التقرير حسابات المصروف من دفتر الأستاذ. شراء المخزون لا يعد مصروفًا تلقائيًا ما لم تعالجه المحاسبة كمصروف.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow {
  const _ExpenseRow(
      {required this.code, required this.name, required this.amount});
  final String code;
  final String name;
  final double amount;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.retry});
  final String error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text('تعذر تحميل المصروفات: $error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: retry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}
