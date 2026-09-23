import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';

typedef InsuranceCompaniesLoader = Future<List<InsuranceCompanyRecord>>
    Function();
typedef InsuranceProductsLoader = Future<List<InsuranceProductRecord>> Function(
    int companyId);
typedef InsuranceCoveragesLoader = Future<List<InsuranceCoverageRecord>>
    Function(String productId);

class InsuranceMasterDataScreen extends StatefulWidget {
  const InsuranceMasterDataScreen({
    super.key,
    this.companiesLoader,
    this.productsLoader,
    this.coveragesLoader,
  });

  final InsuranceCompaniesLoader? companiesLoader;
  final InsuranceProductsLoader? productsLoader;
  final InsuranceCoveragesLoader? coveragesLoader;

  @override
  State<InsuranceMasterDataScreen> createState() =>
      _InsuranceMasterDataScreenState();
}

class _InsuranceMasterDataScreenState extends State<InsuranceMasterDataScreen> {
  bool _loading = true;
  Object? _error;
  int? _companyId;
  String? _productId;
  List<InsuranceCompanyRecord> _companies = const [];
  List<InsuranceProductRecord> _products = const [];
  List<InsuranceCoverageRecord> _coverages = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<List<InsuranceCompanyRecord>> _loadCompanies() =>
      widget.companiesLoader?.call() ??
      InsuranceMasterDataService.listCompanies();

  Future<List<InsuranceProductRecord>> _loadProducts(int companyId) =>
      widget.productsLoader?.call(companyId) ??
      InsuranceMasterDataService.listProducts(companyId: companyId);

  Future<List<InsuranceCoverageRecord>> _loadCoverages(String productId) =>
      widget.coveragesLoader?.call(productId) ??
      InsuranceMasterDataService.listCoverages(productId: productId);

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final companies = await _loadCompanies();
      int? companyId = _companyId;
      if (companyId == null || !companies.any((row) => row.id == companyId)) {
        companyId = companies.isEmpty ? null : companies.first.id;
      }
      final products = companyId == null
          ? const <InsuranceProductRecord>[]
          : await _loadProducts(companyId);
      String? productId = _productId;
      if (productId == null || !products.any((row) => row.id == productId)) {
        productId = products.isEmpty ? null : products.first.id;
      }
      final coverages = productId == null
          ? const <InsuranceCoverageRecord>[]
          : await _loadCoverages(productId);
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _companyId = companyId;
        _products = products;
        _productId = productId;
        _coverages = coverages;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectCompany(int companyId) async {
    if (_companyId == companyId) return;
    setState(() {
      _companyId = companyId;
      _productId = null;
      _products = const [];
      _coverages = const [];
      _loading = true;
      _error = null;
    });
    try {
      final products = await _loadProducts(companyId);
      final productId = products.isEmpty ? null : products.first.id;
      final coverages = productId == null
          ? const <InsuranceCoverageRecord>[]
          : await _loadCoverages(productId);
      if (!mounted || _companyId != companyId) return;
      setState(() {
        _products = products;
        _productId = productId;
        _coverages = coverages;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectProduct(String productId) async {
    if (_productId == productId) return;
    setState(() {
      _productId = productId;
      _coverages = const [];
      _loading = true;
      _error = null;
    });
    try {
      final coverages = await _loadCoverages(productId);
      if (!mounted || _productId != productId) return;
      setState(() {
        _coverages = coverages;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('insuranceMasterDataScreen'),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text(
              '\u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u0623\u0633\u0627\u0633\u064a\u0629 \u0644\u0644\u062a\u0623\u0645\u064a\u0646'),
          actions: [
            IconButton(
              key: const Key('masterDataRefresh'),
              tooltip: '\u062a\u062d\u062f\u064a\u062b',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    _ErrorBanner(onRetry: _reload)
                  else if (_companies.isEmpty && !_loading)
                    const _EmptyState(
                      icon: Icons.business_outlined,
                      text:
                          '\u0644\u0627 \u062a\u0648\u062c\u062f \u0634\u0631\u0643\u0627\u062a \u062a\u0623\u0645\u064a\u0646 \u0645\u0631\u0628\u0648\u0637\u0629 \u0628\u0634\u0643\u0644 \u0635\u062d\u064a\u062d.',
                    )
                  else if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _companiesPanel()),
                        const SizedBox(width: 12),
                        Expanded(child: _productsPanel()),
                        const SizedBox(width: 12),
                        Expanded(child: _coveragesPanel()),
                      ],
                    )
                  else ...[
                    _companiesPanel(),
                    const SizedBox(height: 12),
                    _productsPanel(),
                    const SizedBox(height: 12),
                    _coveragesPanel(),
                  ],
                ],
              ),
            ),
            if (_loading)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _companiesPanel() {
    return _MasterPanel(
      title:
          '\u0634\u0631\u0643\u0627\u062a \u0627\u0644\u062a\u0623\u0645\u064a\u0646',
      icon: Icons.business_outlined,
      count: _companies.length,
      child: _companies.isEmpty
          ? const _PanelEmpty(
              text:
                  '\u0644\u0627 \u062a\u0648\u062c\u062f \u0634\u0631\u0643\u0627\u062a')
          : Column(
              children: _companies
                  .map(
                    (row) => ListTile(
                      key: Key('masterCompany-${row.id}'),
                      selected: row.id == _companyId,
                      selectedTileColor:
                          AppColors.primary.withValues(alpha: .08),
                      leading: Icon(row.isActive
                          ? Icons.verified_outlined
                          : Icons.pause_circle_outline),
                      title: Text(row.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${row.code}  |  ${row.outstanding.toStringAsFixed(2)}'),
                      onTap: () => _selectCompany(row.id),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _productsPanel() {
    return _MasterPanel(
      title: '\u0627\u0644\u0645\u0646\u062a\u062c\u0627\u062a',
      icon: Icons.inventory_2_outlined,
      count: _products.length,
      child: _companyId == null
          ? const _PanelEmpty(
              text:
                  '\u0627\u062e\u062a\u0631 \u0634\u0631\u0643\u0629 \u0623\u0648\u0644\u0627\u064b')
          : _products.isEmpty
              ? const _PanelEmpty(
                  text:
                      '\u0644\u0627 \u062a\u0648\u062c\u062f \u0645\u0646\u062a\u062c\u0627\u062a \u0644\u0644\u0634\u0631\u0643\u0629')
              : Column(
                  children: _products
                      .map(
                        (row) => ListTile(
                          key: Key('masterProduct-${row.id}'),
                          selected: row.id == _productId,
                          selectedTileColor:
                              AppColors.primary.withValues(alpha: .08),
                          leading: Icon(row.isActive
                              ? Icons.shield_outlined
                              : Icons.pause_circle_outline),
                          title: Text(row.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${row.code}  |  ${row.productType}'),
                          onTap: () => _selectProduct(row.id),
                        ),
                      )
                      .toList(),
                ),
    );
  }

  Widget _coveragesPanel() {
    return _MasterPanel(
      title: '\u0627\u0644\u062a\u063a\u0637\u064a\u0627\u062a',
      icon: Icons.health_and_safety_outlined,
      count: _coverages.length,
      child: _productId == null
          ? const _PanelEmpty(
              text:
                  '\u0627\u062e\u062a\u0631 \u0645\u0646\u062a\u062c\u0627\u064b \u0623\u0648\u0644\u0627\u064b')
          : _coverages.isEmpty
              ? const _PanelEmpty(
                  text:
                      '\u0644\u0627 \u062a\u0648\u062c\u062f \u062a\u063a\u0637\u064a\u0627\u062a \u0644\u0644\u0645\u0646\u062a\u062c')
              : Column(
                  children: _coverages
                      .map(
                        (row) => ListTile(
                          key: Key('masterCoverage-${row.id}'),
                          leading: Icon(row.isActive
                              ? Icons.check_circle_outline
                              : Icons.pause_circle_outline),
                          title: Text(row.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${row.code}  |  \u062a\u062d\u0645\u0644 ${row.deductible.toStringAsFixed(2)}'
                            '${row.limitAmount == null ? '' : '  |  \u062d\u062f ${row.limitAmount!.toStringAsFixed(2)}'}',
                          ),
                        ),
                      )
                      .toList(),
                ),
    );
  }
}

class _MasterPanel extends StatelessWidget {
  const _MasterPanel({
    required this.title,
    required this.icon,
    required this.count,
    required this.child,
  });

  final String title;
  final IconData icon;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: CircleAvatar(radius: 15, child: Text('$count')),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 52),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text(
              '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u0623\u0633\u0627\u0633\u064a\u0629'),
          trailing: TextButton(
            key: const Key('masterDataRetry'),
            onPressed: onRetry,
            child: const Text(
                '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'),
          ),
        ),
      );
}
