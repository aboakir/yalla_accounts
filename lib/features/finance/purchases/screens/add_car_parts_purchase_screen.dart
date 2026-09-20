import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/finance/purchases/screens/add_car_parts_purchase_screen.dart
//
// AddCarPartsPurchaseScreen — إنشاء فاتورة شراء "قطع سيارات" (بدون فرض RTL)
// - بنود ديناميكية: الاسم + الكمية + سعر الوحدة = الإجمالي
// - ينشر شراء واحد عبر PurchaseDatabaseService.insertPurchase
// - الحقول: معرّف المورّد (رقمي), التاريخ, طريقة الدفع (cash/bank/credit), ملاحظة
// - يدعم الديسكتوب مع Sidebar
//
// ملاحظة: نخزن الإجمالي فقط الآن في purchases.amount.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class AddCarPartsPurchaseScreen extends StatefulWidget {
  const AddCarPartsPurchaseScreen({super.key});

  static Future<void> open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddCarPartsPurchaseScreen()),
    );
  }

  @override
  State<AddCarPartsPurchaseScreen> createState() =>
      _AddCarPartsPurchaseScreenState();
}

class _AddCarPartsPurchaseScreenState extends State<AddCarPartsPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();

  final _supplierIdCtrl = TextEditingController();
  final _noteCtrl = TextEditingController(text: 'قطع سيارات');

  DateTime _date = DateTime.now();
  String _method = 'credit'; // cash | bank | credit
  bool _saving = false;

  final _items = <_PartRow>[];

  @override
  void initState() {
    super.initState();
    _addRow();
  }

  @override
  void dispose() {
    for (final r in _items) {
      r.dispose();
    }
    _supplierIdCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void update(VoidCallback fn) => setState(fn);

  void _addRow() {
    setState(() => _items.add(_PartRow()));
  }

  void _removeRow(int index) {
    if (_items.length == 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  double _calcTotal() {
    double s = 0.0;
    for (final r in _items) {
      final q = double.tryParse(r.qtyCtrl.text.trim()) ?? 0;
      final p = double.tryParse(r.priceCtrl.text.trim()) ?? 0;
      s += q * p;
    }
    return s;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // تحقق من البنود
    bool hasValid = false;
    for (final r in _items) {
      final nameOk = r.nameCtrl.text.trim().isNotEmpty;
      final qty = double.tryParse(r.qtyCtrl.text.trim()) ?? 0;
      final price = double.tryParse(r.priceCtrl.text.trim()) ?? 0;
      if (nameOk && qty > 0 && price > 0) {
        hasValid = true;
        break;
      }
    }
    if (!hasValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('أضف بندًا واحدًا على الأقل بكمية وسعر صالحين')),
      );
      return;
    }

    final supplierId = int.tryParse(_supplierIdCtrl.text.trim());
    if (supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معرّف المورّد يجب أن يكون رقمًا')),
      );
      return;
    }

    final total = _calcTotal();
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الإجمالي يجب أن يكون أكبر من صفر')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final id = await PurchaseInvoiceService.createInvoice(
        supplierId: supplierId,
        date: _date,
        note: _noteCtrl.text.trim().isEmpty
            ? 'قطع سيارات'
            : _noteCtrl.text.trim(),
        items: _items.map((r) {
          final qty = double.tryParse(r.qtyCtrl.text.trim()) ?? 0;
          final price = double.tryParse(r.priceCtrl.text.trim()) ?? 0;
          return {
            "name": r.nameCtrl.text.trim(),
            "qty": qty,
            "price": price,
          };
        }).toList(),
        method: _method,
        purchaseType: "PARTS",
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'تم حفظ فاتورة قطع #$id — ${MoneyFormatter.format(total)}')),
      );

      // إعادة الضبط
      for (final r in _items) {
        r.nameCtrl.clear();
        r.qtyCtrl.clear();
        r.priceCtrl.clear();
      }
      if (_items.length > 1) {
        _items.removeRange(1, _items.length);
      }
      setState(() {
        _supplierIdCtrl.clear();
        _noteCtrl.text = 'قطع سيارات';
        _method = 'credit';
        _date = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحفظ: ${UserFacingError.message(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final df = DateFormat('yyyy-MM-dd');
    final total = _calcTotal();

    final form = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إضافة شراء قطع سيارات',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),

              // Supplier ID
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _supplierIdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'معرّف المورّد',
                  hintText: 'مثال: 101',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'معرّف المورّد مطلوب';
                  }
                  if (int.tryParse(v.trim()) == null) {
                    return 'يجب أن يكون رقمًا';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 12),

              // Date
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'التاريخ',
                    prefixIcon: Icon(Icons.event_outlined),
                    border: OutlineInputBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(df.format(_date)),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Items header
              AdaptiveRow(
                children: [
                  Text('البنود',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة صف'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Items table-like
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      // header
                      const _ItemsHeader(),
                      const Divider(height: 8),
                      ...List.generate(_items.length, (i) {
                        return Column(
                          children: [
                            _ItemRowWidget(
                              row: _items[i],
                              onChanged: () => setState(() {}),
                              onRemove: _items.length == 1
                                  ? null
                                  : () => _removeRow(i),
                            ),
                            if (i != _items.length - 1)
                              const Divider(height: 8),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Method
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'طريقة الدفع',
                  border: OutlineInputBorder(),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      dense: true,
                      value: 'cash',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('نقدي'),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      value: 'bank',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('بنك/تحويل'),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      value: 'credit',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('آجل (دائنون)'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Note
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  prefixIcon: Icon(Icons.note_outlined),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // Totals
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'الإجمالي: ${MoneyFormatter.format(total)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ الفاتورة'),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('إضافة شراء قطع سيارات',
            style: TextStyle(color: Colors.white)),
        leading: isDesktop
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
      ),
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/purchases/parts/add'),
            ),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/purchases/parts/add'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: form),
              ],
            )
          : form,
    );
  }
}

// ===== Items widgets =====

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontWeight: FontWeight.bold);
    return AdaptiveRow(
      children: const [
        Expanded(flex: 4, child: Text('اسم القطعة', style: style)),
        SizedBox(width: 8),
        Expanded(flex: 2, child: Text('الكمية', style: style)),
        SizedBox(width: 8),
        Expanded(flex: 3, child: Text('سعر الوحدة', style: style)),
        SizedBox(width: 8),
        Expanded(flex: 3, child: Text('إجمالي السطر', style: style)),
        SizedBox(width: 8),
        SizedBox(width: 40), // actions
      ],
    );
  }
}

class _ItemRowWidget extends StatelessWidget {
  final _PartRow row;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _ItemRowWidget({
    required this.row,
    required this.onChanged,
    this.onRemove,
  });

  double _lineTotal() {
    final q = double.tryParse(row.qtyCtrl.text.trim()) ?? 0;
    final p = double.tryParse(row.priceCtrl.text.trim()) ?? 0;
    return q * p;
  }

  @override
  Widget build(BuildContext context) {
    final total = MoneyFormatter.number(_lineTotal());
    return AdaptiveRow(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: row.nameCtrl,
            decoration: const InputDecoration(
              hintText: 'مثال: بوية لؤلؤية',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: row.qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '1',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: row.priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '0.00',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(total, textAlign: TextAlign.right),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: IconButton(
            tooltip: 'حذف',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }
}

class _PartRow {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController qtyCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}
