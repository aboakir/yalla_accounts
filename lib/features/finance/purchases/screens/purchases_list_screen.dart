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
import 'package:yalla_accounts/features/finance/purchases/screens/purchase_create_screen.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

// ============================================================================
// FIXED BEHAVIOR — Scroll works with mouse & keyboard
// ============================================================================
class DesktopBehavior extends ScrollBehavior {
  const DesktopBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails d) {
    return Scrollbar(
      thumbVisibility: true,
      interactive: true,
      controller: d.controller,
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

  double totalAmount = 0;
  double totalPaid = 0;
  double totalRemain = 0;

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
  pi.id,
  pi.date,
  pi.amount_total,
  IFNULL((SELECT SUM(p.amount) FROM payments p 
          WHERE p.invoice_id = pi.id AND p.isIncome = 0), 0) AS paid_total,
  pi.supplier_id,
  (SELECT name FROM suppliers s WHERE s.id = pi.supplier_id LIMIT 1)
      AS supplier_name
FROM purchase_invoices pi
ORDER BY pi.date DESC;
""");

      totalAmount = invoices.fold(0.0,
          (sum, r) => sum + ((r['amount_total'] as num?)?.toDouble() ?? 0));

      totalPaid = invoices.fold(
          0.0, (sum, r) => sum + ((r['paid_total'] as num?)?.toDouble() ?? 0));

      totalRemain = totalAmount - totalPaid;

      setState(() {
        _rows = invoices;
        _loading = false;
      });
    });
  }

  void _openAdd() async {
    await PurchaseCreateScreen.open(context);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 950;

    return ScrollConfiguration(
      behavior: const DesktopBehavior(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FFF6),
        drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
        body: Row(
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

  // SEARCH
  Widget _buildSearch() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'بحث باسم المورد أو رقم الفاتورة',
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (v) => setState(() => _search = v.trim()),
    );
  }

  // SUMMARY
  Widget _buildSummary() {
    return Row(
      children: [
        _sum('إجمالي المشتريات', totalAmount),
        const SizedBox(width: 12),
        _sum('إجمالي المدفوع', totalPaid),
        const SizedBox(width: 12),
        _sum('المتبقي', totalRemain),
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
    final filtered = _rows.where((r) {
      final supplier = (r['supplier_name'] ?? '').toString();
      final id = r['id'].toString();
      return supplier.contains(_search) || id.contains(_search);
    }).toList();

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
              child: DataTable(
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
