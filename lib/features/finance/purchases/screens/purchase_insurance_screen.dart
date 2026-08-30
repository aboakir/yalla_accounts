// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/screens/purchase_insurance_screen.dart
//
// PurchaseInsuranceScreen — FINAL v51 (FULLY COMPATIBLE)
// -----------------------------------------------------------------------------
// - يعتمد supplierId (INT) فقط — بدون supplierPid
// - يرسل purchase lines متوافقة 100% مع PurchaseService v51
// - يدعم credit / cash / bank
// - مناسب لمشتريات "تأمين" التي لا تحتوي أصناف تفصيلية
// -----------------------------------------------------------------------------

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/features/finance/purchases/providers/purchase_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PurchaseInsuranceScreen extends ConsumerStatefulWidget {
  const PurchaseInsuranceScreen({super.key});

  @override
  ConsumerState<PurchaseInsuranceScreen> createState() =>
      _PurchaseInsuranceScreenState();
}

class _PurchaseInsuranceScreenState
    extends ConsumerState<PurchaseInsuranceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplierIdCtrl = TextEditingController(); // supplierId (int)
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController(text: 'تأمين');

  String _method = 'credit';
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _supplierIdCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await ref.read(purchaseProvider.notifier).loadAll();
    if (mounted) setState(() {});
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

  String _normalizeDigits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const en = '0123456789';
    final buf = StringBuffer();
    for (final ch in s.trim().runes) {
      final chStr = String.fromCharCode(ch);
      final i = ar.indexOf(chStr);
      buf.write(i >= 0 ? en[i] : chStr);
    }
    return buf.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final supplierId = int.tryParse(_supplierIdCtrl.text.trim());
    if (supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier ID يجب أن يكون رقمًا')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final amount = double.parse(_normalizeDigits(_amountCtrl.text.trim()));
      final note = _noteCtrl.text.trim().isEmpty
          ? 'تأمين'
          : _noteCtrl.text.trim();

      // ------------------------------------------------------------------
      // أهم نقطة: تجهيز Purchase Lines وفق نظام v51
      // ------------------------------------------------------------------
      final List<Map<String, dynamic>> lines = [
        {
          "item": "تأمين",
          "qty": 1.0,
          "unit_price": amount,
          "total": amount,
          "category": "OTHER",
          "note": note,
        },
      ];

      // ------------------------------------------------------------------
      // استدعاء PurchaseProvider.notifier.add() بصيغته المتوافقة v51
      // ------------------------------------------------------------------
      await ref
          .read(purchaseProvider.notifier)
          .add(
            supplierId: supplierId,
            date: _date,
            method: _method,
            note: note,
            items: [
              {
                "item": "تأمين",
                "qty": 1.0,
                "price": amount,
                "total": amount,
                "category": "OTHER",
                "note": note,
              },
            ],
          );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم الحفظ')));

      _formKey.currentState!.reset();
      _supplierIdCtrl.clear();
      _amountCtrl.clear();
      _noteCtrl.text = 'تأمين';

      setState(() {
        _method = 'credit';
        _date = DateTime.now();
      });

      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    final items = ref
        .watch(purchaseProvider)
        .where((p) => (p.note ?? '').contains('تأمين'))
        .toList();

    final df = DateFormat('yyyy-MM-dd');

    // --------------------------------------------------------------------------
    // FORM
    // --------------------------------------------------------------------------
    final form = Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'مشتريات — تأمين',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // Supplier ID
              TextFormField(
                controller: _supplierIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier ID (رقمي)',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Supplier ID مطلوب'
                    : null,
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'التاريخ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(df.format(_date)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  prefixIcon: Icon(Icons.attach_money_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'المبلغ مطلوب';
                  final n = double.tryParse(_normalizeDigits(v.trim()));
                  if (n == null || n <= 0) return 'مبلغ غير صالح';
                  return null;
                },
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
                      value: 'cash',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('نقدي'),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'bank',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('بنكي'),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'credit',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('على الحساب'),
                      dense: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة',
                  prefixIcon: Icon(Icons.note_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جارٍ الحفم' : 'حفظ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // --------------------------------------------------------------------------
    // LIST
    // --------------------------------------------------------------------------
    final list = Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const ListTile(title: Text('آخر مشتريات التأمين')),
          const Divider(height: 0),
          if (items.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('لا يوجد')),
          if (items.isNotEmpty)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: math.min(items.length, 10),
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, i) {
                final p = items[i];
                return ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(
                    '${df.format(p.date)}  •  ${MoneyFormatter.format(p.total)}',
                  ),
                  subtitle: Text('Supplier ID: ${p.supplierId ?? '-'}'),
                );
              },
            ),
        ],
      ),
    );

    final content = ListView(children: [form, list]);

    // --------------------------------------------------------------------------
    // LAYOUT
    // --------------------------------------------------------------------------
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          '🛡️ مشتريات تأمين',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
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
              child: YallaSidebar(currentRoute: '/purchases/insurance'),
            ),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/purchases/insurance'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
