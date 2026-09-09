import 'package:uuid/uuid.dart';
// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/screens/supplier_payments_screen.dart
//
// SupplierPaymentsScreen — FINAL v51 CLEAN
// - إدخال سداد مورد باستخدام supplier_id (INT فقط)
// - عرض آخر السدادّات
// - فتح GL
// - عكس السداد غير مفعّل حالياً (سيتم إضافته لاحقاً)
// - فلترة حسب supplier_id
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';
import 'package:yalla_accounts/features/finance/purchases/services/supplier_payment_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class SupplierPaymentsScreen extends StatefulWidget {
  const SupplierPaymentsScreen({super.key});

  @override
  State<SupplierPaymentsScreen> createState() => _SupplierPaymentsScreenState();
}

class _SupplierPaymentsScreenState extends State<SupplierPaymentsScreen> {
  // فورم الإدخال
  final _formKey = GlobalKey<FormState>();
  final _supplierCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _method = 'cash';
  DateTime _date = DateTime.now();
  String _operationId = const Uuid().v4();
  bool _saving = false;

  // فلترة
  final _filterCtrl = TextEditingController();

  // لستة البيانات
  bool _loading = true;
  List<Map<String, Object?>> _rows = [];

  final _df = DateFormat('yyyy-MM-dd', 'ar');
  final _nf = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  // اختيار تاريخ
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  // تحميل البيانات
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows = [];
    });

    final rows =
        await SupplierPaymentService.list(supplierId: _filterCtrl.text.trim());
    if (!mounted) return;

    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  // تنفيذ السداد
  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final supplierId = int.tryParse(_supplierCtrl.text.trim());
    if (supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier ID يجب أن يكون رقمًا')),
      );
      return;
    }

    final amount = double.parse(_amountCtrl.text.trim());
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    setState(() => _saving = true);

    try {
      final glId = await SupplierPaymentService.insertAndPost(
        operationId: _operationId,
        supplierId: supplierId,
        amount: amount,
        date: _date,
        method: _method,
        note: note,
      );

      _operationId = const Uuid().v4();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم السداد ونشر GL #$glId')),
      );

      _formKey.currentState!.reset();
      _amountCtrl.clear();
      _noteCtrl.clear();

      setState(() {
        _method = 'cash';
        _date = DateTime.now();
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل العملية: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // فتح GL
  Future<void> _openGl(int glId) async {
    await GLEntryScreen.open(context, glId);
  }

  // عكس السداد (غير مفعّل)
  Future<void> _reverse(String paymentId, int glId) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ميزة عكس السداد غير مفعّلة حالياً')),
    );
  }

  // بطاقة الإدخال
  Widget _buildQuickForm() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('سداد مورد', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),

              // Supplier ID
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _supplierCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier ID (رقمي)',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
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
                    child: Text(_df.format(_date)),
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
                  labelText: 'المبلغ',
                  prefixIcon: Icon(Icons.attach_money_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'مطلوب';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'قيمة غير صالحة';
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
                      title: const Text('بنكي'),
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
              const SizedBox(height: 12),

              // Submit
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ السداد'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // بطاقة الفلترة
  Widget _buildFilter() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AdaptiveRow(
          children: [
            Expanded(
              child: TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _filterCtrl,
                decoration: const InputDecoration(
                  labelText: 'فلترة حسب Supplier ID',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _load, child: const Text('تطبيق')),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                _filterCtrl.clear();
                _load();
              },
              child: const Text('مسح'),
            ),
          ],
        ),
      ),
    );
  }

  // لستة السدادّات
  Widget _buildList() {
    if (_loading) {
      return const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_rows.isEmpty) {
      return const Expanded(
        child: Center(child: Text('لا توجد سدادّات')),
      );
    }

    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 0),
        itemBuilder: (_, i) {
          final r = _rows[i];

          final id = r['id'].toString();
          final supId = r['party_id'].toString();
          final amt = ((r['amount'] as num?) ?? 0).toDouble();
          final date = r['date']?.toString() ?? '';
          final method = r['method']?.toString() ?? '';
          final status = r['status']?.toString() ?? 'POSTED';
          final note = r['notes']?.toString() ?? '';

          final glRaw = r['gl_entry_id'];
          final glId =
              glRaw is int ? glRaw : int.tryParse(glRaw?.toString() ?? '');

          return ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text('Supplier $supId • ${_nf.format(amt)}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$date • ${method.toUpperCase()} • $status'),
                if (note.isNotEmpty) Text('ملاحظة: $note'),
                Text('ID: $id'),
              ],
            ),
            trailing: Wrap(
              spacing: 6,
              children: [
                if (glId != null)
                  Chip(
                    label: Text('#$glId'),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  tooltip: 'فتح قيد GL',
                  onPressed: glId != null ? () => _openGl(glId) : null,
                  icon: const Icon(Icons.open_in_new),
                ),
                IconButton(
                  tooltip: 'عكس السداد',
                  onPressed: () => _reverse(id, glId ?? 0),
                  icon: const Icon(Icons.undo),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سداد الموردين'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: NestedScrollView(
          headerSliverBuilder: (_, __) => [
                SliverToBoxAdapter(child: _buildQuickForm()),
                SliverToBoxAdapter(child: _buildFilter())
              ],
          body: Column(children: [_buildList()])),
    );
  }
}
