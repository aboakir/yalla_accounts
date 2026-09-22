import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';

class StepInsuredInfo extends StatefulWidget {
  final PolicyDraft draft;
  final GlobalKey<FormState> formKey;

  const StepInsuredInfo({
    super.key,
    required this.draft,
    required this.formKey,
  });

  @override
  State<StepInsuredInfo> createState() => _StepInsuredInfoState();
}

class _CoverageOption {
  const _CoverageOption({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;
}

class _StepInsuredInfoState extends State<StepInsuredInfo> {
  late final TextEditingController _insuredNameCtrl;
  late final TextEditingController _insuredPhoneCtrl;

  List<InsuranceCompanyRecord> _insurers = const [];
  List<InsuranceProductRecord> _products = const [];
  List<_CoverageOption> _coverages = const [];
  Set<String> _selectedCoverageIds = <String>{};

  bool _loadingInsurers = true;
  bool _loadingProducts = false;
  bool _loadingCoverages = false;

  @override
  void initState() {
    super.initState();
    _insuredNameCtrl = TextEditingController(
      text: widget.draft.insuredName ?? '',
    );
    _insuredPhoneCtrl = TextEditingController(
      text: widget.draft.insuredPhone ?? '',
    );
    _selectedCoverageIds = _readCoverageIds().toSet();
    _loadInsurers();
  }

  @override
  void dispose() {
    _insuredNameCtrl.dispose();
    _insuredPhoneCtrl.dispose();
    super.dispose();
  }

  List<String> _readCoverageIds() {
    return widget.draft.coverageIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  void _writeCoverageIds(Iterable<String> values) {
    final normalized = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    widget.draft.coverageIds
      ..clear()
      ..addAll(normalized);
  }

  Future<void> _loadInsurers() async {
    try {
      final rows = (await InsuranceMasterDataService.listCompanies())
          .where((company) => company.isActive)
          .toList();

      int? selectedId = widget.draft.insuranceCompanyId;
      if (!rows.any((company) => company.id == selectedId)) {
        final currentName =
            (widget.draft.companyName ?? '').trim().toLowerCase();
        InsuranceCompanyRecord? matching;
        for (final company in rows) {
          if (company.name.trim().toLowerCase() == currentName) {
            matching = company;
            break;
          }
        }
        selectedId = matching?.id;
      }
      selectedId ??= rows.isEmpty ? null : rows.first.id;

      if (!mounted) return;
      setState(() {
        _insurers = rows;
        _loadingInsurers = false;
      });

      if (selectedId != null) {
        final selected = rows.firstWhere(
          (company) => company.id == selectedId,
        );
        widget.draft.insuranceCompanyId = selected.id;
        widget.draft.companyName = selected.name;
        await _loadProducts(selected.id, preserveSelection: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInsurers = false);
    }
  }

  Future<void> _loadProducts(
    int companyId, {
    required bool preserveSelection,
  }) async {
    if (mounted) {
      setState(() {
        _loadingProducts = true;
        _loadingCoverages = false;
        _products = const [];
        _coverages = const [];
        if (!preserveSelection) {
          _selectedCoverageIds.clear();
          _writeCoverageIds(const []);
        }
      });
    }

    try {
      final rows = (await InsuranceMasterDataService.listProducts(
        companyId: companyId,
      ))
          .where((product) => product.isActive)
          .toList();
      if (widget.draft.insuranceCompanyId != companyId) return;

      String? selectedProductId =
          preserveSelection ? widget.draft.productId?.trim() : null;
      if (!rows.any((product) => product.id == selectedProductId)) {
        selectedProductId = rows.isEmpty ? null : rows.first.id;
      }

      if (!mounted) return;
      setState(() {
        _products = rows;
        _loadingProducts = false;
      });

      if (selectedProductId == null) {
        widget.draft.productId = null;
        widget.draft.coverageType = null;
        return;
      }

      final selected = rows.firstWhere(
        (product) => product.id == selectedProductId,
      );
      widget.draft.productId = selected.id;
      widget.draft.coverageType = selected.productType;
      await _loadCoverages(
        selected.id,
        preserveSelection: preserveSelection,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProducts = false);
    }
  }

  Future<void> _loadCoverages(
    String productId, {
    required bool preserveSelection,
  }) async {
    if (mounted) {
      setState(() {
        _loadingCoverages = true;
        _coverages = const [];
        if (!preserveSelection) {
          _selectedCoverageIds.clear();
          _writeCoverageIds(const []);
        }
      });
    }

    try {
      final db = await DBService.database;
      final rows = await db.query(
        'insurance_coverages',
        columns: const ['id', 'code', 'name'],
        where: 'product_id=? AND is_active=1',
        whereArgs: [productId],
        orderBy: 'name ASC',
      );
      final options = rows
          .map(
            (row) => _CoverageOption(
              id: row['id'].toString(),
              code: (row['code'] ?? '').toString(),
              name: (row['name'] ?? '').toString(),
            ),
          )
          .toList();
      if (widget.draft.productId != productId) return;
      final availableIds = options.map((option) => option.id).toSet();
      final selected = preserveSelection
          ? _selectedCoverageIds.intersection(availableIds)
          : <String>{};

      if (!mounted) return;
      setState(() {
        _coverages = options;
        _selectedCoverageIds = selected;
        _loadingCoverages = false;
      });
      _writeCoverageIds(selected);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCoverages = false);
    }
  }

  String? _validateName(String? value) {
    if ((value ?? '').trim().isEmpty) return 'أدخل اسم المؤمن له';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return 'أدخل رقم الهاتف';
    if (phone.length < 7) return 'رقم الهاتف غير صحيح';
    return null;
  }

  String _productTypeLabel(String type) {
    switch (type.trim().toUpperCase()) {
      case 'THIRD_PARTY':
      case 'THIRD':
      case 'TP':
        return 'طرف ثالث';
      case 'COMPREHENSIVE':
      case 'FULL':
        return 'شامل';
      default:
        return type.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final selectedCompanyId = _insurers.any(
      (company) => company.id == draft.insuranceCompanyId,
    )
        ? draft.insuranceCompanyId
        : null;
    final selectedProductId = _products.any(
      (product) => product.id == draft.productId,
    )
        ? draft.productId
        : null;

    return Form(
      key: widget.formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'بيانات المؤمن له وشركة التأمين',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 16),
          TextFormField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _insuredNameCtrl,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'اسم المؤمن له',
              border: OutlineInputBorder(),
            ),
            validator: _validateName,
            onChanged: (value) => draft.insuredName = value.trim(),
            onSaved: (value) => draft.insuredName = (value ?? '').trim(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _insuredPhoneCtrl,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              border: OutlineInputBorder(),
            ),
            validator: _validatePhone,
            onChanged: (value) => draft.insuredPhone = value.trim(),
            onSaved: (value) => draft.insuredPhone = (value ?? '').trim(),
          ),
          const SizedBox(height: 12),
          if (_loadingInsurers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            DropdownButtonFormField<int>(
              value: selectedCompanyId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'شركة التأمين',
                border: OutlineInputBorder(),
              ),
              hint: const Text('اختر شركة التأمين'),
              items: _insurers
                  .map(
                    (company) => DropdownMenuItem<int>(
                      value: company.id,
                      child: Text(
                        company.name,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (companyId) async {
                if (companyId == null) return;
                final company = _insurers.firstWhere(
                  (item) => item.id == companyId,
                );
                setState(() {
                  draft.insuranceCompanyId = company.id;
                  draft.companyName = company.name;
                  draft.productId = null;
                  draft.coverageType = null;
                });
                await _loadProducts(company.id, preserveSelection: false);
                widget.formKey.currentState?.validate();
              },
              validator: (value) => value == null
                  ? 'اختر شركة تأمين مرتبطة بسجل المورد والأطراف'
                  : null,
            ),
          const SizedBox(height: 12),
          if (_loadingProducts)
            const LinearProgressIndicator()
          else if (_products.isEmpty && selectedCompanyId != null)
            FormField<String>(
              key: ValueKey<int>(selectedCompanyId),
              initialValue: draft.productId,
              validator: (_) => 'لا توجد منتجات تأمين فعّالة لهذه الشركة.',
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'لا توجد منتجات تأمين فعّالة لهذه الشركة حالياً.',
                    textAlign: TextAlign.right,
                  ),
                  if (field.hasError) ...[
                    const SizedBox(height: 6),
                    Text(
                      field.errorText!,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (_products.isNotEmpty)
            DropdownButtonFormField<String>(
              value: selectedProductId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'منتج التأمين',
                border: OutlineInputBorder(),
              ),
              hint: const Text('اختر منتج التأمين'),
              items: _products
                  .map(
                    (product) => DropdownMenuItem<String>(
                      value: product.id,
                      child: Text(
                        '${product.name} — ${_productTypeLabel(product.productType)}',
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (productId) async {
                if (productId == null) return;
                final product = _products.firstWhere(
                  (item) => item.id == productId,
                );
                setState(() {
                  draft.productId = product.id;
                  draft.coverageType = product.productType;
                });
                await _loadCoverages(
                  product.id,
                  preserveSelection: false,
                );
                widget.formKey.currentState?.validate();
              },
              validator: (value) => value == null ? 'اختر منتج التأمين' : null,
            ),
          if (_loadingCoverages) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else if (_coverages.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'التغطيات المشمولة',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            FormField<Set<String>>(
              key: ValueKey<String>('coverage_${draft.productId ?? ''}'),
              initialValue: Set<String>.from(_selectedCoverageIds),
              validator: (_) => _selectedCoverageIds.isEmpty
                  ? 'اختر تغطية واحدة على الأقل'
                  : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: _coverages.map((coverage) {
                      final selected =
                          _selectedCoverageIds.contains(coverage.id);
                      return FilterChip(
                        selected: selected,
                        label: Text(
                          coverage.code.trim().isEmpty
                              ? coverage.name
                              : '${coverage.name} (${coverage.code})',
                        ),
                        onSelected: (enabled) {
                          setState(() {
                            if (enabled) {
                              _selectedCoverageIds.add(coverage.id);
                            } else {
                              _selectedCoverageIds.remove(coverage.id);
                            }
                            _writeCoverageIds(_selectedCoverageIds);
                          });
                          field.didChange(
                            Set<String>.from(_selectedCoverageIds),
                          );
                        },
                      );
                    }).toList(),
                  ),
                  if (field.hasError) ...[
                    const SizedBox(height: 6),
                    Text(
                      field.errorText!,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: draft.isVip,
            onChanged: (value) => setState(() => draft.isVip = value),
            title: const Text('VIP', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
