// -----------------------------------------------------------------------------
// 📁 lib/features/finance/purchases/screens/purchase_create_screen.dart
// FINAL — One-Purchase Flow + Supplier Picker
// -----------------------------------------------------------------------------
// - اختيار مورد عبر PID أو الاسم
// - نافذة اختيار مورّد جاهزة + بحث مباشر
// - إنشاء مورد جديد تلقائياً عند عدم وجوده
// - سطر واحد للشراء (صنف + كمية + سعر)
// - حساب إجمالي تلقائي
// - حفظ + GL Posting عبر PurchaseInvoiceService
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_invoice_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

// ============================================================================
// SUPPLIER MODEL (عرضي)
// ============================================================================
class _Supplier {
  final int id;
  final String pid; // S0001
  final String name;

  const _Supplier({required this.id, required this.pid, required this.name});
}

// ============================================================================
// SCREEN
// ============================================================================
class PurchaseCreateScreen extends StatefulWidget {
  const PurchaseCreateScreen({
    super.key,
    this.initialPurchaseType = 'OTHER',
    this.initialNote,
  });

  final String initialPurchaseType;
  final String? initialNote;

  static Future<void> open(
    BuildContext ctx, {
    String initialPurchaseType = 'OTHER',
    String? initialNote,
  }) async {
    await Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => PurchaseCreateScreen(
          initialPurchaseType: initialPurchaseType,
          initialNote: initialNote,
        ),
      ),
    );
  }

  @override
  State<PurchaseCreateScreen> createState() => _PurchaseCreateScreenState();
}

class _PurchaseCreateScreenState extends State<PurchaseCreateScreen> {
  final _formKey = GlobalKey<FormState>();

  final _supplierPidCtrl = TextEditingController();
  final _supplierNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: MoneyFormatter.zeroText);
  final _noteCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  String _method = "credit"; // cash | bank | credit
  late String _purchaseType;
  bool _saving = false;

  final List<_LineModel> _lines = [_LineModel()];
  final _df = DateFormat("yyyy-MM-dd", "ar");

  // ==========================================================================
  // حساب الإجمالي
  // ==========================================================================
  double _sum() => _lines.fold(0.0, (s, l) => s + (l.qty * l.price));

  void _recalc() {
    _amountCtrl.text = _sum().toStringAsFixed(MoneyFormatter.decimals);
    setState(() {});
  }

  void _addLine() => setState(() => _lines.add(_LineModel()));

  void _removeLine(int i) {
    if (_lines.length <= 1) return;
    _lines.removeAt(i);
    _recalc();
  }

  @override
  void initState() {
    super.initState();
    const allowed = {'PARTS', 'RAW', 'PAINT', 'TOOLS', 'OTHER'};
    final requested = widget.initialPurchaseType.trim().toUpperCase();
    _purchaseType = allowed.contains(requested) ? requested : 'OTHER';
    _noteCtrl.text = widget.initialNote?.trim() ?? '';
  }

  @override
  void dispose() {
    _supplierPidCtrl.dispose();
    _supplierNameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    for (final l in _lines) {
      l.nameCtrl.dispose();
      l.qtyCtrl.dispose();
      l.priceCtrl.dispose();
    }
    super.dispose();
  }

  // ==========================================================================
  // DATE PICKER
  // ==========================================================================
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale("ar"),
    );
    if (d != null) setState(() => _date = d);
  }

  // ==========================================================================
  // SUPPLIERS SEARCH + PICKER
  // ==========================================================================
  Future<List<_Supplier>> _searchSuppliers(String q, bool byPid) async {
    final db = await DBService.database;
    q = q.trim();

    List<Map<String, Object?>> rows;

    if (q.isEmpty) {
      rows = await db.rawQuery("""
        SELECT id, name, printf('S%04d', id) AS pid
        FROM suppliers ORDER BY name LIMIT 50
      """);
    } else if (byPid) {
      rows = await db.rawQuery("""
        SELECT id, name, printf('S%04d', id) AS pid
        FROM suppliers
        WHERE printf('S%04d', id) LIKE ? OR CAST(id AS TEXT) LIKE ?
        ORDER BY id
      """, ['%$q%', '%$q%']);
    } else {
      rows = await db.rawQuery("""
        SELECT id, name, printf('S%04d', id) AS pid
        FROM suppliers
        WHERE name LIKE ? COLLATE NOCASE
        ORDER BY name
      """, ['%$q%']);
    }

    return rows
        .map((m) => _Supplier(
              id: (m['id'] as num).toInt(),
              pid: (m['pid'] as String),
              name: (m['name'] as String),
            ))
        .toList();
  }

  // ========================================================================
  // فتح نافذة اختيار مورد
  // ========================================================================
  Future<_Supplier?> _openSupplierPicker(bool byPid) async {
    final ctrl = TextEditingController();
    List<_Supplier> results = await _searchSuppliers("", byPid);
    if (!mounted) return null;

    return showDialog<_Supplier>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          Future<void> doSearch(String t) async {
            results = await _searchSuppliers(t, byPid);
            setSt(() {});
          }

          return AdaptiveAlertDialog(
            title: Text(
              byPid ? "اختر مورّد بالرقم" : "اختر مورّد بالاسم",
              textAlign: TextAlign.right,
            ),
            content: SizedBox(
              width: MediaQuery.sizeOf(context).width < 600
                  ? double.infinity
                  : 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: ctrl,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                      hintText: "بحث...",
                    ),
                    onChanged: doSearch,
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 330),
                    child: results.isEmpty
                        ? const Center(child: Text("لا نتائج"))
                        : ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final s = results[i];
                              return ListTile(
                                onTap: () => Navigator.pop(context, s),
                                leading: Text(
                                  s.pid,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                title: Text(
                                  s.name,
                                  textAlign: TextAlign.right,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إغلاق"),
              )
            ],
          );
        },
      ),
    );
  }

  // ========================================================================
  // Create Supplier
  // ========================================================================
  Future<_Supplier> _createSupplier(String name) async {
    final db = await DBService.database;

    late _Supplier s;

    await db.transaction((txn) async {
      final newId = await txn.insert("suppliers", {"name": name});
      final pid = "S${newId.toString().padLeft(4, '0')}";

      final code = "2200.$pid";
      final exists = await txn
          .rawQuery("SELECT id FROM accounts WHERE code=? LIMIT 1", [code]);

      if (exists.isEmpty) {
        await txn.insert("accounts", {
          "code": code,
          "name": "ذمم مورد — $name",
          "type": "LIABILITY",
          "normal_balance": "CREDIT",
        });
      }

      s = _Supplier(id: newId, pid: pid, name: name);
    });

    return s;
  }

  // ========================================================================
  // Ensure Supplier
  // ========================================================================
  Future<_Supplier?> _ensureSupplier() async {
    final pid = _supplierPidCtrl.text.trim();
    final name = _supplierNameCtrl.text.trim();

    if (pid.isNotEmpty) {
      final db = await DBService.database;
      final r = await db.rawQuery("""
        SELECT id, name, printf('S%04d', id) AS pid
        FROM suppliers WHERE printf('S%04d', id)=? LIMIT 1
      """, [pid]);

      if (r.isNotEmpty) {
        final m = r.first;
        return _Supplier(
          id: m['id'] as int,
          pid: m['pid'] as String,
          name: m['name'] as String,
        );
      }

      if (name.isEmpty) return null;
      return _createSupplier(name);
    }

    if (name.isNotEmpty) {
      final db = await DBService.database;
      final r = await db.rawQuery("""
        SELECT id, name, printf('S%04d', id) AS pid
        FROM suppliers WHERE name=? COLLATE NOCASE LIMIT 1
      """, [name]);

      if (r.isNotEmpty) {
        final m = r.first;
        return _Supplier(
          id: m['id'] as int,
          pid: m['pid'] as String,
          name: m['name'] as String,
        );
      }

      return _createSupplier(name);
    }

    return null;
  }

  // ==========================================================================
  // SUBMIT
  // ==========================================================================
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final items = _lines.where((l) => l.name.isNotEmpty && l.qty > 0).toList();
    if (items.isEmpty) {
      _snack("أضف بنداً واحداً على الأقل");
      return;
    }

    final supplier = await _ensureSupplier();
    if (supplier == null) {
      _snack("يجب اختيار مورّد");
      return;
    }

    final total = double.tryParse(_amountCtrl.text) ?? 0;
    if (total <= 0) {
      _snack("المجموع غير صالح");
      return;
    }

    setState(() => _saving = true);

    try {
      final id = await PurchaseInvoiceService.createInvoice(
        supplierId: supplier.id,
        date: _date,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        method: _method,
        purchaseType: _purchaseType,
        items: items.map((l) {
          return {
            "item_name": l.name,
            "qty": l.qty,
            "price": l.price,
          };
        }).toList(),
      );

      _snack("تم الحفظ — GL $id", ok: true);
      _reset();
    } catch (e) {
      _snack("فشل الحفظ: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    _formKey.currentState?.reset();
    _supplierPidCtrl.clear();
    _supplierNameCtrl.clear();
    _noteCtrl.text = widget.initialNote?.trim() ?? '';
    _method = 'credit';
    const allowed = {'PARTS', 'RAW', 'PAINT', 'TOOLS', 'OTHER'};
    final requested = widget.initialPurchaseType.trim().toUpperCase();
    _purchaseType = allowed.contains(requested) ? requested : 'OTHER';
    _lines
      ..clear()
      ..add(_LineModel());
    _recalc();
  }

  void _snack(String s, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s),
        backgroundColor: ok ? AppColors.success : null,
      ),
    );
  }

  // ==========================================================================
  // UI
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("إنشاء عملية شراء",
            style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  // -------------------------------------------------------------------
                  // SUPPLIER FIELDS
                  // -------------------------------------------------------------------
                  AdaptiveRow(
                    children: [
                      Expanded(
                        child: TextFormField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _supplierPidCtrl,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            labelText: "رقم المورّد PID",
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () async {
                                final s = await _openSupplierPicker(true);
                                if (s != null) {
                                  _supplierPidCtrl.text = s.pid;
                                  _supplierNameCtrl.text = s.name;
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _supplierNameCtrl,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            labelText: "اسم المورّد",
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () async {
                                final s = await _openSupplierPicker(false);
                                if (s != null) {
                                  _supplierPidCtrl.text = s.pid;
                                  _supplierNameCtrl.text = s.name;
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // DATE FIELD
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: "التاريخ",
                              border: OutlineInputBorder(),
                            ),
                            child: Text(_df.format(_date)),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  AdaptiveRow(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _purchaseType,
                          decoration: const InputDecoration(
                            labelText: 'نوع المشتريات',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'PARTS', child: Text('قطع غيار')),
                            DropdownMenuItem(
                                value: 'RAW', child: Text('مواد خام')),
                            DropdownMenuItem(
                                value: 'PAINT', child: Text('مواد دهان')),
                            DropdownMenuItem(
                                value: 'TOOLS', child: Text('عِدّة وأدوات')),
                            DropdownMenuItem(
                                value: 'OTHER', child: Text('أخرى')),
                          ],
                          onChanged: (v) =>
                              setState(() => _purchaseType = v ?? 'OTHER'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _method,
                          decoration: const InputDecoration(
                            labelText: 'طريقة الدفع',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'credit', child: Text('على الحساب')),
                            DropdownMenuItem(
                                value: 'cash', child: Text('نقدًا')),
                            DropdownMenuItem(
                                value: 'bank', child: Text('بنك / تحويل')),
                          ],
                          onChanged: (v) =>
                              setState(() => _method = v ?? 'credit'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // -------------------------------------------------------------------
                  // INVOICE LINES TABLE
                  // -------------------------------------------------------------------
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(.1),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: const Text("تفاصيل الفاتورة",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const Divider(height: 1),
                        const _LinesHeader(),
                        const Divider(height: 1),
                        ..._lines.asMap().entries.map((e) {
                          final i = e.key;
                          final m = e.value;
                          return _LineRow(
                            model: m,
                            onChanged: _recalc,
                            onRemove:
                                _lines.length > 1 ? () => _removeLine(i) : null,
                          );
                        }),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text("إضافة بند"),
                                onPressed: _addLine,
                              ),
                              Text(
                                "الإجمالي: ${_amountCtrl.text} ${MoneyFormatter.symbol}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // NOTE FIELD
                  TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _noteCtrl,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      labelText: "ملاحظات (اختياري)",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // SAVE BUTTON
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? "جارٍ الحفظ..." : "حفظ العملية"),
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MODELS
// ============================================================================
class _LineModel {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController qtyCtrl = TextEditingController(text: "1");
  final TextEditingController priceCtrl = TextEditingController(text: "0.00");

  String get name => nameCtrl.text.trim();
  double get qty => double.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get price => double.tryParse(priceCtrl.text.trim()) ?? 0;
}

// ============================================================================
// TABLE HEADER
// ============================================================================
class _LinesHeader extends StatelessWidget {
  const _LinesHeader();

  @override
  Widget build(BuildContext context) {
    const h = TextStyle(fontWeight: FontWeight.bold);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: AdaptiveRow(
        children: const [
          Expanded(flex: 5, child: Text("الصنف", style: h)),
          SizedBox(width: 8),
          Expanded(flex: 2, child: Text("الكمية", style: h)),
          SizedBox(width: 8),
          Expanded(flex: 3, child: Text("السعر", style: h)),
          SizedBox(width: 8),
          Expanded(flex: 3, child: Text("الإجمالي", style: h)),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ============================================================================
// LINE ROW
// ============================================================================
class _LineRow extends StatefulWidget {
  final _LineModel model;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _LineRow({
    required this.model,
    required this.onChanged,
    this.onRemove,
  });

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  @override
  void initState() {
    super.initState();
    widget.model.qtyCtrl.addListener(widget.onChanged);
    widget.model.priceCtrl.addListener(widget.onChanged);
  }

  @override
  void dispose() {
    widget.model.qtyCtrl.removeListener(widget.onChanged);
    widget.model.priceCtrl.removeListener(widget.onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.model.qty * widget.model.price;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: AdaptiveRow(
        children: [
          // اسم الصنف
          Expanded(
            flex: 5,
            child: TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: widget.model.nameCtrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: "اسم الصنف",
              ),
            ),
          ),
          const SizedBox(width: 8),

          // كمية
          Expanded(
            flex: 2,
            child: TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: widget.model.qtyCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: "0",
              ),
            ),
          ),
          const SizedBox(width: 8),

          // سعر
          Expanded(
            flex: 3,
            child: TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: widget.model.priceCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: "0.00",
              ),
            ),
          ),
          const SizedBox(width: 8),

          // الإجمالي
          Expanded(
            flex: 3,
            child: InputDecorator(
              decoration:
                  InputDecoration(border: OutlineInputBorder(), isDense: true),
              child: Text(MoneyFormatter.format(total)),
            ),
          ),

          const SizedBox(width: 8),

          // حذف السطر
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: widget.onRemove == null ? Colors.grey : Colors.red,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }
}
