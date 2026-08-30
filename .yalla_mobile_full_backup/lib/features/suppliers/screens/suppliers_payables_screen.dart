// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/supplier_payables_screen.dart
// شاشة ذمم مورد واحد — FINAL VERSION (بدون Directionality)
// -----------------------------------------------------------------------------
// تعتمد على Localizations.override لفرض RTL بشكل نظامي ونظيف.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class SupplierPayablesScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;

  const SupplierPayablesScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
  });

  @override
  State<SupplierPayablesScreen> createState() => _SupplierPayablesScreenState();
}

class _SupplierPayablesScreenState extends State<SupplierPayablesScreen> {
  bool _loading = false;
  List<_InvoiceRow> _rows = [];

  final _nf = NumberFormat("#,##0.00");

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final db = await DBService.database;

    // 1) جلب PID

    // 2) جلب الفواتير
    final invoices = await db.rawQuery("""
SELECT 
  id,
  date,
  supplier_id,
  amount_total
FROM purchase_invoices
WHERE supplier_id = ?
ORDER BY date DESC
""", [widget.supplierId]);

    final List<_InvoiceRow> rows = [];

    for (final inv in invoices) {
      final String id = inv['id'].toString();
      final total = (inv['amount_total'] as num?)?.toDouble() ?? 0.0;

      final pays = await db.rawQuery("""
        SELECT SUM(amount) AS paid
        FROM purchase_payments
WHERE invoice_id = ?
      """, [id]);

      final paid = (pays.first['paid'] as num?)?.toDouble() ?? 0.0;
      final remain = total - paid;

      rows.add(
        _InvoiceRow(
          invoiceId: id,
          date: inv['date'].toString(),
          total: total,
          paid: paid,
          remain: remain,
        ),
      );
    }

    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // -------------------------------------------------------------------------
    // بديل Directionality: فرض اللغة العربية + RTL على الشاشة فقط
    // -------------------------------------------------------------------------
    return Localizations.override(
      context: context,
      locale: const Locale('ar'),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: Text("ذمم المورد: ${widget.supplierName}"),
              backgroundColor: AppColors.primary,
              centerTitle: true,
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(
                        child: Text(
                          "لا توجد ذمم على هذا المورد",
                          style: TextStyle(fontSize: 15, color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 0, color: Colors.grey.shade300),
                        itemBuilder: (_, i) {
                          final r = _rows[i];

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            title: Text(
                              "فاتورة: ${r.invoiceId}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            subtitle: Text(
                              "التاريخ: ${r.date}\n"
                              "الإجمالي: ${_nf.format(r.total)}  •  المدفوع: ${_nf.format(r.paid)}",
                            ),
                            trailing: Text(
                              _nf.format(r.remain),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: r.remain > 0
                                    ? Colors.red
                                    : Colors.green.shade700,
                              ),
                            ),

                            // -------------------------------------------------
                            // قائمة إجراءات الفاتورة
                            // -------------------------------------------------
                            onTap: () async {
                              final action = await showMenu(
                                context: context,
                                position:
                                    const RelativeRect.fromLTRB(200, 200, 0, 0),
                                items: const [
                                  PopupMenuItem(
                                    value: 'view',
                                    child: Text("عرض الفاتورة"),
                                  ),
                                  PopupMenuItem(
                                    value: 'pay',
                                    child: Text("سند صرف لهذه الفاتورة"),
                                  ),
                                ],
                              );

                              if (action == null) return;

                              switch (action) {
                                case 'view':
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.invoiceView,
                                    arguments: {
                                      'invoiceId': r.invoiceId,
                                    },
                                  );
                                  break;

                                case 'pay':
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.paymentVoucher,
                                    arguments: {
                                      'purchaseId': r.invoiceId,
                                      'supplierId': widget.supplierId,
                                      'supplierName': widget.supplierName,
                                      'presetAmount': r.remain,
                                    },
                                  );
                                  break;
                              }
                            },
                          );
                        },
                      ),
          );
        },
      ),
    );
  }
}

// نموذج صف للفواتير
class _InvoiceRow {
  final String invoiceId;
  final String date;
  final double total;
  final double paid;
  final double remain;

  _InvoiceRow({
    required this.invoiceId,
    required this.date,
    required this.total,
    required this.paid,
    required this.remain,
  });
}
