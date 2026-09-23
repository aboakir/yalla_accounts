// 📁 lib/features/finance/purchases/screens/suppliers_aging_screen.dart
//
// شاشة أعمار ذمم الموردين (GL) — v30
// - يحسب حتى نهاية يوم "التاريخ المرجعي" بدقة (e.date < asOf+1).
// - بحث بالاسم أو رقم/كود المورد (TEXT).
// - التجميع من gl_lines حيث party_type='SUPPLIER' باستخدام (credit - debit).
// - أعمدة: 0–30 | 31–60 | 61–90 | 91–120 | +120 | الإجمالي.
// - فتح كشف حساب المورد عبر AppRoutes.purchasesSupplierLedger.
// - هوية لونية: AppBar = AppColors.primary، Chips بخلفية خفيفة.
//
// ملاحظة: رصيد المورد الدائن = SUM(credit - debit). الصفوف الصفرية مستبعدة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/reports/providers/supplier_aging_provider.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/pdf/supplier_ledger_pdf.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class SuppliersAgingScreen extends StatefulWidget {
  const SuppliersAgingScreen({super.key});

  @override
  State<SuppliersAgingScreen> createState() => _SuppliersAgingScreenState();
}

class _SuppliersAgingScreenState extends State<SuppliersAgingScreen> {
  bool _loading = true;
  List<_Row> _rows = [];
  double _tot0 = 0, _tot30 = 0, _tot60 = 0, _tot90 = 0, _tot120 = 0, _grand = 0;

  final _nf = NumberFormat('#,##0.00', 'ar');
  final _df = DateFormat('yyyy-MM-dd', 'ar');

  DateTime _asOf = DateTime.now();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAsOf() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'اختر التاريخ المرجعي',
      locale: const Locale('ar'),
    );
    if (d != null) {
      setState(() => _asOf = DateTime(d.year, d.month, d.day));
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sourceRows = await SupplierAgingProvider.fetch(
        asOf: _asOf,
        query: _searchCtrl.text,
      );
      if (!mounted) return;

      final rows = sourceRows
          .map((m) => _Row(
                supplierId: m.supplierId,
                supplierName: m.supplierName,
                b0_30: m.b0_30,
                b31_60: m.b31_60,
                b61_90: m.b61_90,
                b91_120: m.b91_120,
                b120p: m.b120p,
                total: m.total,
              ))
          .toList(growable: false);
      double t0 = 0, t30 = 0, t60 = 0, t90 = 0, t120 = 0, tg = 0;
      for (final row in rows) {
        t0 += row.b0_30;
        t30 += row.b31_60;
        t60 += row.b61_90;
        t90 += row.b91_120;
        t120 += row.b120p;
        tg += row.total;
      }

      setState(() {
        _rows = rows;
        _tot0 = t0;
        _tot30 = t30;
        _tot60 = t60;
        _tot90 = t90;
        _tot120 = t120;
        _grand = tg;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      rethrow;
    }
  }

  void _openSupplier(String id, String name) {
    Navigator.of(context).pushNamed(
      AppRoutes.purchasesSupplierLedger,
      arguments: {
        'supplierId': id,
        'supplierName': name,
        'asOf': _asOf.toIso8601String(),
      },
    );
  }

  Future<void> _printSupplierPdf(
    String supplierId,
    String supplierName,
  ) async {
    await SupplierLedgerPdf.generate(
      supplierId: supplierId,
      supplierName: supplierName,
      to: _asOf, // نفس التاريخ المرجعي
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      drawer: MediaQuery.sizeOf(context).width < 600
          ? const Drawer(child: YallaSidebar())
          : null,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('أعمار ذمم الموردين',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'تاريخ مرجعي',
            onPressed: _pickAsOf,
            icon: const Icon(Icons.calendar_month, color: Colors.white),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: TextField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم المورّد أو رقمه',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _load();
                              },
                            ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 12),
                Text('حتى: ${_df.format(_asOf)}',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Text('لا توجد أرصدة للموردين عند التاريخ المحدد'))
              : Column(
                  children: [
                    // إجماليات
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _chip('0–30 يوم', _nf.format(_tot0)),
                          _chip('31–60 يوم', _nf.format(_tot30)),
                          _chip('61–90 يوم', _nf.format(_tot60)),
                          _chip('91–120 يوم', _nf.format(_tot90)),
                          _chip('+120 يوم', _nf.format(_tot120)),
                          _chip('الإجمالي', _nf.format(_grand), filled: true),
                        ],
                      ),
                    ),
                    // هيدر
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      color: Colors.black.withOpacity(.04),
                      child: AdaptiveRow(
                        children: [
                          _h('المورّد', flex: 3),
                          _h('0–30', alignEnd: true),
                          _h('31–60', alignEnd: true),
                          _h('61–90', alignEnd: true),
                          _h('91–120', alignEnd: true),
                          _h('+120', alignEnd: true),
                          _h('الإجمالي', alignEnd: true, flex: 2),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    // جدول
                    Expanded(
                      child: ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          return InkWell(
                            onTap: () =>
                                _openSupplier(r.supplierId, r.supplierName),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: AdaptiveRow(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(r.supplierName,
                                        style: t.bodyMedium),
                                  ),
                                  _amt(r.b0_30),
                                  _amt(r.b31_60),
                                  _amt(r.b61_90),
                                  _amt(r.b91_120),
                                  _amt(r.b120p),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _nf.format(r.total),
                                      textAlign: TextAlign.end,
                                      style: t.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  AdaptiveRow(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'كشف حساب',
                                        icon: const Icon(Icons.open_in_new),
                                        onPressed: () => _openSupplier(
                                            r.supplierId, r.supplierName),
                                      ),
                                      IconButton(
                                        tooltip: 'PDF',
                                        icon: const Icon(Icons.picture_as_pdf),
                                        onPressed: () => _printSupplierPdf(
                                            r.supplierId, r.supplierName),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _amt(double v) =>
      Expanded(child: Text(_nf.format(v), textAlign: TextAlign.end));

  Widget _h(String s, {int flex = 1, bool alignEnd = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        s,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _chip(String label, String value, {bool filled = false}) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
      side: const BorderSide(color: AppColors.primary),
      backgroundColor: filled
          ? AppColors.primary.withOpacity(.12)
          : AppColors.primary.withOpacity(.06),
    );
  }
}

class _Row {
  final String supplierId;
  final String supplierName;
  final double b0_30;
  final double b31_60;
  final double b61_90;
  final double b91_120;
  final double b120p;
  final double total;

  _Row({
    required this.supplierId,
    required this.supplierName,
    required this.b0_30,
    required this.b31_60,
    required this.b61_90,
    required this.b91_120,
    required this.b120p,
    required this.total,
  });
}
