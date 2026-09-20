import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart';
import 'package:yalla_accounts/features/employees/services/employee_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairProfitabilityCard extends StatefulWidget {
  const RepairProfitabilityCard({
    super.key,
    required this.repairId,
    required this.isClosed,
  });

  final String repairId;
  final bool isClosed;

  @override
  State<RepairProfitabilityCard> createState() =>
      _RepairProfitabilityCardState();
}

class _RepairProfitabilityCardState extends State<RepairProfitabilityCard> {
  RepairProfitabilitySnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  final _date = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final snapshot = await RepairCostService.loadSnapshot(widget.repairId);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _label(String type) => RepairCostType.label(type);

  Widget _metric(String title, String value, IconData icon) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualCostDialog() async {
    var type = RepairCostType.parts;
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final wasteCtrl = TextEditingController(text: '0');
    final costCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? employeeId;
    List<Employee> employees = const [];
    try {
      employees = (await EmployeeService.getAllEmployees())
          .where((e) => e.status.toLowerCase() == 'active')
          .toList();
    } catch (_) {}
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final labor = type == RepairCostType.labor;
          return AdaptiveAlertDialog(
            title: const Text('إضافة تكلفة للملف'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration:
                          const InputDecoration(labelText: 'نوع التكلفة'),
                      items: RepairCostType.all
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(_label(v)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => type = v ?? type),
                    ),
                    const SizedBox(height: 10),
                    if (labor && employees.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: employeeId,
                        decoration: const InputDecoration(
                          labelText: 'الموظف / الفني',
                        ),
                        items: employees
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(e.fullName),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setLocal(() => employeeId = v);
                          final selected =
                              employees.where((e) => e.id == v).toList();
                          if (selected.isNotEmpty) {
                            nameCtrl.text = selected.first.fullName;
                          }
                        },
                      )
                    else
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: labor ? 'اسم العامل / الفني' : 'اسم البند',
                        ),
                      ),
                    if (labor && employees.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'وصف العمل / اسم الفني',
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: labor ? 'ساعات العمل' : 'الكمية المستخدمة',
                      ),
                    ),
                    if (!labor) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: wasteCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'كمية الهدر'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: costCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: labor ? 'تكلفة الساعة' : 'تكلفة الوحدة',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة اختيارية',
                      ),
                    ),
                    if (labor) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'تكلفة الساعة هنا تكلفة إدارية للملف، ولا تنشئ قيد راتب أو GL جديد.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
                    final waste = double.tryParse(wasteCtrl.text.trim()) ?? 0;
                    final unitCost = double.tryParse(costCtrl.text.trim()) ?? 0;
                    var itemName = nameCtrl.text.trim();
                    if (labor && itemName.isEmpty && employeeId != null) {
                      final selected =
                          employees.where((e) => e.id == employeeId).toList();
                      if (selected.isNotEmpty) {
                        itemName = selected.first.fullName;
                      }
                    }
                    await RepairCostService.addManualCost(
                      repairId: widget.repairId,
                      costType: type,
                      itemName: itemName,
                      quantityUsed: qty,
                      unitCost: unitCost,
                      wasteQuantity: waste,
                      employeeId: employeeId,
                      workHours: labor ? qty : null,
                      note: noteCtrl.text,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (e) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                          content: Text(
                              'تعذر حفظ التكلفة: ${UserFacingError.message(e)}')),
                    );
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
    qtyCtrl.dispose();
    wasteCtrl.dispose();
    costCtrl.dispose();
    noteCtrl.dispose();
    if (saved == true) await _reload();
  }

  Future<void> _showPurchaseLines() async {
    List<PurchaseCostCandidate> candidates;
    try {
      candidates = await RepairCostService.listAvailablePurchaseLines();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('تعذر تحميل المشتريات: ${UserFacingError.message(e)}')),
      );
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بنود مشتريات متاحة للتخصيص.')),
      );
      return;
    }
    final chosen = await showDialog<PurchaseCostCandidate>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('تخصيص بند مشتريات للملف'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: ListView.separated(
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = candidates[i];
              return ListTile(
                title: Text(c.itemName),
                subtitle: Text(
                  '${_date.format(c.date)} • متاح ${c.remainingQty} من ${c.purchasedQty} • ${MoneyFormatter.format(c.unitCost)} / وحدة',
                ),
                trailing: Text(_label(c.suggestedCostType)),
                onTap: () => Navigator.pop(dialogContext, c),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    if (chosen != null) await _showPurchaseAllocation(chosen);
  }

  Future<void> _showPurchaseAllocation(PurchaseCostCandidate candidate) async {
    var type = candidate.suggestedCostType;
    final qtyCtrl =
        TextEditingController(text: candidate.remainingQty.toString());
    final wasteCtrl = TextEditingController(text: '0');
    final noteCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AdaptiveAlertDialog(
          title: Text(candidate.itemName),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'المتاح للتخصيص: ${candidate.remainingQty} • تكلفة الوحدة: ${MoneyFormatter.format(candidate.unitCost)}',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'نوع التكلفة'),
                  items: const [
                    RepairCostType.parts,
                    RepairCostType.rawMaterial,
                    RepairCostType.paint,
                    RepairCostType.externalService,
                  ]
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(_label(v)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'الكمية المستخدمة'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: wasteCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'كمية الهدر'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration:
                      const InputDecoration(labelText: 'ملاحظة اختيارية'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'هذا تخصيص إداري لبند شراء مُرحّل سابقًا؛ لن يتم إنشاء مصروف أو قيد GL جديد.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await RepairCostService.allocatePurchaseLine(
                    repairId: widget.repairId,
                    purchaseLineId: candidate.lineId,
                    costType: type,
                    quantityUsed: double.tryParse(qtyCtrl.text.trim()) ?? 0,
                    wasteQuantity: double.tryParse(wasteCtrl.text.trim()) ?? 0,
                    note: noteCtrl.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                        content: Text(
                            'تعذر التخصيص: ${UserFacingError.message(e)}')),
                  );
                }
              },
              child: const Text('تخصيص'),
            ),
          ],
        ),
      ),
    );
    qtyCtrl.dispose();
    wasteCtrl.dispose();
    noteCtrl.dispose();
    if (saved == true) await _reload();
  }

  Future<void> _reverse(RepairCostEntry entry) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('عكس بند التكلفة'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'سبب العكس *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await RepairCostService.reverseEntry(
                  entryId: entry.id,
                  reason: reasonCtrl.text,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                      content:
                          Text('تعذر العكس: ${UserFacingError.message(e)}')),
                );
              }
            },
            child: const Text('عكس'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (ok == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            : _error != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تكلفة وربحية الملف',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('تعذر تحميل بيانات الربحية: $_error'),
                      TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  )
                : _buildLoaded(context),
      ),
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final s = _snapshot!;
    final margin = s.marginPercent == null
        ? '—'
        : '${s.marginPercent!.toStringAsFixed(2)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'تكلفة وربحية الملف',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            IconButton(
              onPressed: _reload,
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (widget.isClosed && !s.hasCostData)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: MaterialBanner(
              content: Text(
                'تنبيه: الملف مغلق ولا توجد له تكلفة مباشرة مسجلة؛ لا تعتبر الإيراد كاملًا ربحًا فعليًا.',
              ),
              actions: [SizedBox.shrink()],
            ),
          ),
        Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            _metric(
              'الإيراد المعترف به',
              MoneyFormatter.format(s.revenue),
              Icons.trending_up,
            ),
            _metric(
              'إجمالي التكلفة',
              MoneyFormatter.format(s.directCost),
              Icons.receipt_long_outlined,
            ),
            _metric(
              'الربح / الخسارة',
              MoneyFormatter.format(s.profit),
              s.profit >= 0 ? Icons.show_chart : Icons.trending_down,
            ),
            _metric('هامش الربح', margin, Icons.percent),
          ],
        ),
        const Divider(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final type in RepairCostType.all)
              Chip(
                label: Text(
                  '${_label(type)}: ${MoneyFormatter.format(s.amountFor(type))}',
                ),
              ),
            Chip(
              label: Text(
                'الهدر ضمن التكلفة: ${MoneyFormatter.format(s.wasteCost)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _showManualCostDialog,
              icon: const Icon(Icons.add),
              label: const Text('إضافة تكلفة'),
            ),
            OutlinedButton.icon(
              onPressed: _showPurchaseLines,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('تخصيص مشتريات'),
            ),
          ],
        ),
        if (s.entries.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'آخر بنود التكلفة',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ...s.entries.take(8).map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${entry.itemName} • ${_label(entry.costType)}',
                  ),
                  subtitle: Text(
                    '${_date.format(entry.createdAt)} • ${entry.sourceType == 'PURCHASE_LINE' ? 'من مشتريات' : 'إدخال مباشر'}'
                    '${entry.wasteQuantity > 0 ? ' • هدر ${entry.wasteQuantity}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        MoneyFormatter.format(entry.totalCost),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        tooltip: 'عكس بند التكلفة',
                        onPressed: () => _reverse(entry),
                        icon: const Icon(Icons.undo),
                      ),
                    ],
                  ),
                ),
              ),
        ],
        const SizedBox(height: 8),
        const Text(
          'الربحية هنا مباشرة للملف فقط. المصاريف العامة مثل الإيجار والكهرباء لا تدخل في هذا الرقم.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
