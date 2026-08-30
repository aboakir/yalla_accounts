// -----------------------------------------------------------------------------
// 📁 lib/features/vouchers/dialogs/supplier_purchase_dialog.dart
// Dialog اختيار فواتير مشتريات مرتبطة بمورد
// - يجلب الفواتير من قاعدة البيانات
// - يعرض فقط الفواتير التي تحتوي supplierPid
// - ترتيب الأحدث ثم الأقدم
// - بحث كتابي مباشر
// - عند الاختيار: إرجاع purchaseId + supplierPid + supplierName + remaining
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:intl/intl.dart';

class SupplierPurchaseDialog extends StatefulWidget {
  const SupplierPurchaseDialog({super.key});

  @override
  State<SupplierPurchaseDialog> createState() => _SupplierPurchaseDialogState();
}

class _SupplierPurchaseDialogState extends State<SupplierPurchaseDialog> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSupplierPurchases();
    _searchCtrl.addListener(_applySearch);
  }

  Future<void> _loadSupplierPurchases() async {
    final db = await DBService.database;

    final result = await db.rawQuery("""
      SELECT 
        id,
        date,
        supplierPid,
        supplierName,
        total,
        paid,
        (total - paid) AS remaining
      FROM purchases
      WHERE supplierPid IS NOT NULL 
        AND supplierPid != ''
      ORDER BY date DESC
    """);

    setState(() {
      _rows = result;
      _filtered = result;
      _loading = false;
    });
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _filtered = _rows);
      return;
    }

    setState(() {
      _filtered = _rows.where((row) {
        final id = row['id'].toString();
        final name = (row['supplierName'] ?? '').toString();
        return id.contains(q) || name.contains(q);
      }).toList();
    });
  }

  void _selectInvoice(Map<String, dynamic> row) {
    Navigator.pop(context, {
      "purchaseId": row['id'].toString(),
      "supplierPid": row['supplierPid'] ?? '',
      "supplierName": row['supplierName'] ?? '',
      "remaining": row['remaining'] ?? 0.0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
      ),
      child: Container(
        width: MediaQuery.sizeOf(context).width < 600
            ? MediaQuery.sizeOf(context).width - 32
            : 750,
        height: MediaQuery.sizeOf(context).width < 600
            ? MediaQuery.sizeOf(context).height * 0.82
            : 540,
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              "فواتير مشتريات مرتبطة بمورد",
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _searchCtrl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: "بحث باسم المورد أو رقم الفاتورة",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        "لا توجد فواتير مطابقة",
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final row = _filtered[i];
                        final date = DateFormat(
                          'yyyy-MM-dd',
                        ).format(DateTime.parse(row['date']));
                        final remaining = (row['remaining'] ?? 0.0)
                            .toStringAsFixed(2);
                        final supplierName = (row['supplierName'] ?? '')
                            .toString();

                        return InkWell(
                          onTap: () => _selectInvoice(row),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "فاتورة رقم: ${row['id']}",
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "المورد: $supplierName",
                                  textAlign: TextAlign.right,
                                ),
                                Text(
                                  "التاريخ: $date",
                                  textAlign: TextAlign.right,
                                ),
                                Text(
                                  "المتبقي: $remaining",
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إغلاق"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
