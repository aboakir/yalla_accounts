// 📁 lib/features/finance/purchases/screens/unposted_purchases_screen.dart
//
// UnpostedPurchasesScreen — تدقيق مشتريات غير مرحلة للـ GL (v29a)
// - يجلب where gl_entry_id IS NULL OR 0
// - ترحيل فردي + ترحيل جماعي + فتح القيد إذا وُجد
// - يعتمد supplier_pid (TEXT) و2200.S<supplierPid>
// - القيد: Dr 1400 "مخزون/مشتريات"  |  Cr نقد/بنك أو ذمم موردين
// - ref: note إن وُجد وإلا purchaseId

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';

class UnpostedPurchasesScreen extends StatefulWidget {
  const UnpostedPurchasesScreen({super.key});

  @override
  State<UnpostedPurchasesScreen> createState() =>
      _UnpostedPurchasesScreenState();
}

class _UnpostedPurchasesScreenState extends State<UnpostedPurchasesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  final _df = DateFormat('yyyy-MM-dd', 'ar');
  final _nf = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows = [];
    });

    final db = await DBService.database;

    // v29a: supplier_pid نصي + JOIN بالـ suppliers.id (TEXT)
    final rows = await db.rawQuery('''
      SELECT
        p.id,
        p.supplier_pid,
        IFNULL(s.name, CASE WHEN IFNULL(p.supplierName,'') <> '' THEN p.supplierName ELSE 'Supplier ' || IFNULL(p.supplier_pid,'-') END) AS supplier_name,
        p.amount,
        p.date,
        p.method,
        p.note,
        p.gl_entry_id
      FROM purchases p
      LEFT JOIN suppliers s ON CAST(s.id AS TEXT) = CAST(p.supplier_pid AS TEXT)
      WHERE p.gl_entry_id IS NULL OR p.gl_entry_id=0
      ORDER BY p.date DESC, p.id DESC
    ''');

    _rows = rows
        .map((r) => {
              'id': r['id']?.toString(),
              'supplier_pid': r['supplier_pid']?.toString(),
              'supplier_name': r['supplier_name']?.toString(),
              'amount': ((r['amount'] as num?) ?? 0).toDouble(),
              'date': r['date']?.toString(),
              'method': r['method']?.toString(),
              'note': r['note']?.toString(),
              'gl_entry_id': r['gl_entry_id'],
            })
        .toList();

    if (mounted) setState(() => _loading = false);
  }

  // ==== Helpers: method parsing ====
  bool _isCredit(String m) {
    final s = m.trim().toLowerCase();
    return s == 'credit' || s == 'على الحساب' || s == 'on account';
  }

  bool _isBank(String m) {
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

  // ==== Post one purchase to GL directly via DBService (v29a) ====
  Future<int> _postPurchaseGl(String purchaseId) async {
    // idempotency
    final existing =
        await DBService.getGlEntryIdBySource('PURCHASE', purchaseId);
    if (existing != null) return existing;

    final db = await DBService.database;

    final row = await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: [purchaseId],
      limit: 1,
    );
    if (row.isEmpty) {
      throw StateError('purchase not found');
    }

    final r = row.first;
    final amount = ((r['amount'] as num?) ?? 0).toDouble();
    if (amount <= 0) throw StateError('purchase amount must be > 0');

    final method = (r['method']?.toString() ?? 'credit');
    final dateStr = (r['date']?.toString() ?? DateTime.now().toIso8601String());
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
    final supplierPid = (r['supplier_pid'] ?? '').toString();
    final note = r['note']?.toString();

    // تأكيد الحسابات
    await DBService.ensureDefaultAccountsExist();

    // Dr 1400 "مخزون/مشتريات" — متسق مع باقي الخدمة
    final drId = await DBService.getAccountIdByCode('1400') ??
        await DBService.ensureAccount(
          code: '1400',
          name: 'مخزون/مشتريات',
          type: 'ASSET',
          normalBalance: 'DEBIT',
        );

    final cashId = await DBService.getAccountIdByCode('1000'); // الصندوق
    final bankId = await DBService.getAccountIdByCode('1010'); // البنك
    final apRootId =
        await DBService.getAccountIdByCode('2200'); // ذمم الموردين (جذر)
    if (cashId == null || bankId == null || apRootId == null) {
      throw StateError('حسابات 1000/1010/2200 ناقصة.');
    }

    // خط الدائن
    late final Map<String, Object?> creditLine;
    if (_isCredit(method)) {
      if (supplierPid.isEmpty) {
        throw StateError('شراء على الحساب يتطلب مورّدًا معروفًا.');
      }
      // P1.007 — never fall back to the non-postable AP header.
      final apId = await DBService.ensureSupplierAccount(supplierPid);
      creditLine = {
        'account_id': apId,
        'debit': 0.0,
        'credit': amount,
        'party_type': 'SUPPLIER',
        'party_id': supplierPid, // نصي
        'invoice_id': null,
        'repair_id': null,
      };
    } else {
      creditLine = {
        'account_id': _isBank(method) ? bankId : cashId,
        'debit': 0.0,
        'credit': amount,
        'party_type': null,
        'party_id': null,
        'invoice_id': null,
        'repair_id': null,
      };
    }

    // نشر GL
    final entryId = await DBService.postEntryGL(
      date: date,
      ref: (note?.trim().isNotEmpty == true) ? note!.trim() : purchaseId,
      source: 'PURCHASE',
      sourceId: purchaseId,
      note: note,
      lines: [
        {
          'account_id': drId, // Dr مخزون/مشتريات
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

    // ربط gl_entry_id
    await db.update(
      'purchases',
      {'gl_entry_id': entryId},
      where: 'id=?',
      whereArgs: [purchaseId],
    );

    return entryId;
  }

  Future<void> _postOne(String purchaseId) async {
    setState(() => _loading = true);
    try {
      final entryId = await _postPurchaseGl(purchaseId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ترحيل $purchaseId إلى GL (#$entryId)')),
      );
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

  Future<void> _postAll() async {
    if (_rows.isEmpty) return;
    setState(() => _loading = true);
    int ok = 0, fail = 0;

    for (final r in List<Map<String, dynamic>>.from(_rows)) {
      final id = r['id'] as String?;
      if (id == null) continue;
      try {
        await _postPurchaseGl(id);
        ok++;
      } catch (_) {
        fail++;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم: $ok — فشل: $fail')),
    );
    await _load();
  }

  Future<void> _openGlIfExists(String purchaseId) async {
    final entryId =
        await DBService.getGlEntryIdBySource('PURCHASE', purchaseId);
    if (entryId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد قيد GL لهذا السجل')),
      );
      return;
    }
    if (!mounted) return;
    await GLEntryScreen.open(context, entryId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unposted Purchases'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          if (_rows.isNotEmpty)
            TextButton.icon(
              onPressed: _loading ? null : _postAll,
              icon: const Icon(Icons.publish, color: Colors.white),
              label:
                  const Text('Post All', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('لا توجد مشتريات غير مرحلة'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final id = r['id'] as String?;
                    final supName = r['supplier_name'] as String?;
                    final amount = r['amount'] as double;
                    final dateStr = r['date'] as String?;
                    final date = DateTime.tryParse(dateStr ?? '');
                    final dateTxt =
                        date != null ? _df.format(date) : (dateStr ?? '');

                    return ListTile(
                      title: Text(
                          supName ?? 'Supplier ${r['supplier_pid'] ?? '-'}'),
                      subtitle: Text(dateTxt),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_nf.format(amount)),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'Post GL',
                            icon: const Icon(Icons.publish),
                            onPressed: id == null ? null : () => _postOne(id),
                          ),
                          IconButton(
                            tooltip: 'Open GL',
                            icon: const Icon(Icons.open_in_new),
                            onPressed:
                                id == null ? null : () => _openGlIfExists(id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
