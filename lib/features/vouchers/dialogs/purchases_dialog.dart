// -----------------------------------------------------------------------------
// 📁 lib/features/vouchers/dialogs/purchases_dialog.dart
// Dialog اختيار فواتير مشتريات غير مرتبطة بموردين
// - يجلب الفواتير من قاعدة البيانات
// - يعرض فقط الفواتير التي لا تحتوي supplierPid
// - ترتيب الأحدث ثم الأقدم
// - بحث كتابي مباشر
// - عند الاختيار: فتح نموذج سداد الفاتورة
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:intl/intl.dart';

class PurchasesDialog extends StatefulWidget {
  const PurchasesDialog({super.key});

  @override
  State<PurchasesDialog> createState() => _PurchasesDialogState();
}

class _PurchasesDialogState extends State<PurchasesDialog> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPurchases();
    _searchCtrl.addListener(_applySearch);
  }

  Future<void> _loadPurchases() async {
    final db = await DBService.database;

    final result = await db.rawQuery("""
      SELECT 
        id,
        date,
        total,
        paid,
        (total - paid) AS remaining
      FROM purchases
      WHERE (supplierPid IS NULL OR supplierPid = '')
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
        final date = row['date'].toString();
        return id.contains(q) || date.contains(q);
      }).toList();
    });
  }

  void _selectInvoice(Map<String, dynamic> row) {
    Navigator.pop(context, {
      "purchaseId": row['id'].toString(),
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
              "فواتير مشتريات غير مرتبطة بموردين",
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _searchCtrl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: "بحث برقم الفاتورة أو التاريخ",
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
