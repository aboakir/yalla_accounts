import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/services/db/tables/inventory_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/platform/yalla_path_provider.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/features/inventory/services/canonical_inventory_service.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_operations_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_cost_service.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key, this.itemKind});
  final String? itemKind;

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  final _uuid = const Uuid();
  bool _loading = true;
  String? _error;
  int? _warehouseId;
  List<_InventoryRow> _rows = const [];
  String _query = '';

  List<_InventoryRow> get _visibleRows {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((row) {
      final haystack = [
        row.name,
        row.sku ?? '',
        row.kind,
        row.unit,
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList(growable: false);
  }

  double get _visibleStockValue => _visibleRows.fold<double>(
        0,
        (sum, row) => sum + row.stockValue,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int> _ensureWarehouse() async {
    final db = await DBService.database;
    final rows = await db.query(
      InventoryTables.warehouses,
      columns: const ['id'],
      where: 'is_active=1',
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isNotEmpty) return (rows.single['id'] as num).toInt();
    return CanonicalInventoryService.createWarehouse(
      code: 'MAIN',
      name: 'المخزن الرئيسي',
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await DBService.database;
      await InventoryOperationsService.ensureOperationalTables(db);
      final warehouseId = await _ensureWarehouse();
      final rows = await db.query(
        InventoryTables.items,
        where: widget.itemKind == null
            ? 'is_active=1'
            : 'is_active=1 AND item_kind=?',
        whereArgs: widget.itemKind == null ? null : [widget.itemKind],
        orderBy: 'name COLLATE NOCASE ASC, id ASC',
      );
      final out = <_InventoryRow>[];
      for (final item in rows) {
        final id = (item['id'] as num).toInt();
        final valuation = await InventoryOperationsService.valuation(
          itemId: id,
          warehouseId: warehouseId,
          executor: db,
        );
        final reorder = await InventoryOperationsService.reorderStatus(
          itemId: id,
          warehouseId: warehouseId,
          executor: db,
        );
        out.add(_InventoryRow(
          id: id,
          name: item['name']?.toString() ?? '',
          sku: item['sku']?.toString(),
          kind: item['item_kind']?.toString() ?? 'OTHER',
          unit: item['unit']?.toString() ?? 'pcs',
          onHand: valuation.onHand,
          averageCost: valuation.averageUnitCost,
          stockValue: valuation.stockValue,
          reorderLevel: reorder.reorderLevel,
          needsReorder: reorder.needsReorder,
        ));
      }
      if (!mounted) return;
      setState(() {
        _warehouseId = warehouseId;
        _rows = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _csvCell(String value) {
    final clean = value.replaceAll('"', '""');
    return '"$clean"';
  }

  Future<void> _exportCsv() async {
    try {
      final rows = _visibleRows;
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات مخزون للتصدير')),
        );
        return;
      }

      final sb = StringBuffer()
        ..writeln([
          'sku',
          'item',
          'kind',
          'unit',
          'on_hand',
          'average_cost',
          'stock_value',
          'reorder_level',
          'needs_reorder',
        ].map(_csvCell).join(','));

      for (final row in rows) {
        sb.writeln([
          row.sku ?? '',
          row.name,
          row.kind,
          row.unit,
          row.onHand.toStringAsFixed(2),
          row.averageCost.toStringAsFixed(2),
          row.stockValue.toStringAsFixed(2),
          row.reorderLevel.toStringAsFixed(2),
          row.needsReorder ? 'YES' : 'NO',
        ].map(_csvCell).join(','));
      }
      sb.writeln([
        'TOTAL',
        '',
        '',
        '',
        '',
        '',
        _visibleStockValue.toStringAsFixed(2),
        '',
        '',
      ].map(_csvCell).join(','));

      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getTemporaryDirectory();
      final file = File('${dir.path}/inventory_report.csv');
      await file.writeAsString(sb.toString(), encoding: utf8);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Inventory Report Export',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل تصدير المخزون: ${UserFacingError.message(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _exportPdf() async {
    try {
      final rows = _visibleRows;
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات مخزون للطباعة')),
        );
        return;
      }

      final bytes = await YallaPdfService.generateTablePdf(
        title: 'تقرير المخزون',
        headers: const [
          'الرمز',
          'الصنف',
          'الوحدة',
          'الرصيد',
          'متوسط التكلفة',
          'قيمة المخزون',
          'إعادة الطلب',
        ],
        rows: [
          for (final row in rows)
            [
              row.sku ?? '',
              row.name,
              row.unit,
              row.onHand.toStringAsFixed(2),
              row.averageCost.toStringAsFixed(2),
              row.stockValue.toStringAsFixed(2),
              row.needsReorder ? 'نعم' : 'لا',
            ],
          [
            'الإجمالي',
            '',
            '',
            '',
            '',
            _visibleStockValue.toStringAsFixed(2),
            '',
          ],
        ],
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل طباعة تقرير المخزون: ${UserFacingError.message(e)}',
          ),
        ),
      );
    }
  }

  Future<String?> _askText(
    String title,
    String label, {
    String? initial,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _addItem() async {
    final name = await _askText('إضافة صنف', 'اسم الصنف');
    if (name == null || name.isEmpty) return;
    final sku = await _askText('إضافة صنف', 'الرمز / SKU');
    if (sku == null) return;
    final unit = await _askText(
      'إضافة صنف',
      'الوحدة الأساسية',
      initial: widget.itemKind == 'RAW_MATERIAL' ? 'liter' : 'pcs',
    );
    if (unit == null || unit.isEmpty) return;
    final purchaseText = await _askText(
      'إضافة صنف',
      'سعر الشراء الافتراضي',
      initial: '0',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (purchaseText == null) return;
    final price = double.tryParse(purchaseText) ?? 0;
    final id = await CanonicalInventoryService.createItem(
      name: name,
      sku: sku.isEmpty ? null : sku,
      unit: unit,
      itemKind: widget.itemKind ?? 'OTHER',
      category: widget.itemKind == 'RAW_MATERIAL' ? 'RAW_MATERIAL' : null,
      defaultPurchasePrice: price > 0 ? price : null,
    );
    if (_warehouseId != null) {
      await InventoryOperationsService.setReorderLevel(
        itemId: id,
        warehouseId: _warehouseId!,
        level: 0,
      );
    }
    await _load();
  }

  Future<void> _showCard(_InventoryRow row) async {
    final card = await InventoryOperationsService.stockCard(
      itemId: row.id,
      warehouseId: _warehouseId!,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('كرت الصنف — ${row.name}'),
        content: SizedBox(
          width: 720,
          child: card.isEmpty
              ? const Text('لا توجد حركات')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: card.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final m = card[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${m.movementType}  ${m.quantityDelta.toStringAsFixed(2)}',
                      ),
                      subtitle: Text(
                        'التكلفة ${m.unitCost.toStringAsFixed(2)} · '
                        'الرصيد ${m.runningOnHand.toStringAsFixed(2)} · '
                        'القيمة ${m.runningValue.toStringAsFixed(2)}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _setReorder(_InventoryRow row) async {
    final value = await _askText(
      'حد إعادة الطلب',
      'الحد',
      initial: row.reorderLevel.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (value == null) return;
    final level = double.tryParse(value);
    if (level == null || level < 0) return;
    await InventoryOperationsService.setReorderLevel(
      itemId: row.id,
      warehouseId: _warehouseId!,
      level: level,
    );
    await _load();
  }

  Future<void> _adjust(_InventoryRow row) async {
    final value = await _askText(
      'تسوية الجرد',
      'الكمية الفعلية',
      initial: row.onHand.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (value == null) return;
    final qty = double.tryParse(value);
    if (qty == null || qty < 0 || (qty - row.onHand).abs() < 0.000001) return;
    final reason = await _askText('تسوية الجرد', 'السبب');
    if (reason == null || reason.isEmpty) return;
    await InventoryOperationsService.adjustToCount(
      operationId: _uuid.v4(),
      itemId: row.id,
      warehouseId: _warehouseId!,
      countedOnHand: qty,
      reason: reason,
    );
    await _load();
  }

  Future<void> _damage(_InventoryRow row) async {
    final value = await _askText(
      'تسجيل تلف',
      'الكمية التالفة',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (value == null) return;
    final qty = double.tryParse(value);
    if (qty == null || qty <= 0) return;
    final reason = await _askText('تسجيل تلف', 'سبب التلف');
    if (reason == null || reason.isEmpty) return;
    await InventoryOperationsService.damageStock(
      operationId: _uuid.v4(),
      itemId: row.id,
      warehouseId: _warehouseId!,
      quantity: qty,
      reason: reason,
    );
    await _load();
  }

  Future<void> _issue(_InventoryRow row) async {
    final repairId = await _askText('صرف إلى ملف إصلاح', 'معرف ملف الإصلاح');
    if (repairId == null || repairId.isEmpty) return;
    final value = await _askText(
      'صرف إلى ملف إصلاح',
      'الكمية',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (value == null) return;
    final qty = double.tryParse(value);
    if (qty == null || qty <= 0) return;
    await InventoryOperationsService.issueToRepair(
      operationId: _uuid.v4(),
      repairId: repairId,
      itemId: row.id,
      warehouseId: _warehouseId!,
      quantity: qty,
      costType: row.kind == 'PART'
          ? RepairCostType.parts
          : RepairCostType.rawMaterial,
    );
    await _load();
  }

  Future<void> _return(_InventoryRow row) async {
    final db = await DBService.database;
    await InventoryOperationsService.ensureOperationalTables(db);
    final issues = await db.rawQuery(
      "SELECT id,repair_id,quantity_issued,quantity_returned "
      "FROM inventory_repair_issues "
      "WHERE item_id=? AND warehouse_id=? AND status='ACTIVE' "
      "ORDER BY datetime(created_at) DESC",
      [row.id, _warehouseId],
    );
    if (issues.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد صرف مفتوح يمكن إرجاعه')),
      );
      return;
    }
    if (!mounted) return;
    String selected = issues.first['id'].toString();
    final issueId = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('اختيار حركة الصرف'),
          content: DropdownButtonFormField<String>(
            value: selected,
            items: issues.map((issue) {
              final remaining = (issue['quantity_issued'] as num).toDouble() -
                  (issue['quantity_returned'] as num).toDouble();
              return DropdownMenuItem(
                value: issue['id'].toString(),
                child: Text(
                  '${issue['repair_id']} · متبقي ${remaining.toStringAsFixed(2)}',
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) setLocal(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('اختيار'),
            ),
          ],
        ),
      ),
    );
    if (issueId == null) return;
    final value = await _askText(
      'إرجاع من ملف إصلاح',
      'الكمية المرتجعة',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (value == null) return;
    final qty = double.tryParse(value);
    if (qty == null || qty <= 0) return;
    await InventoryOperationsService.returnFromRepair(
      operationId: _uuid.v4(),
      issueId: issueId,
      quantity: qty,
    );
    await _load();
  }

  Future<void> _runAction(String action, _InventoryRow row) async {
    switch (action) {
      case 'card':
        await _showCard(row);
        break;
      case 'issue':
        await _issue(row);
        break;
      case 'return':
        await _return(row);
        break;
      case 'adjust':
        await _adjust(row);
        break;
      case 'damage':
        await _damage(row);
        break;
      case 'reorder':
        await _setReorder(row);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.itemKind == 'RAW_MATERIAL' ? 'المواد والمخزون' : 'إدارة المخزون';
    final compact = MediaQuery.sizeOf(context).width < 600;
    final visibleRows = _visibleRows;
    final reorderCount = visibleRows.where((row) => row.needsReorder).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: compact
            ? [
                PopupMenuButton<String>(
                  tooltip: 'خيارات التقرير',
                  onSelected: (value) {
                    switch (value) {
                      case 'csv':
                        _exportCsv();
                        break;
                      case 'pdf':
                        _exportPdf();
                        break;
                      case 'refresh':
                        _load();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'csv',
                      child: Text('تصدير CSV'),
                    ),
                    PopupMenuItem(
                      value: 'pdf',
                      child: Text('طباعة PDF'),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text('تحديث'),
                    ),
                  ],
                ),
              ]
            : [
                IconButton(
                  tooltip: 'تصدير CSV',
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton(
                  tooltip: 'طباعة PDF',
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('صنف'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('خطأ: $_error'))
              : _rows.isEmpty
                  ? const Center(child: Text('لا توجد أصناف في المخزون'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: visibleRows.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          if (index == 0) {
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        Chip(
                                          label: Text(
                                            'الأصناف: ${visibleRows.length}',
                                            key: const ValueKey(
                                              'inventory-report-item-count',
                                            ),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            'قيمة المخزون: ${_visibleStockValue.toStringAsFixed(2)}',
                                            key: const ValueKey(
                                              'inventory-report-total-value',
                                            ),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            'إعادة الطلب: $reorderCount',
                                            key: const ValueKey(
                                              'inventory-report-reorder-count',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      key: const ValueKey(
                                        'inventory-report-search',
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'بحث في المخزون',
                                        prefixIcon: Icon(Icons.search),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (value) {
                                        setState(() => _query = value);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final row = visibleRows[index - 1];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          row.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: 'إجراءات',
                                        onSelected: (value) =>
                                            _runAction(value, row),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'card',
                                            child: Text('كرت الصنف'),
                                          ),
                                          PopupMenuItem(
                                            value: 'issue',
                                            child: Text('صرف لملف إصلاح'),
                                          ),
                                          PopupMenuItem(
                                            value: 'return',
                                            child: Text('إرجاع من ملف إصلاح'),
                                          ),
                                          PopupMenuItem(
                                            value: 'adjust',
                                            child: Text('تسوية جرد'),
                                          ),
                                          PopupMenuItem(
                                            value: 'damage',
                                            child: Text('تسجيل تلف'),
                                          ),
                                          PopupMenuItem(
                                            value: 'reorder',
                                            child: Text('حد إعادة الطلب'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 6,
                                    children: [
                                      Text('الرمز: ${row.sku ?? '—'}'),
                                      Text('الوحدة: ${row.unit}'),
                                      Text(
                                        'الرصيد: ${row.onHand.toStringAsFixed(2)}',
                                      ),
                                      Text(
                                        'متوسط التكلفة: ${row.averageCost.toStringAsFixed(2)}',
                                      ),
                                      Text(
                                        'قيمة المخزون: ${row.stockValue.toStringAsFixed(2)}',
                                      ),
                                    ],
                                  ),
                                  if (row.needsReorder)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text(
                                        'وصل الصنف إلى حد إعادة الطلب',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _InventoryRow {
  const _InventoryRow({
    required this.id,
    required this.name,
    required this.sku,
    required this.kind,
    required this.unit,
    required this.onHand,
    required this.averageCost,
    required this.stockValue,
    required this.reorderLevel,
    required this.needsReorder,
  });

  final int id;
  final String name;
  final String? sku;
  final String kind;
  final String unit;
  final double onHand;
  final double averageCost;
  final double stockValue;
  final double reorderLevel;
  final bool needsReorder;
}
