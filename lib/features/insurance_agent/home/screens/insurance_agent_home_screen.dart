import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/design/yalla_breakpoints.dart';
import 'package:yalla_accounts/core/design/yalla_components.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/services/insurance_claim_service.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/renewals/services/insurance_renewal_service.dart';

class InsuranceAgentHomeScreen extends StatefulWidget {
  const InsuranceAgentHomeScreen({super.key});

  @override
  State<InsuranceAgentHomeScreen> createState() =>
      _InsuranceAgentHomeScreenState();
}

class _InsuranceAgentHomeScreenState extends State<InsuranceAgentHomeScreen> {
  final _search = TextEditingController();
  InsuranceDashboardSummary? _summary;
  List<InsurancePolicyOverview> _policies = const [];
  List<InsuranceRenewalCandidate> _renewals = const [];
  List<InsuranceClaimRecord> _claims = const [];
  List<InsuranceCompanyBalance> _companies = const [];
  int _selectedTab = 0;
  bool _busy = true;
  String? _error;

  static const _tabs = ['الوثائق', 'التجديدات', 'المطالبات', 'الشركات'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        InsuranceDashboardService.summary(),
        InsuranceDashboardService.policies(limit: 100),
        InsuranceRenewalService.listCandidates(),
        InsuranceClaimService.listClaims(),
        InsuranceDashboardService.companyBalances(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = values[0] as InsuranceDashboardSummary;
        _policies = values[1] as List<InsurancePolicyOverview>;
        _renewals = values[2] as List<InsuranceRenewalCandidate>;
        _claims = values[3] as List<InsuranceClaimRecord>;
        _companies = values[4] as List<InsuranceCompanyBalance>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = UserFacingError.message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String route) async {
    await AppRoutes.pushNamedSafe(context, route);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = YallaBreakpoints.isDesktop(context);
    final scaffold = Scaffold(
      drawer: desktop
          ? null
          : const Drawer(
              child: SafeArea(
                child: YallaSidebar(currentRoute: AppRoutes.insuranceAgentHome),
              ),
            ),
      appBar: AppBar(
        automaticallyImplyLeading: !desktop,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('التأمين'),
            Text('الوثائق والتجديدات والمطالبات',
                style: TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'حاسبة التأمين',
            onPressed: () => _open(AppRoutes.insuranceAgentCalculator),
            icon: const Icon(Icons.calculate_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(YallaSpacing.lg),
          children: [
            _Header(
              onAdd: () => _open(AppRoutes.insuranceAgentAddNew),
              onCalculator: () => _open(AppRoutes.insuranceAgentCalculator),
            ),
            const SizedBox(height: YallaSpacing.lg),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _ErrorCard(message: _error!, retry: _load)
            else ...[
              _Metrics(summary: _summary!),
              const SizedBox(height: YallaSpacing.lg),
              _Actions(open: _open),
              const SizedBox(height: YallaSpacing.lg),
              YallaSurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _Tabs(
                      labels: _tabs,
                      selected: _selectedTab,
                      onSelected: (value) =>
                          setState(() => _selectedTab = value),
                    ),
                    const Divider(height: 1),
                    _TabContent(
                      index: _selectedTab,
                      query: _search,
                      policies: _policies,
                      renewals: _renewals,
                      claims: _claims,
                      companies: _companies,
                      onChanged: () => setState(() {}),
                      open: _open,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!desktop) return scaffold;
    return Row(
      children: [
        const SizedBox(
          width: 280,
          child: YallaSidebar(currentRoute: AppRoutes.insuranceAgentHome),
        ),
        Expanded(child: scaffold),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onAdd, required this.onCalculator});
  final VoidCallback onAdd;
  final VoidCallback onCalculator;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مركز التأمين',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
            const Text('بيانات حقيقية ومتابعة مباشرة لكل أعمال التأمين'),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('إضافة تأمين'),
            ),
            OutlinedButton.icon(
              onPressed: onCalculator,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('الحاسبة'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.summary});
  final InsuranceDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00', 'en_US');
    final items = [
      ('الوثائق السارية', '${summary.activePolicies}', Icons.shield_outlined),
      ('تنتهي خلال 30 يوم', '${summary.expiringSoon}', Icons.event_repeat),
      (
        'ذمم العملاء',
        '${money.format(summary.customerReceivable)} ₪',
        Icons.account_balance_wallet_outlined
      ),
      ('مطالبات مفتوحة', '${summary.openClaims}', Icons.car_crash_outlined),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth >= 1000
          ? (constraints.maxWidth - 36) / 4
          : constraints.maxWidth >= 600
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: items
            .map((item) => SizedBox(
                  width: width,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(item.$3, size: 30, color: YallaColors.brand),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.$1),
                                Text(item.$2,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ))
            .toList(),
      );
    });
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.open});
  final Future<void> Function(String) open;

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('الوثائق', Icons.list_alt, AppRoutes.insurancePoliciesList),
      ('المطالبات', Icons.car_crash_outlined, AppRoutes.insuranceAgentClaims),
      (
        'جهات الاتصال',
        Icons.contacts_outlined,
        AppRoutes.insuranceAgentContacts
      ),
      (
        'المالية',
        Icons.account_balance_wallet_outlined,
        AppRoutes.insuranceAgentFinance
      ),
      (
        'التنبيهات',
        Icons.notifications_active_outlined,
        AppRoutes.insuranceAgentAlerts
      ),
      ('التقارير', Icons.assessment_outlined, AppRoutes.insuranceAgentReports),
      ('المنتجون', Icons.badge_outlined, AppRoutes.insuranceAgentProducers),
      ('الحاسبة', Icons.calculate_outlined, AppRoutes.insuranceAgentCalculator),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions
          .map((action) => OutlinedButton.icon(
                onPressed: () => open(action.$3),
                icon: Icon(action.$2),
                label: Text(action.$1),
              ))
          .toList(),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(
            labels.length,
            (index) => InkWell(
                  onTap: () => onSelected(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 3,
                          color: index == selected
                              ? YallaColors.brand
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(labels[index]),
                  ),
                )),
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.index,
    required this.query,
    required this.policies,
    required this.renewals,
    required this.claims,
    required this.companies,
    required this.onChanged,
    required this.open,
  });
  final int index;
  final TextEditingController query;
  final List<InsurancePolicyOverview> policies;
  final List<InsuranceRenewalCandidate> renewals;
  final List<InsuranceClaimRecord> claims;
  final List<InsuranceCompanyBalance> companies;
  final VoidCallback onChanged;
  final Future<void> Function(String) open;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd', 'en_US');
    final money = NumberFormat('#,##0.00', 'en_US');
    Widget content;
    if (index == 0) {
      final q = query.text.trim().toLowerCase();
      final shown = policies
          .where((policy) =>
              q.isEmpty ||
              [
                policy.number,
                policy.insuredName,
                policy.vehicle,
                policy.company
              ].any((value) => value.toLowerCase().contains(q)))
          .toList();
      content = Column(
        children: [
          TextField(
            controller: query,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'بحث باسم العميل، المركبة، الشركة أو الوثيقة',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const _Empty(text: 'لا توجد وثائق مطابقة')
          else
            ...shown.take(30).map((policy) => ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text('${policy.number} — ${policy.insuredName}'),
                  subtitle: Text(
                      '${policy.company} • ${policy.vehicle} • ${date.format(policy.endDate)}'),
                  trailing: Text('${money.format(policy.sale)} ₪'),
                  onTap: () => open(AppRoutes.insurancePoliciesList),
                )),
        ],
      );
    } else if (index == 1) {
      content = renewals.isEmpty
          ? const _Empty(text: 'لا توجد تجديدات مستحقة')
          : Column(
              children: renewals
                  .take(30)
                  .map((renewal) => ListTile(
                        leading: const Icon(Icons.event_repeat_outlined),
                        title:
                            Text('استحقاق ${date.format(renewal.renewalDate)}'),
                        subtitle: Text(
                            'الحالة ${renewal.status} • متبقي ${renewal.daysRemaining} يوم'),
                        onTap: () => open(AppRoutes.insuranceAgentAlerts),
                      ))
                  .toList(),
            );
    } else if (index == 2) {
      content = claims.isEmpty
          ? const _Empty(text: 'لا توجد مطالبات مسجلة')
          : Column(
              children: claims
                  .take(30)
                  .map((claim) => ListTile(
                        leading: const Icon(Icons.car_crash_outlined),
                        title: Text(claim.claimNumber),
                        subtitle: Text(claim.status),
                        onTap: () => open(AppRoutes.insuranceAgentClaims),
                      ))
                  .toList(),
            );
    } else {
      content = companies.isEmpty
          ? const _Empty(text: 'لا توجد شركات تأمين مسجلة')
          : Column(
              children: companies
                  .map((company) => ListTile(
                        leading: const Icon(Icons.apartment_outlined),
                        title: Text(company.name),
                        subtitle: Text('${company.policyCount} وثيقة'),
                        trailing: Text(
                            '${money.format(company.outstanding)} ₪ مستحق'),
                        onTap: () => open(AppRoutes.insuranceAgentFinance),
                      ))
                  .toList(),
            );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: content,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(child: Text(text)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: retry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}
