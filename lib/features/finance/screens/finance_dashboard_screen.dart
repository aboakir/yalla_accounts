import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  late DateTime _from;
  late DateTime _to;
  String _query = '';
  bool _loading = true;
  int _request = 0;
  String? _error;
  FinancialOverviewSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await FinancialOverviewService.load(
        from: _from,
        to: _to,
        query: _query,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(DateTime.now().year - 10, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (!mounted || d == null) return;
    setState(() => _from = d);
    await _load();
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(DateTime.now().year - 10, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      locale: const Locale('ar'),
    );
    if (!mounted || d == null) return;
    setState(() => _to = d);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: AdaptiveRow(
        children: [
          if (!isMobile) const YallaSidebar(currentRoute: '/finance/dashboard'),
          Expanded(
            child: Column(
              children: [
                _buildHeader(isMobile),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _ErrorView(error: _error!, onRetry: _load)
                          : _buildBody(_snapshot!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool mobile) {
    return Material(
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  if (mobile)
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                  const Expanded(
                    child: Text(
                      'النظرة المالية',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  _headerChip('من ${_df.format(_from)}', _pickFrom),
                  _headerChip('إلى ${_df.format(_to)}', _pickTo),
                  FinancialPeriodFilter(
                      from: _from,
                      to: _to,
                      onChanged: (range) {
                        setState(() {
                          _from = range.start;
                          _to = range.end;
                        });
                        _load();
                      }),
                  SizedBox(
                    width: mobile ? double.infinity : 260,
                    child: TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        hintText: 'بحث في الحركة والحسابات...',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (value) {
                        _query = value.trim();
                        _load();
                      },
                      onChanged: (value) => _query = value.trim(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.calendar_month, size: 18),
      onPressed: onTap,
    );
  }

  Widget _buildBody(FinancialOverviewSnapshot s) {
    final balanceCards = <_MetricData>[
      _MetricData('الصندوق', s.cashBalance, Icons.account_balance_wallet),
      _MetricData('البنك', s.bankBalance, Icons.account_balance),
      _MetricData('ذمم العملاء', s.customerReceivables, Icons.people_alt),
      _MetricData('ذمم الموردين', s.supplierPayables, Icons.local_shipping),
      _MetricData('رواتب مستحقة', s.payrollPayables, Icons.badge),
      _MetricData(
        'صافي ربح الفترة',
        s.netProfit,
        Icons.trending_up,
        emphasizeSign: true,
      ),
    ];

    final activityCards = <_MetricData>[
      _MetricData('إيرادات الفترة', s.revenue, Icons.south_west),
      _MetricData('مصروفات الفترة', s.expenses, Icons.north_east),
      _MetricData('المقبوضات النقدية والبنكية', s.receipts, Icons.south_west),
      _MetricData('المدفوعات النقدية والبنكية', s.payments, Icons.north_east),
      _MetricData('مقبوضات العملاء', s.collections, Icons.payments),
      _MetricData('مدفوع للموردين', s.supplierPayments, Icons.shopping_cart),
      _MetricData('رواتب مدفوعة', s.payrollPayments, Icons.price_check),
    ];

    return Container(
      color: const Color(0xfff7f9f4),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AsOfBanner(to: s.to),
            const SizedBox(height: 12),
            _MetricGrid(items: balanceCards, money: _money),
            if (s.customerCredits > 0 || s.supplierAdvances > 0) ...[
              const SizedBox(height: 12),
              _CreditsNotice(
                customerCredits: s.customerCredits,
                supplierAdvances: s.supplierAdvances,
                money: _money,
              ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle('حركة الفترة'),
            const SizedBox(height: 10),
            _MetricGrid(items: activityCards, money: _money),
            const SizedBox(height: 24),
            _AccountingHealthCard(snapshot: s, money: _money),
            const SizedBox(height: 24),
            const _SectionTitle('أكثر الحسابات حركة'),
            const SizedBox(height: 10),
            _TopAccountsCard(rows: s.topAccounts, money: _money),
            const SizedBox(height: 24),
            const _SectionTitle('آخر الحركات المحاسبية'),
            const SizedBox(height: 10),
            _RecentEntriesCard(rows: s.recentEntries, money: _money, df: _df),
          ],
        ),
      ),
    );
  }
}

class _MetricData {
  const _MetricData(
    this.title,
    this.value,
    this.icon, {
    this.emphasizeSign = false,
  });

  final String title;
  final double value;
  final IconData icon;
  final bool emphasizeSign;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items, required this.money});

  final List<_MetricData> items;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 3
            : width >= 700
                ? 2
                : 1;
        const gap = 12.0;
        final itemWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _MetricCard(item: item, money: money),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item, required this.money});

  final _MetricData item;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final negative = item.emphasizeSign && item.value < 0;
    final valueColor = negative ? Colors.red.shade700 : Colors.black87;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.10),
              child: Icon(item.icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.title,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money.format(item.value),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: valueColor,
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
}

class _AsOfBanner extends StatelessWidget {
  const _AsOfBanner({required this.to});

  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('yyyy-MM-dd').format(to);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الأرصدة حتى $label، بينما الإيرادات والمصروفات والتحصيلات تخص الفترة المختارة فقط.',
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditsNotice extends StatelessWidget {
  const _CreditsNotice({
    required this.customerCredits,
    required this.supplierAdvances,
    required this.money,
  });

  final double customerCredits;
  final double supplierAdvances;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (customerCredits > 0) {
      parts.add('أرصدة دائنة للعملاء ${money.format(customerCredits)}');
    }
    if (supplierAdvances > 0) {
      parts.add('دفعات مقدمة للموردين ${money.format(supplierAdvances)}');
    }
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(parts.join(' • '), textAlign: TextAlign.right),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountingHealthCard extends StatelessWidget {
  const _AccountingHealthCard({required this.snapshot, required this.money});

  final FinancialOverviewSnapshot snapshot;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final health = snapshot.accountingHealthy;
    final healthy = health == true && snapshot.periodBalanced;
    final unknown = health == null;
    final icon = unknown
        ? Icons.help_outline
        : healthy
            ? Icons.verified
            : Icons.warning_amber_rounded;
    final label = unknown
        ? 'فحص السلامة غير متاح'
        : healthy
            ? 'السلامة المحاسبية: سليمة'
            : 'السلامة المحاسبية: تحتاج مراجعة';
    final details = <String>[
      'فرق المدين/الدائن للفترة: ${money.format(snapshot.trialBalanceDifference)}',
      if (snapshot.integrityIssueCount != null)
        'مشكلات التكامل: ${snapshot.integrityIssueCount}',
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon,
                size: 28, color: healthy ? AppColors.primary : Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(details.join(' • '), textAlign: TextAlign.right),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopAccountsCard extends StatelessWidget {
  const _TopAccountsCard({required this.rows, required this.money});

  final List<FinancialOverviewAccountActivity> rows;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyCard('لا توجد حركة حسابات ضمن الفترة.');
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            ListTile(
              title: Text(rows[i].name, textAlign: TextAlign.right),
              subtitle: Text(
                'مدين ${money.format(rows[i].debit)} • دائن ${money.format(rows[i].credit)}',
                textAlign: TextAlign.right,
              ),
              leading: Text(
                money.format(rows[i].movement),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (i != rows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _RecentEntriesCard extends StatelessWidget {
  const _RecentEntriesCard({
    required this.rows,
    required this.money,
    required this.df,
  });

  final List<FinancialOverviewEntry> rows;
  final NumberFormat money;
  final DateFormat df;

  String _sourceLabel(String source) {
    switch (source.trim().toUpperCase()) {
      case 'INVOICE':
        return 'فاتورة';
      case 'PAYMENT':
        return 'سند قبض';
      case 'PURCHASE':
        return 'مشتريات';
      case 'VOUCHER':
        return 'سند صرف';
      case 'PAYROLL':
        return 'استحقاق راتب';
      case 'EMP_ADV':
        return 'سلفة موظف';
      default:
        return source.trim().isEmpty ? 'قيد محاسبي' : source.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyCard('لا توجد حركات محاسبية ضمن الفترة.');
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            ListTile(
              title: Text(
                rows[i].description.isNotEmpty
                    ? rows[i].description
                    : _sourceLabel(rows[i].source),
                textAlign: TextAlign.right,
              ),
              subtitle: Text(
                [
                  df.format(rows[i].date),
                  _sourceLabel(rows[i].source),
                  if (rows[i].sourceNumber.isNotEmpty) rows[i].sourceNumber,
                ].join(' • '),
                textAlign: TextAlign.right,
              ),
              leading: Text(
                money.format(rows[i].amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (i != rows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Colors.black87,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text(text, textAlign: TextAlign.center)),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 42),
            const SizedBox(height: 12),
            Text(
              'تعذر تحميل النظرة المالية:\n$error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
