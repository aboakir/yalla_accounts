// 📁 lib/features/finance/purchases/screens/purchases_gl_audit_screen.dart
//
// PurchasesGLAuditScreen — تدقيق GL للمشتريات (v30, UI unified)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PurchasesGLAuditScreen extends StatefulWidget {
  const PurchasesGLAuditScreen({super.key});

  @override
  State<PurchasesGLAuditScreen> createState() => _PurchasesGLAuditScreenState();
}

enum _Filter { all, posted, unposted }

class _PurchasesGLAuditScreenState extends State<PurchasesGLAuditScreen> {
  bool _loading = true;
  _Filter _filter = _Filter.all;
  final _df = DateFormat('yyyy-MM-dd', 'ar');
  final _nf = NumberFormat('#,##0.00', 'ar');

  List<_Row> _rows = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ===== Data =====
  Future<int?> _findGlIdForPurchase(String pid, dynamic glEntryIdCol) async {
    final fromCol = (glEntryIdCol is int)
        ? glEntryIdCol
        : int.tryParse('${glEntryIdCol ?? ''}');
    if (fromCol != null && fromCol > 0) return fromCol;
    return DBService.getGlEntryIdBySource('PURCHASE', pid);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows = [];
      _selected.clear();
    });

    final db = await DBService.database;

    final base = await db.rawQuery('''
      SELECT 
        p.id,
        p.supplier_pid,
        p.supplierName,
        p.amount,
        p.date,
        p.method,
        p.note,
        p.gl_entry_id
      FROM purchases p
      ORDER BY p.date DESC, p.id DESC
    ''');

    final List<_Row> all = [];
    for (final m in base) {
      final pid = '${m['id']}';
      final glId = await _findGlIdForPurchase(pid, m['gl_entry_id']);
      final supplierPid = (m['supplier_pid'] ?? '').toString();
      final supplierName = (m['supplierName'] ?? '').toString();

      all.add(_Row(
        id: pid,
        supplierPid: supplierPid.isEmpty ? null : supplierPid,
        supplierName: supplierName.isNotEmpty ? supplierName : null,
        amount: ((m['amount'] as num?) ?? 0).toDouble(),
        dateStr: m['date']?.toString(),
        method: m['method']?.toString() ?? 'credit',
        note: m['note']?.toString(),
        glEntryId: glId,
      ));
    }

    setState(() {
      _rows = switch (_filter) {
        _Filter.posted => all.where((r) => r.glEntryId != null).toList(),
        _Filter.unposted => all.where((r) => r.glEntryId == null).toList(),
        _ => all,
      };
      _loading = false;
    });
  }

  double get _sumSelected => _rows
      .where((r) => _selected.contains(r.id))
      .fold(0.0, (s, r) => s + r.amount);

  // ===== GL helpers =====
  bool _isCreditMethod(String m) {
    final s = m.trim().toLowerCase();
    return s == 'credit' || s == 'على الحساب' || s == 'on account';
  }

  bool _isBankMethod(String m) {
    final s = m.trim().toLowerCase();
    return s.contains('bank') ||
        s.contains('transfer') ||
        s.contains('تحويل') ||
        s.contains('visa') ||
        s.contains('master') ||
        s.contains('card') ||
        s.contains('شيك') ||
        s.contains('cheque') ||
        s.contains('check') ||
        s.contains('بنك');
  }

  Future<int> _postPurchaseGl(String purchaseId) async {
    final exists = await DBService.getGlEntryIdBySource('PURCHASE', purchaseId);
    if (exists != null) return exists;

    final db = await DBService.database;

    final row = await db.query('purchases',
        where: 'id=?', whereArgs: [purchaseId], limit: 1);
    if (row.isEmpty) {
      throw StateError('سجل المشتريات غير موجود');
    }

    final r = row.first;
    final amount = ((r['amount'] as num?) ?? 0).toDouble();
    if (amount <= 0) {
      throw StateError('مبلغ الشراء يجب أن يكون أكبر من صفر');
    }

    final method = (r['method']?.toString() ?? 'credit');
    final dateStr = (r['date']?.toString() ?? DateTime.now().toIso8601String());
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
    final supplierPid = (r['supplier_pid'] ?? '').toString();
    final note = r['note']?.toString();

    await DBService.ensureDefaultAccountsExist();

    final invId =
        await DBService.getAccountIdByCode('1400'); // Dr مخزون/مشتريات
    final cashId = await DBService.getAccountIdByCode('1000'); // الصندوق
    final bankId = await DBService.getAccountIdByCode('1010'); // البنك
    final apRootId =
        await DBService.getAccountIdByCode('2200'); // جذر ذمم الموردين
    if (invId == null || cashId == null || bankId == null || apRootId == null) {
      throw StateError('حسابات 1400/1000/1010/2200 ناقصة.');
    }

    late final Map<String, Object?> creditLine;
    if (_isCreditMethod(method)) {
      if (supplierPid.isEmpty) {
        throw StateError('شراء على الحساب يتطلب مورّدًا محددًا.');
      }
      // P1.007 — never fall back to the non-postable AP header.
      final apId =
          await DBService.ensureSupplierAccount(supplierPid); // 2200.S<id>
      creditLine = {
        'account_id': apId,
        'debit': 0.0,
        'credit': amount,
        'party_type': 'SUPPLIER',
        'party_id': supplierPid,
        'invoice_id': null,
        'repair_id': null,
      };
    } else {
      creditLine = {
        'account_id': _isBankMethod(method) ? bankId : cashId,
        'debit': 0.0,
        'credit': amount,
        'party_type': null,
        'party_id': null,
        'invoice_id': null,
        'repair_id': null,
      };
    }

    final entryId = await DBService.postEntryGL(
      date: date,
      ref: (note?.trim().isNotEmpty == true) ? note!.trim() : purchaseId,
      source: 'PURCHASE',
      sourceId: purchaseId,
      note: note,
      lines: [
        {
          'account_id': invId,
          'debit': amount,
          'credit': 0.0,
          'party_type': null,
          'party_id': null,
          'invoice_id': null,
          'repair_id': null,
        },
        creditLine,
      ],
    );

    await db.update('purchases', {'gl_entry_id': entryId},
        where: 'id=?', whereArgs: [purchaseId]);

    return entryId;
  }

  // ===== Row actions =====
  Future<void> _postOne(_Row r) async {
    setState(() => _loading = true);
    try {
      final id = await _postPurchaseGl(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم ترحيل GL #$id للسجل ${r.id}')));
      await _load();
    } on DatabaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('DB: $e')));
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      setState(() => _loading = false);
    }
  }

  Future<void> _reverseOne(_Row r) async {
    if (r.glEntryId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لا يوجد قيد لعكسه')));
      return;
    }
    setState(() => _loading = true);
    try {
      final revId = await DBService.reverseEntryGL(r.glEntryId!,
          note: 'عكس مشتريات ${r.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم إنشاء قيد عكسي #$revId')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      setState(() => _loading = false);
    }
  }

  Future<void> _openOne(_Row r) async {
    if (r.glEntryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد قيد GL لهذا السجل')));
      return;
    }
    await GLEntryScreen.open(context, r.glEntryId!);
  }

  Future<void> _postSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _loading = true);
    int ok = 0, fail = 0;
    for (final r in _rows.where((x) => _selected.contains(x.id))) {
      try {
        await _postPurchaseGl(r.id);
        ok++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تم: $ok | فشل: $fail')));
    await _load();
  }

  Future<void> _reverseSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _loading = true);
    int ok = 0, fail = 0;
    for (final r in _rows.where((x) => _selected.contains(x.id))) {
      if (r.glEntryId == null) continue;
      try {
        await DBService.reverseEntryGL(r.glEntryId!,
            note: 'عكس جماعي مشتريات ${r.id}');
        ok++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تم: $ok | فشل: $fail')));
    await _load();
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    Responsive.isDesktop(context);
    final total = _rows.fold<double>(0, (s, r) => s + r.amount);

    // رأس الشاشة الثابت أسفل AppBar
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: AdaptiveRow(
        children: [
          const Text(
            'تدقيق GL للمشتريات',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // فلتر الحالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<_Filter>(
              value: _filter,
              dropdownColor: Colors.white,
              underline: const SizedBox.shrink(),
              iconEnabledColor: Colors.white,
              style: const TextStyle(color: Colors.black87),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _filter = v);
                _load();
              },
              items: const [
                DropdownMenuItem(value: _Filter.all, child: Text('الكل')),
                DropdownMenuItem(value: _Filter.posted, child: Text('المرحلة')),
                DropdownMenuItem(
                    value: _Filter.unposted, child: Text('غير المرحلة')),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );

    final toolbar = Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade100,
      child: AdaptiveRow(
        children: [
          Chip(
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            label: Text('الصفوف: ${_rows.length}'),
          ),
          const SizedBox(width: 8),
          Chip(
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            label: Text('الإجمالي: ${_nf.format(total)}'),
          ),
          const SizedBox(width: 8),
          Chip(
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            label: Text('المحدد: ${_nf.format(_sumSelected)}'),
          ),
          const Spacer(),
          if (_filter != _Filter.posted)
            FilledButton.icon(
              onPressed: _selected.isEmpty ? null : _postSelected,
              icon: const Icon(Icons.publish),
              label: Text('ترحيل المحدد (${_selected.length})'),
            ),
          const SizedBox(width: 8),
          if (_filter != _Filter.unposted)
            OutlinedButton.icon(
              onPressed: _selected.isEmpty ? null : _reverseSelected,
              icon: const Icon(Icons.undo),
              label: Text('عكس المحدد (${_selected.length})'),
            ),
        ],
      ),
    );

    final list = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_rows.isEmpty
            ? const Center(child: Text('لا توجد بيانات'))
            : ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  final checked = _selected.contains(r.id);
                  final dateTxt = (r.dateStr == null || r.dateStr!.isEmpty)
                      ? ''
                      : _df.format(
                          DateTime.tryParse(r.dateStr!) ?? DateTime.now());
                  final title = r.supplierName ??
                      (r.supplierPid != null
                          ? 'مورد ${r.supplierPid}'
                          : 'مورد');

                  return ListTile(
                    leading: Checkbox(
                      value: checked,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(r.id);
                          } else {
                            _selected.remove(r.id);
                          }
                        });
                      },
                    ),
                    title: Text(title, textAlign: TextAlign.right),
                    subtitle: Text(
                      [
                        if ((r.note ?? '').isNotEmpty) r.note!,
                        if (dateTxt.isNotEmpty) dateTxt,
                      ].join(' • '),
                      textAlign: TextAlign.right,
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_nf.format(r.amount),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        if (r.glEntryId != null)
                          Chip(
                            label: Text('#${r.glEntryId}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        IconButton(
                          tooltip: 'ترحيل',
                          onPressed:
                              r.glEntryId == null ? () => _postOne(r) : null,
                          icon: const Icon(Icons.publish),
                        ),
                        IconButton(
                          tooltip: 'فتح القيد',
                          onPressed:
                              r.glEntryId != null ? () => _openOne(r) : null,
                          icon: const Icon(Icons.open_in_new),
                        ),
                        IconButton(
                          tooltip: 'عكس',
                          onPressed:
                              r.glEntryId != null ? () => _reverseOne(r) : null,
                          icon: const Icon(Icons.undo),
                        ),
                      ],
                    ),
                  );
                },
              ));

    return Scaffold(
      // AppBar موحّد مع النظام الجديد
      appBar: const YallaAppBar(
        workshopName: 'المشتريات',
        showThemeToggle: true,
        showUserAvatar: false,
        showSearch: false,
        showNotifications: false,
      ),
      drawer: Responsive.isMobile(context)
          ? Drawer(child: YallaSidebar(currentRoute: '/purchases/gl-audit'))
          : null,
      body: AdaptiveRow(
        children: [
          if (Responsive.isDesktop(context))
            const SizedBox(
              width: 280,
              child: YallaSidebar(currentRoute: '/purchases/gl-audit'),
            ),
          Expanded(
            child: Column(
              children: [
                header,
                toolbar,
                Expanded(child: list),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  final String id;
  final String? supplierPid;
  final String? supplierName;
  final double amount;
  final String? dateStr;
  final String method;
  final String? note;
  final int? glEntryId;

  _Row({
    required this.id,
    required this.supplierPid,
    required this.supplierName,
    required this.amount,
    required this.dateStr,
    required this.method,
    required this.note,
    required this.glEntryId,
  });
}
