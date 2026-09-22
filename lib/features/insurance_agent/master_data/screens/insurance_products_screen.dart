import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';

class InsuranceProductsScreen extends StatefulWidget {
  const InsuranceProductsScreen({super.key});

  @override
  State<InsuranceProductsScreen> createState() =>
      _InsuranceProductsScreenState();
}

class _InsuranceProductsScreenState extends State<InsuranceProductsScreen> {
  bool _loading = true;
  bool _saving = false;
  int? _companyId;
  List<InsuranceCompanyRecord> _companies = const [];
  List<InsuranceProductRecord> _products = const [];

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _loading = true);
    try {
      final companies = await InsuranceMasterDataService.listCompanies();
      if (!mounted) return;
      setState(() {
        _companies = companies.where((company) => company.isActive).toList();
        _companyId ??= _companies.isEmpty ? null : _companies.first.id;
      });
      await _loadProducts();
    } catch (error) {
      if (mounted) _showError('تعذر تحميل شركات ومنتجات التأمين: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProducts() async {
    final companyId = _companyId;
    if (companyId == null) {
      if (mounted) setState(() => _products = const []);
      return;
    }
    final products = await InsuranceMasterDataService.listProducts(
      companyId: companyId,
    );
    if (mounted) setState(() => _products = products);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'COMPULSORY':
        return 'إلزامي';
      case 'COMPREHENSIVE':
        return 'شامل';
      case 'THIRD_PARTY':
        return 'طرف ثالث';
      default:
        return 'أخرى';
    }
  }

  Future<void> _addProduct() async {
    final companyId = _companyId;
    if (companyId == null) return;
    final nameCtrl = TextEditingController();
    final commissionCtrl = TextEditingController(text: '0');
    var type = 'COMPREHENSIVE';
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة منتج تأمين'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'المنتج هو نوع التأمين الذي تبيعه هذه الشركة، مثل شامل أو إلزامي.',
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'اسم المنتج',
                      hintText: 'مثال: شامل سيارات خاصة',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'اكتب اسم المنتج'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(
                      labelText: 'نوع التأمين',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'COMPULSORY',
                        child: Text('إلزامي'),
                      ),
                      DropdownMenuItem(
                        value: 'COMPREHENSIVE',
                        child: Text('شامل'),
                      ),
                      DropdownMenuItem(
                        value: 'THIRD_PARTY',
                        child: Text('طرف ثالث'),
                      ),
                      DropdownMenuItem(value: 'OTHER', child: Text('أخرى')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: commissionCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'نسبة عمولة الوكيل الافتراضية %',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final number = double.tryParse(value?.trim() ?? '');
                      return number == null || number < 0 || number > 100
                          ? 'اكتب نسبة من 0 إلى 100'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => _saving = true);
                      try {
                        await InsuranceMasterDataService.createProduct(
                          companyId: companyId,
                          code: 'PRD-${DateTime.now().millisecondsSinceEpoch}',
                          name: nameCtrl.text,
                          productType: type,
                          defaultCommissionRate:
                              double.parse(commissionCtrl.text.trim()),
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('تعذر حفظ المنتج: $error')),
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => _saving = false);
                        }
                      }
                    },
              child: const Text('حفظ المنتج'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    commissionCtrl.dispose();
    if (created == true && mounted) {
      await _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تمت إضافة المنتج وسيظهر في إصدار البوليصة')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('منتجات التأمين'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadCompanies,
            icon: const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              onPressed: _loading || _companyId == null ? null : _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('إضافة منتج'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCompanies,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'كتالوج المنتجات',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'أنشئ هنا أنواع التأمين المتاحة لدى كل شركة؛ بعدها تصبح قابلة للاختيار عند إصدار البوليصة.',
                  ),
                  const SizedBox(height: 18),
                  if (_companies.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'أضف شركة تأمين فعّالة أولًا، ثم أضف منتجاتها.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<int>(
                      value: _companyId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'شركة التأمين',
                        border: OutlineInputBorder(),
                      ),
                      items: _companies
                          .map(
                            (company) => DropdownMenuItem(
                              value: company.id,
                              child: Text(company.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => _companyId = value);
                        await _loadProducts();
                      },
                    ),
                    const SizedBox(height: 18),
                    if (_products.isEmpty)
                      Card(
                        color: Colors.orange.shade50,
                        child: const Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'لا توجد منتجات تأمين لهذه الشركة بعد. اضغط «إضافة منتج» لإنشاء إلزامي أو شامل أو أي خطة أخرى.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ..._products.map(
                        (product) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.shield_outlined),
                            title: Text(product.name),
                            subtitle: Text(
                              '${_typeLabel(product.productType)} • عمولة افتراضية ${product.defaultCommissionRate.toStringAsFixed(2)}%',
                            ),
                            trailing: product.isActive
                                ? const Chip(label: Text('فعّال'))
                                : const Chip(label: Text('موقوف')),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
