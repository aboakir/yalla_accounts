// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/suppliers_payables_list_screen.dart
// ذمم الموردين — تصميم احترافي + بحث + PDF
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SupplierPayablesListScreen extends StatefulWidget {
  const SupplierPayablesListScreen({super.key});

  @override
  State<SupplierPayablesListScreen> createState() =>
      _SupplierPayablesListScreenState();
}

class _SupplierPayablesListScreenState
    extends State<SupplierPayablesListScreen> {
  bool _loading = false;
  List<_SupplierRow> _rows = [];
  List<_SupplierRow> _filtered = [];
  double totalAll = 0;
  double totalPaid = 0;
  double totalRemaining = 0;

  final _nf = NumberFormat("#,##0.00");
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applySearch);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // تحميل البيانات
  // ---------------------------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await DBService.database;

    final data = await db.rawQuery("""
      SELECT 
        s.id AS supplier_id,
        s.name AS name,
        IFNULL(SUM(p.amount_total), 0) AS total_purchases,
        IFNULL(SUM(p.paid_total), 0) AS total_paid,
        IFNULL(SUM(p.remaining), 0) AS total_remaining
      FROM suppliers s
      LEFT JOIN purchase_invoices p
        ON p.supplier_id = s.id
      GROUP BY s.id, s.name
      ORDER BY s.name ASC;
    """);

    _rows = data.map((r) {
      return _SupplierRow(
        id: r['supplier_id'].toString(),
        name: r['name']?.toString() ?? '',
        total: (r['total_purchases'] as num?)?.toDouble() ?? 0.0,
        paid: (r['total_paid'] as num?)?.toDouble() ?? 0.0,
        remain: (r['total_remaining'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    // إجماليات KPIs
    totalAll = _rows.fold(0, (sum, r) => sum + r.total);
    totalPaid = _rows.fold(0, (sum, r) => sum + r.paid);
    totalRemaining = _rows.fold(0, (sum, r) => sum + r.remain);

    _filtered = List.from(_rows);

    setState(() => _loading = false);
  }

  // ---------------------------------------------------------------------------
  // البحث الفوري
  // ---------------------------------------------------------------------------
  void _applySearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _filtered = List.from(_rows));
      return;
    }

    setState(() {
      _filtered = _rows.where((r) {
        return r.name.contains(q) || r.total.toString().contains(q);
      }).toList();
    });
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------
  Future<void> _exportPdf() async {
    if (_filtered.isEmpty) return;

    await YallaPdfService.generateSupplierPayablesPdf(
      _filtered
          .map((e) => {
                'name': e.name,
                'total': e.total,
                'paid': e.paid,
                'remain': e.remain,
              })
          .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // واجهة الشاشة
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      locale: const Locale('ar'),
      child: LayoutBuilder(builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;

        return Scaffold(
          backgroundColor: Colors.white,
          drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            title: const Text("ذمم الموردين",
                style: TextStyle(color: Colors.white)),
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                tooltip: "تصدير PDF",
                onPressed: _exportPdf,
              ),
            ],
          ),
          body: AdaptiveRow(
            children: [
              if (isDesktop) const SizedBox(width: 260, child: YallaSidebar()),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContent(),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // المحتوى الكامل
  // ---------------------------------------------------------------------------
  Widget _buildContent() {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildKPIs(),
        const SizedBox(height: 20),
        _buildSearchBox(),
        const SizedBox(height: 10),
        Expanded(child: _buildTable()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // صندوق البحث الاحترافي
  // ---------------------------------------------------------------------------
  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            hintText: "بحث باسم المورد...",
            border: InputBorder.none,
            icon: Icon(Icons.search),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // KPIs
  // ---------------------------------------------------------------------------
  Widget _buildKPIs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AdaptiveRow(
        children: [
          _kpiBox("إجمالي المشتريات", totalAll, Colors.blue),
          _kpiBox("إجمالي المدفوع", totalPaid, Colors.green),
          _kpiBox("المتبقي", totalRemaining, Colors.red),
        ],
      ),
    );
  }

  Widget _kpiBox(String title, double value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_nf.format(value),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // جدول العرض
  // ---------------------------------------------------------------------------
  Widget _buildTable() {
    if (_filtered.isEmpty) {
      return const Center(
        child: Text("لا توجد نتائج", style: TextStyle(fontSize: 16)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) =>
          Divider(height: 0, color: Colors.grey.shade300),
      itemBuilder: (_, i) {
        final r = _filtered[i];

        return InkWell(
          onTap: null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        "الإجمالي: ${_nf.format(r.total)}   •   المدفوع: ${_nf.format(r.paid)}",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Text(
                  _nf.format(r.remain),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: r.remain > 0 ? Colors.red : Colors.green.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                AdaptiveRow(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'كشف حساب',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () {
                        Navigator.of(context).pushNamed(
                          AppRoutes.purchasesSupplierLedger,
                          arguments: {
                            'supplierId': r.id,
                            'supplierName': r.name,
                          },
                        );
                      },
                    ),
                    Icon(Icons.arrow_back_ios,
                        size: 16, color: Colors.grey.shade600),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// موديل داخلي
// -----------------------------------------------------------------------------
class _SupplierRow {
  final String id;
  final String name;
  final double total;
  final double paid;
  final double remain;

  _SupplierRow({
    required this.id,
    required this.name,
    required this.total,
    required this.paid,
    required this.remain,
  });
}
