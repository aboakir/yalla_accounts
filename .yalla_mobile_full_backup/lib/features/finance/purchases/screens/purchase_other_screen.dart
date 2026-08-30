import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PurchaseOtherScreen extends StatefulWidget {
  const PurchaseOtherScreen({super.key});

  @override
  State<PurchaseOtherScreen> createState() => _PurchaseOtherScreenState();
}

class _PurchaseOtherScreenState extends State<PurchaseOtherScreen> {
  final _date = DateTime.now();
  final List<_Line> _lines = [];

  final _itemCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  bool _saving = false;
  String _workshopName = "الورشة";

  @override
  void initState() {
    super.initState();
    _loadWorkshopName();
  }

  Future<void> _loadWorkshopName() async {
    final prefs = await SharedPreferences.getInstance();
    _workshopName = prefs.getString("workshop_name") ?? "الورشة";
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  double get total => _lines.fold(0.0, (s, x) => s + (x.qty * x.price));

  void _addLine() {
    final item = _itemCtrl.text.trim();
    if (item.isEmpty) return;

    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (price <= 0) return;

    setState(() {
      _lines.add(_Line(item: item, qty: qty, price: price));
      _itemCtrl.clear();
      _qtyCtrl.clear();
      _priceCtrl.clear();
    });
  }

  Future<void> _saveInvoice() async {
    if (_lines.isEmpty) {
      _toast("أضف صنفًا واحدًا على الأقل");
      return;
    }

    setState(() => _saving = true);

    try {
      final List<Map<String, dynamic>> mappedLines = _lines
          .map((ln) => {
                "item": ln.item,
                "qty": ln.qty,
                "unit_price": ln.price,
                "total": ln.qty * ln.price,
                "category": "OTHER",
                "note": null,
              })
          .toList();

      await PurchaseInvoiceService.createInvoice(
        supplierId: 0, // لأن الفاتورة OTHER بلا مورد
        date: _date,
        method: "credit",
        note: "مشتريات تشغيلية عامة",
        purchaseType: "OTHER",
        items: mappedLines.map((ln) {
          return {
            "item_name": ln["item"],
            "qty": ln["qty"],
            "price": ln["unit_price"],
          };
        }).toList(),
      );

      _toast("تم حفظ الفاتورة بنجاح");
      Navigator.pop(context);
    } catch (e) {
      _toast("خطأ أثناء الحفظ: $e");
    } finally {
      setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat("yyyy-MM-dd");

    return Scaffold(
      appBar: YallaAppBar(
        workshopName: _workshopName,
        showSearch: false,
        showNotifications: false,
        showThemeToggle: false,
      ),
      drawer: const YallaSidebar(),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AdaptiveRow(children: [
              Text("التاريخ: ${df.format(_date)}",
                  style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 20),
            AdaptiveRow(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _itemCtrl,
                    decoration: InputDecoration(labelText: "الصنف"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    decoration: InputDecoration(labelText: "الكمية"),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    decoration: InputDecoration(labelText: "السعر"),
                    keyboardType: TextInputType.number,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  onPressed: _addLine,
                )
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _lines.length,
                itemBuilder: (_, i) {
                  final ln = _lines[i];
                  return Card(
                    child: ListTile(
                      title: Text(ln.item),
                      subtitle: Text("الكمية: ${ln.qty} × ${ln.price}"),
                      trailing:
                          Text("${MoneyFormatter.format((ln.qty * ln.price))}"),
                    ),
                  );
                },
              ),
            ),
            AdaptiveRow(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "الإجمالي: ${MoneyFormatter.format(total)}",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  onPressed: _saving ? null : _saveInvoice,
                  child: const Text("حفظ الفاتورة"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _Line {
  final String item;
  final double qty;
  final double price;
  _Line({required this.item, required this.qty, required this.price});
}
