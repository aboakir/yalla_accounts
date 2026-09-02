// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/suppliers_debts_screen.dart
// شاشة أرصدة الموردين — FINAL VERSION (بدون Directionality)
// -----------------------------------------------------------------------------
// تعتمد على Localizations.override لفرض RTL بشكل نظامي ونظيف.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class SuppliersDebtsScreen extends StatefulWidget {
  const SuppliersDebtsScreen({super.key});

  @override
  State<SuppliersDebtsScreen> createState() => _SuppliersDebtsScreenState();
}

class _SuppliersDebtsScreenState extends State<SuppliersDebtsScreen> {
  bool _loading = false;
  List<_SupplierDebtRow> _rows = [];

  final _nf = NumberFormat("#,##0.00");

  @override
  void initState() {
    super.initState();
    _loadDebts();
  }

  Future<void> _loadDebts() async {
    setState(() => _loading = true);

    final db = await DBService.database;

    // 1) جلب الموردين
    final suppliers = await db.rawQuery("""
      SELECT id, pid, name, phone
      FROM suppliers
      ORDER BY LOWER(name) ASC
    """);

    final List<_SupplierDebtRow> rows = [];

    // 2) حساب رصيد كل مورد
    for (final s in suppliers) {
      final id = s['id'].toString();
      final name = s['name']?.toString() ?? '';
      final pid = s['pid']?.toString() ?? '';

      // مجموع الفواتير
      final invoices = await db.rawQuery("""
        SELECT SUM(total) AS t
        FROM purchase_invoices
        WHERE supplierPid = ?
      """, [pid]);

      final total = (invoices.first['t'] as num?)?.toDouble() ?? 0.0;

      // مجموع المدفوعات
      final pays = await db.rawQuery("""
        SELECT SUM(amount) AS p
        FROM purchase_payments
        WHERE supplierPid = ?
      """, [pid]);

      final paid = (pays.first['p'] as num?)?.toDouble() ?? 0.0;

      final balance = total - paid;

      rows.add(
        _SupplierDebtRow(
          supplierId: id,
          supplierPid: pid,
          name: name,
          total: total,
          paid: paid,
          balance: balance,
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
    // بديل Directionality: فرض اللغة العربية فقط على هذه الشاشة
    // -------------------------------------------------------------------------
    return Localizations.override(
      context: context,
      locale: const Locale('ar'),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text("أرصدة الموردين"),
              backgroundColor: AppColors.primary,
              centerTitle: true,
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(
                        child: Text(
                          "لا يوجد موردون",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
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
                                horizontal: 12, vertical: 6),
                            title: Text(
                              r.name,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              "الإجمالي: ${_nf.format(r.total)}  •  المدفوع: ${_nf.format(r.paid)}",
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              _nf.format(r.balance),
                              style: TextStyle(
                                fontSize: 16,
                                color: r.balance > 0
                                    ? Colors.red
                                    : Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            // -------------------------------------------------
                            // قائمة إجراءات للمورد
                            // -------------------------------------------------
                            onTap: () async {
                              final action = await showMenu(
                                context: context,
                                position:
                                    const RelativeRect.fromLTRB(200, 200, 0, 0),
                                items: const [
                                  PopupMenuItem(
                                    value: 'account',
                                    child: Text("كشف حساب"),
                                  ),
                                  PopupMenuItem(
                                    value: 'payment',
                                    child: Text("إنشاء سند صرف"),
                                  ),
                                ],
                              );

                              if (action == null) return;

                              switch (action) {
                                case 'account':
                                  AppRoutes.openSupplierLedger(
                                    context,
                                    supplierId: r.supplierId,
                                    supplierName: r.name,
                                  );
                                  break;

                                case 'payment':
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.paymentVoucher,
                                    arguments: {
                                      'supplierPid': r.supplierPid,
                                      'supplierName': r.name,
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

// نموذج صف
class _SupplierDebtRow {
  final String supplierId;
  final String supplierPid;
  final String name;
  final double total;
  final double paid;
  final double balance;

  _SupplierDebtRow({
    required this.supplierId,
    required this.supplierPid,
    required this.name,
    required this.total,
    required this.paid,
    required this.balance,
  });
}
