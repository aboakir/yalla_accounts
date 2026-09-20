import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

import 'package:yalla_accounts/features/finance/purchases/services/purchase_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PurchaseToolsScreen extends StatefulWidget {
  const PurchaseToolsScreen({super.key});

  @override
  State<PurchaseToolsScreen> createState() => _PurchaseToolsScreenState();
}

class _PurchaseToolsScreenState extends State<PurchaseToolsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplierCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _method = 'credit'; // cash | bank | credit
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _submitQuick() async {
    if (!_formKey.currentState!.validate()) return;

    final supplierId = int.tryParse(_supplierCtrl.text.trim());
    if (supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier ID يجب أن يكون رقمياً')),
      );
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Amount غير صالح')));
      return;
    }

    setState(() => _saving = true);
    try {
      final id = await PurchaseService.createAndPost(
        supplierId: supplierId,
        supplierName: "مشتريات أدوات",
        amount: amount, // ← ← الإضافة المطلوبة
        date: _date,
        method: _method,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        purchaseType: "TOOLS",
        lines: [
          {
            "item": "TOOLS_PURCHASE",
            "qty": 1,
            "unit_price": amount,
            "total": amount,
            "category": "TOOLS",
            "note": null,
          }
        ],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم إنشاء شراء #$id')));

      // Reset
      _formKey.currentState!.reset();
      _supplierCtrl.clear();
      _amountCtrl.clear();
      _noteCtrl.clear();
      setState(() {
        _method = 'credit';
        _date = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل الإنشاء: ${UserFacingError.message(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildQuickForm() {
    final df = DateFormat('yyyy-MM-dd');
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Quick Purchase',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),

              // Supplier ID
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _supplierCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier ID (رقمي)',
                  hintText: 'مثال: 101',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Supplier ID مطلوب';
                  }
                  if (int.tryParse(v.trim()) == null) {
                    return 'Supplier ID يجب أن يكون رقماً';
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
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.event_outlined),
                    border: OutlineInputBorder(),
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
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.attach_money_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Amount مطلوب';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Amount غير صالح';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Method
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Method',
                  border: OutlineInputBorder(),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      dense: true,
                      value: 'cash',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('Cash'),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      value: 'bank',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('Bank'),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      value: 'credit',
                      groupValue: _method,
                      onChanged: (v) => setState(() => _method = v!),
                      title: const Text('On Account (AP)'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Note
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.note_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Submit
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submitQuick,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save Purchase'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.purchasesList),
              icon: const Icon(Icons.list_alt),
              label: const Text('Purchases List'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.purchaseCreate),
              icon: const Icon(Icons.add),
              label: const Text('New Purchase'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.purchasePayments),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Payments'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    final content = ListView(
      children: [
        _buildQuickForm(),
        _buildActions(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('🛠️ Purchase Tools',
            style: TextStyle(color: Colors.white)),
        leading: isDesktop
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  tooltip: 'فتح القائمة',
                ),
              ),
      ),
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/purchases/tools'),
            ),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/purchases/tools'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
