// 📁 lib/features/repairs/screens/purchase_parts_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/repairs/models/purchase_part.dart';
import 'package:yalla_accounts/features/repairs/services/purchase_part_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PurchasePartsScreen extends ConsumerStatefulWidget {
  final String repairId;
  const PurchasePartsScreen({super.key, required this.repairId});

  @override
  ConsumerState<PurchasePartsScreen> createState() =>
      _PurchasePartsScreenState();
}

class _PurchasePartsScreenState extends ConsumerState<PurchasePartsScreen> {
  List<PurchasePart> purchases = [];
  final _partController = TextEditingController();
  final _costController = TextEditingController();
  DateTime _purchaseDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  Future<void> _loadPurchases() async {
    final data =
        await PurchasePartService.getPurchasesByRepair(widget.repairId);
    setState(() => purchases = data);
  }

  Future<void> _addPurchase() async {
    if (_partController.text.isEmpty || _costController.text.isEmpty) return;
    final newPurchase = PurchasePart(
      repairId: widget.repairId,
      partName: _partController.text,
      cost: double.tryParse(_costController.text) ?? 0,
      purchaseDate: _purchaseDate,
    );
    await PurchasePartService.addPurchase(newPurchase);
    _partController.clear();
    _costController.clear();
    _purchaseDate = DateTime.now();
    _loadPurchases();
  }

  Future<void> _deletePurchase(int id) async {
    await PurchasePartService.deletePurchase(id);
    _loadPurchases();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final isDesktop = Responsive.isDesktop(context);
    const currentRoute = '/purchases/parts';

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      appBar: AppBar(
        backgroundColor: Colors.green,
        title:
            const Text('🧩 قطع الغيار', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
                width: 260, child: YallaSidebar(currentRoute: currentRoute)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  AdaptiveRow(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _partController,
                          decoration:
                              const InputDecoration(labelText: 'اسم القطعة'),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _costController,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'التكلفة'),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _purchaseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _purchaseDate = picked);
                          }
                        },
                      ),
                      ElevatedButton(
                        onPressed: _addPurchase,
                        child: const Text('إضافة'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text('سجل المشتريات',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: purchases.length,
                      itemBuilder: (_, i) {
                        final p = purchases[i];
                        return ListTile(
                          title: Text(p.partName),
                          subtitle: Text('بتاريخ ${df.format(p.purchaseDate)}'),
                          trailing: AdaptiveRow(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${MoneyFormatter.format(p.cost)}'),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deletePurchase(p.id!),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
