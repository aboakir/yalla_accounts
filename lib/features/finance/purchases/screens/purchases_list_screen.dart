import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/screens/purchases_list_screen.dart
// PREMIUM DESKTOP SCROLL v6 — Guaranteed Fix
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_details_screen.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

// ============================================================================
// FIXED BEHAVIOR — Scroll works with mouse & keyboard
// ============================================================================
class DesktopBehavior extends ScrollBehavior {
  const DesktopBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return Scrollbar(
      thumbVisibility: true,
      interactive: true,
      controller: details.controller,
      child: child,
    );
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

// ============================================================================
// SCREEN
// ============================================================================
class PurchasesListScreen extends StatefulWidget {
  const PurchasesListScreen({super.key});

  @override
  State<PurchasesListScreen> createState() => _PurchasesListScreenState();
}

class _PurchasesListScreenState extends State<PurchasesListScreen> {
  final ScrollController verticalCtrl = ScrollController();
  final ScrollController horizontalCtrl = ScrollController();

  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String _search = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    verticalCtrl.dispose();
    horizontalCtrl.dispose();
    super.dispose();
  }

  // ============================================================================
  // LOAD
  // ============================================================================
  Future<void> _load() async {
    setState(() => _loading = true);

    await DBService.inTx((txn) async {
      final invoices = await txn.rawQuery("""
SELECT 
  pi.id, pi.invoice_number,
  pi.date,
  pi.status, pi.amount_total AS original_amount_total,
  CASE WHEN UPPER(pi.status) IN ('VOID','CANCELLED','REVERSED') THEN 0 ELSE pi.amount_total END AS amount_total,
  ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
  pi.supplier_id,
  (SELECT name FROM suppliers s WHERE s.id = pi.supplier_id LIMIT 1)
      AS supplier_name
FROM purchase_invoices pi
ORDER BY pi.date DESC;
""");

      setState(() {
        _rows = invoices;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 950;

    return ScrollConfiguration(
      behavior: const DesktopBehavior(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FFF6),
        drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
        body: AdaptiveRow(
          children: [
            if (isDesktop) const YallaSidebar(),
            Expanded(
              child: Column(
                children: [
                  const YallaAppBar(workshopName: 'ورشتك'),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // BODY
  // ============================================================================
  Widget _buildBody() {
    if (!context.isDesktopWidth) return _buildPhoneBody();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildSearch(),
          const SizedBox(height: 20),
          _buildSummary(),
          const SizedBox(height: 20),
          _buildPdfBtn(),
          const SizedBox(height: 20),
          Expanded(
            child: _loading ? _loadingWidget() : _buildTable(),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredRows {
    final query = _search.toLowerCase();
    final from =
        _from == null ? null : DateTime(_from!.year, _from!.month, _from!.day);
    final toExclusive = _to == null
        ? null
        : DateTime(_to!.year, _to!.month, _to!.day)
            .add(const Duration(days: 1));
    return _rows.where((r) {
      final matchesSearch =
          '${r['supplier_name'] ?? ''} ${r['invoice_number'] ?? ''} ${r['id']}'
              .toLowerCase()
              .contains(query);
      if (!matchesSearch) return false;
      final date = DateTime.tryParse((r['date'] ?? '').toString());
      if (date == null) return from == null && toExclusive == null;
      if (from != null && date.isBefore(from)) return false;
      if (toExclusive != null && !date.isBefore(toExclusive)) return false;
      return true;
    }).toList();
  }

  double _amount(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toDouble() ?? 0;

  Future<void> _openPurchase(Map<String, dynamic> row) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PurchaseDetailsScreen(invoiceId: row['id'].toString()),
        ));
    if (mounted) await _load();
  }

  String _purchaseDate(Object? value) {
    final raw = value?.toString() ?? '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw.isEmpty ? 'تاريخ غير محدد' : raw;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _amounts(double total, double paid) {
    Widget cell(String label, double value, Color color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(MoneyFormatter.format(value),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ]),
          ),
        );
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cell('الإجمالي', total, Colors.black87),
        cell('المدفوع', paid, Colors.green.shade700),
        cell('المتبقي', total - paid, Colors.red.shade700),
      ]),
    );
  }

  Widget _buildPhoneBody() {
    final rows = _filteredRows;
    final total = rows.fold(0.0, (s, r) => s + _amount(r, 'amount_total'));
    final paid = rows.fold(0.0, (s, r) => s + _amount(r, 'paid_total'));
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(
                      child: Text('قائمة المشتريات',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold))),
                  IconButton(
                      tooltip: 'تصدير PDF',
                      onPressed: _generatePdf,
                      icon: const Icon(Icons.picture_as_pdf)),
                ]),
                _buildSearch(),
                const SizedBox(height: 12),
                Text('ملخص النتائج · ${rows.length} فاتورة',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _amounts(total, paid),
              ],
            ),
          )),
          if (_loading)
            SliverFillRemaining(hasScrollBody: false, child: _loadingWidget())
          else if (rows.isEmpty)
            const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('لا توجد فواتير شراء مطابقة')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => _purchaseCard(rows[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _purchaseCard(Map<String, dynamic> row) {
    final total = _amount(row, 'amount_total');
    final paid = _amount(row, 'paid_total');
    final remaining = total - paid;
    final status = ['VOID', 'CANCELLED', 'REVERSED'].contains(row['status'])
        ? 'ملغاة'
        : remaining <= 0.0001
            ? 'مسدد'
            : paid > 0.0001
                ? 'مسدد جزئيًا'
                : 'غير مسدد';
    final color = remaining <= 0.0001
        ? Colors.green.shade700
        : paid > 0.0001
            ? Colors.orange.shade800
            : Colors.red.shade700;
    final number = (row['invoice_number'] ?? '').toString().trim();
    final supplier = (row['supplier_name'] ?? '').toString().trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openPurchase(row),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.storefront_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(supplier.isEmpty ? 'مورد غير محدد' : supplier,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 8),
              Text('رقم الفاتورة: ${number.isEmpty ? row['id'] : number}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 6),
              Text('تاريخ الشراء: ${_purchaseDate(row['date'])}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              _amounts(total, paid),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text(status,
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold))),
                TextButton.icon(
                    onPressed: () => _openPurchase(row),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('تفاصيل الفاتورة')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // SEARCH + PERIOD FILTER
  Widget _buildSearch() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: context.isDesktopWidth ? 360 : double.infinity,
          child: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            decoration: InputDecoration(
              hintText: 'بحث باسم المورد أو رقم الفاتورة',
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
        ),
        FinancialPeriodFilter(
          from: _from,
          to: _to,
          onChanged: (range) => setState(() {
            _from = range.start;
            _to = range.end;
          }),
        ),
        if (_from != null || _to != null)
          TextButton.icon(
            onPressed: () => setState(() {
              _from = null;
              _to = null;
            }),
            icon: const Icon(Icons.clear),
            label: const Text('كل الفترات'),
          ),
      ],
    );
  }

  // SUMMARY
  Widget _buildSummary() {
    final rows = _filteredRows;
    final total = rows.fold(0.0, (s, r) => s + _amount(r, 'amount_total'));
    final paid = rows.fold(0.0, (s, r) => s + _amount(r, 'paid_total'));
    return AdaptiveRow(
      children: [
        _sum('إجمالي المشتريات', total),
        const SizedBox(width: 12),
        _sum('إجمالي المدفوع', paid),
        const SizedBox(width: 12),
        _sum('المتبقي', total - paid),
      ],
    );
  }

  Widget _sum(String t, double v) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(t),
            const SizedBox(height: 6),
            Text(
              v.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // // ============================================================================
// TABLE — FINAL DESKTOP SCROLL FIX
// ============================================================================
  Widget _buildTable() {
    final filtered = _filteredRows;

    if (filtered.isEmpty) {
      return const Center(child: Text('لا توجد فواتير شراء'));
    }

    return ScrollConfiguration(
      behavior: const DesktopBehavior(),
      child: Scrollbar(
        controller: verticalCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: verticalCtrl,
          scrollDirection: Axis.vertical,
          primary: false, // ← تم إصلاحها
          child: Scrollbar(
            controller: horizontalCtrl,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: horizontalCtrl,
              scrollDirection: Axis.horizontal,
              primary: false, // ← مهم جداً
              child: AdaptiveDataTable(
                columns: const [
                  DataColumn(label: Text("عرض")),
                  DataColumn(label: Text("المورد")),
                  DataColumn(label: Text("الإجمالي")),
                  DataColumn(label: Text("المدفوع")),
                  DataColumn(label: Text("المتبقي")),
                  DataColumn(label: Text("التاريخ")),
                ],
                rows: filtered.map((row) {
                  final remain = (row['amount_total'] as num).toDouble() -
                      (row['paid_total'] as num).toDouble();

                  return DataRow(
                    cells: [
                      DataCell(IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PurchaseDetailsScreen(
                                invoiceId: row['id'].toString(),
                              ),
                            ),
                          );
                        },
                      )),
                      DataCell(Text(row['supplier_name'] ?? 'بدون')),
                      DataCell(Text(
                          MoneyFormatter.format(row['amount_total'] as num))),
                      DataCell(Text(
                          MoneyFormatter.format(row['paid_total'] as num))),
                      DataCell(Text(remain.toStringAsFixed(2))),
                      DataCell(Text(row['date'].toString())),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // PDF BUTTON
  // ============================================================================
  Widget _buildPdfBtn() {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton.icon(
        onPressed: _generatePdf,
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text("تصدير PDF"),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Future<void> _generatePdf() async {
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لا توجد بيانات للطباعة")),
      );
      return;
    }

    final headers = [
      "رقم الفاتورة",
      "التاريخ",
      "المورد",
      "الإجمالي",
      "المدفوع",
      "المتبقي"
    ];

    final rows = _rows.map((r) {
      final remain = (r['amount_total'] as num).toDouble() -
          (r['paid_total'] as num).toDouble();

      return [
        r['id'].toString(),
        r['date'].toString(),
        (r['supplier_name'] ?? 'بدون').toString(),
        MoneyFormatter.format(r['amount_total'] as num),
        MoneyFormatter.format(r['paid_total'] as num),
        remain.toStringAsFixed(2),
      ];
    }).toList();

    final pdfBytes = await YallaPdfService.generateTablePdf(
      title: "قائمة فواتير المشتريات",
      headers: headers,
      rows: rows,
    );

    await YallaPdfService.saveAndOpen(
      bytes: pdfBytes,
      fileName: "Purchases_${DateTime.now().millisecondsSinceEpoch}.pdf",
    );
  }

  Widget _loadingWidget() => const Center(child: CircularProgressIndicator());
}
