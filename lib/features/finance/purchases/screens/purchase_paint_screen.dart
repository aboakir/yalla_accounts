// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/screens/purchase_paint_screen.dart
//
// PurchasePaintScreen — FINAL v51
// - يدعم النظام الجديد بالكامل
// - يعتمد purchaseProvider.notifier.add()
// - خطوط مشتريات دهانات جاهزة ومتوافقة مع PurchaseService v51
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

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PurchasePaintScreen extends ConsumerStatefulWidget {
  const PurchasePaintScreen({super.key});

  @override
  ConsumerState<PurchasePaintScreen> createState() =>
      _PurchasePaintScreenState();
}

class _PurchasePaintScreenState extends ConsumerState<PurchasePaintScreen> {
  final _formKey = GlobalKey<FormState>();

  final _supplierIdCtrl = TextEditingController(); // Supplier ID (INT) REQUIRED
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController(text: 'دهانات');

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

  // تحويل أرقام عربية -> إنجليزية
  String _normalize(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const en = '0123456789';
    final b = StringBuffer();
    for (final r in s.trim().runes) {
      final ch = String.fromCharCode(r);
      final i = ar.indexOf(ch);
      b.write(i >= 0 ? en[i] : ch);
    }
    return b.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final amount = double.parse(_normalize(_amountCtrl.text.trim()));
      final supplierId = int.tryParse(_supplierIdCtrl.text.trim());
      if (supplierId == null || supplierId <= 0) {
        throw ArgumentError('معرّف المورد يجب أن يكون رقمًا صالحًا');
      }

      final lines = [
        {
          'item_name': 'دهانات',
          'qty': 1.0,
          'price': amount,
          'category': 'PAINT',
          'note': _noteCtrl.text.trim(),
        }
      ];

      await ref.read(purchaseProvider.notifier).add(
            supplierId: supplierId,
            date: _date,
            method: _method,
            note: _noteCtrl.text.trim(),
            items: lines,
            purchaseType: 'PAINT',
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("تم الحفظ")));

      _formKey.currentState!.reset();
      _supplierIdCtrl.clear();
      _amountCtrl.clear();
      _noteCtrl.text = "دهانات";
      setState(() {
        _date = DateTime.now();
        _method = 'credit';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("فشل: $e")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final df = DateFormat("yyyy-MM-dd");

    final items = ref.watch(purchaseProvider).where((p) {
      return (p.note ?? "").contains("دهان");
    }).toList();

    final form = Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text("مشتريات — دهانات",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            // Supplier ID (إلزامي)
            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _supplierIdCtrl,
              decoration: const InputDecoration(
                labelText: "معرّف المورّد *",
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final id = int.tryParse((value ?? '').trim());
                if (id == null || id <= 0) return 'أدخل معرّف مورد صالح';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // التاريخ
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: "التاريخ",
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

            // المبلغ
            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "المبلغ",
                prefixIcon: Icon(Icons.attach_money_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return "المبلغ مطلوب";
                final n = double.tryParse(_normalize(v.trim()));
                if (n == null || n <= 0) return "غير صالح";
                return null;
              },
            ),
            const SizedBox(height: 12),

            // طريقة الدفع
            InputDecorator(
              decoration: const InputDecoration(
                labelText: "طريقة الدفع",
                border: OutlineInputBorder(),
              ),
              child: Column(children: [
                RadioListTile(
                  value: "cash",
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  title: const Text("نقدي"),
                  dense: true,
                ),
                RadioListTile(
                  value: "bank",
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  title: const Text("بنكي"),
                  dense: true,
                ),
                RadioListTile(
                  value: "credit",
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  title: const Text("على الحساب"),
                  dense: true,
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // ملاحظة
            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "ملاحظة",
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
                label: Text(_saving ? "جارٍ الحفظ…" : "حفظ"),
              ),
            ),
          ]),
        ),
      ),
    );

    final list = Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(children: [
        const ListTile(title: Text("آخر مشتريات دهانات")),
        const Divider(height: 0),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text("لا يوجد"),
          ),
        if (items.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: math.min(items.length, 10),
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) {
              final p = items[i];
              return ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: Text(
                  "${df.format(p.date)} • ${MoneyFormatter.format(p.total)}",
                ),
                subtitle: Text("Supplier: ${p.supplierId ?? '-'}"),
              );
            },
          ),
      ]),
    );

    final content = ListView(children: [form, list]);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          "🎨 مشتريات دهانات",
          style: TextStyle(color: Colors.white),
        ),
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
          : const Drawer(child: YallaSidebar(currentRoute: "/purchases/paint")),
      body: isDesktop
          ? AdaptiveRow(
              children: const [
                SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: "/purchases/paint"),
                ),
                VerticalDivider(width: 1),
                Expanded(
                  child: Center(child: Text("استخدم تخطيط الموبايل للنموذج")),
                ),
              ],
            )
          : content,
    );
  }
}
