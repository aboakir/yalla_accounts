// -----------------------------------------------------------------------------
// 📁 lib/shared/widgets/purchase_picker.dart
// PurchasePicker — FIXED v51 (بدون pid – بدون supplierLabel)
// -----------------------------------------------------------------------------
// • يعمل مع بيانات purchase invoices v51
// • يعتمد فقط على الحقول الموجودة فعليًا:
//      id, supplier_id, amount_total, paid_total, status
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PurchasePickerResult {
  final String id;
  final String display;
  final int supplierId;
  final double amount;
  final double paid;
  final String status;

  PurchasePickerResult({
    required this.id,
    required this.display,
    required this.supplierId,
    required this.amount,
    required this.paid,
    required this.status,
  });
}

class PurchasePicker {
  static Future<PurchasePickerResult?> show({
    required BuildContext context,
    required List<Map<String, dynamic>> purchases,
  }) async {
    return showModalBottomSheet<PurchasePickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _PurchasePickerSheet(purchases: purchases),
    );
  }
}

class _PurchasePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> purchases;
  const _PurchasePickerSheet({required this.purchases});

  @override
  State<_PurchasePickerSheet> createState() => _PurchasePickerSheetState();
}

class _PurchasePickerSheetState extends State<_PurchasePickerSheet> {
  String query = "";

  @override
  Widget build(BuildContext context) {
    final filtered = widget.purchases.where((p) {
      final text =
          "${p["supplier_id"]} ${p["amount_total"]} ${p["paid_total"]} ${p["status"]}"
              .toString()
              .toLowerCase();
      return text.contains(query.toLowerCase());
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              decoration: InputDecoration(
                hintText: "ابحث عن فاتورة مشتريات...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text("لا توجد نتائج مطابقة"))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];

                        final id = p["id"].toString();
                        final supplierId = (p["supplier_id"] as num).toInt();
                        final amount =
                            (p["amount_total"] as num?)?.toDouble() ?? 0.0;
                        final paid =
                            (p["paid_total"] as num?)?.toDouble() ?? 0.0;
                        final status = p["status"] ?? "UNPAID";

                        final display =
                            "فاتورة: $id\nالمورد: $supplierId\nالمبلغ: ${MoneyFormatter.format(amount)}\nالمدفوع: $paid\nالحالة: $status";

                        return Card(
                          elevation: 1,
                          child: ListTile(
                            title: Text(display, textAlign: TextAlign.right),
                            onTap: () {
                              Navigator.of(context).pop(
                                PurchasePickerResult(
                                  id: id,
                                  display: display,
                                  supplierId: supplierId,
                                  amount: amount,
                                  paid: paid,
                                  status: status,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
