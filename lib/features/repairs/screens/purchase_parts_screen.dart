// 📁 lib/features/repairs/screens/purchase_parts_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/repairs/models/purchase_part.dart';
import 'package:yalla_accounts/features/repairs/services/purchase_part_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

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

  Future<void> _showPhoneAddPart() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إضافة شراء قطعة',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _partController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                    labelText: 'اسم القطعة', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _costController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                    labelText: 'التكلفة', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: sheetContext,
                  initialDate: _purchaseDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null && mounted) {
                  setState(() => _purchaseDate = picked);
                }
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat('yyyy-MM-dd').format(_purchaseDate)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(50)),
              onPressed: () async {
                if (_partController.text.trim().isEmpty ||
                    _costController.text.trim().isEmpty) {
                  return;
                }
                await _addPurchase();
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('حفظ القطعة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhone(BuildContext context, DateFormat df) {
    final total = purchases.fold<double>(0, (sum, item) => sum + item.cost);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('قطع الغيار',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPurchases,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.lightGrey)),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text('${purchases.length} عملية شراء',
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(MoneyFormatter.format(total),
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (purchases.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Center(
                    child: Text('لا توجد مشتريات قطع لهذا الملف',
                        style: TextStyle(color: Colors.black54))),
              ),
            ...purchases.map((item) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 9),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: AppColors.lightGrey)),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    title: Text(item.partName,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(df.format(item.purchaseDate),
                        textAlign: TextAlign.right),
                    leading: IconButton(
                      tooltip: 'حذف',
                      onPressed: item.id == null
                          ? null
                          : () => _deletePurchase(item.id!),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    trailing: Text(MoneyFormatter.format(item.cost),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900)),
                  ),
                )),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _showPhoneAddPart,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة قطعة'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    if (MediaQuery.sizeOf(context).width < 600) return _buildPhone(context, df);
    final isDesktop = Responsive.isDesktop(context);
    const currentRoute = '/purchases/parts';

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title:
            const Text('🧩 قطع الغيار', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => AppRoutes.popOrDashboard(context),
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
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _partController,
                          decoration:
                              const InputDecoration(labelText: 'اسم القطعة'),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          inputFormatters: const [YallaDigitNormalizer()],
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
                              Text(MoneyFormatter.format(p.cost)),
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
