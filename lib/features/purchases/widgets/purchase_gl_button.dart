import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/finance/purchases/widgets/purchase_gl_button.dart
//
// PurchaseGlButton — فتح أو توليد قيد GL لعملية شراء موجودة
// - يتحقق من gl_entries(source='PURCHASE', source_id=purchaseId)
// - إذا مفقود ويُسمح بالإنشاء: يقرأ صف الشراء وينشر GL مباشرة عبر DBService
//   • Dr 1400 مخزون/مشتريات
//   • Cr 1000/1010 نقد/بنك أو Cr 2100.AP (مخصص للمورد إن توفر supplier_id)
// - يحدّث purchases.gl_entry_id ثم يفتح شاشة القيد.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';

class PurchaseGlButton extends StatefulWidget {
  final String purchaseId;
  final bool autoCreateIfMissing;
  final String? label;

  const PurchaseGlButton({
    super.key,
    required this.purchaseId,
    this.autoCreateIfMissing = true,
    this.label,
  });

  @override
  State<PurchaseGlButton> createState() => _PurchaseGlButtonState();
}

class _PurchaseGlButtonState extends State<PurchaseGlButton> {
  bool _loading = false;

  Future<void> _openOrCreate() async {
    setState(() => _loading = true);
    try {
      // 1) حاول إيجاد القيد
      int? entryId =
          await DBService.getGlEntryIdBySource('PURCHASE', widget.purchaseId);

      // 2) أنشئه إذا مفقود ومسموح
      if (entryId == null && widget.autoCreateIfMissing) {
        entryId = await _postGlForExistingPurchase(widget.purchaseId);
      }

      if (entryId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد قيد محاسبي لهذه العملية')),
        );
        return;
      }

      if (!mounted) return;
      await GLEntryScreen.open(context, entryId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${UserFacingError.message(e)}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// يقرأ صف الشراء الحالي ثم ينشر GL متوازن ويعيد entryId.
  Future<int?> _postGlForExistingPurchase(String purchaseId) async {
    final db = await DBService.database;

    // امنع التكرار لو وجد أثناء السباق
    final exists = await DBService.getGlEntryIdBySource('PURCHASE', purchaseId);
    if (exists != null) return exists;

    // اقرأ الشراء
    final row = await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: [purchaseId],
      limit: 1,
    );
    if (row.isEmpty) {
      throw StateError('purchase not found: $purchaseId');
    }

    // حقول مطلوبة
    final r = row.first;
    final amount = ((r['amount'] as num?) ?? 0).toDouble();
    if (amount <= 0) throw StateError('purchase amount must be > 0');

    final method = (r['method']?.toString() ?? 'credit').toLowerCase();
    final dateStr = (r['date']?.toString() ?? DateTime.now().toIso8601String());
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
    final supplierIdStr = r['supplier_id']?.toString();
    final note = r['note']?.toString();
    final ref = r['itemName']?.toString();

    // تأكيد الحسابات الأساسية
    await DBService.ensureDefaultAccountsExist();

    // حسابات
    final invId = await DBService.getAccountIdByCode('1400'); // Dr
    final cashId = await DBService.getAccountIdByCode('1000');
    final bankId = await DBService.getAccountIdByCode('1010');
    if (invId == null || cashId == null || bankId == null) {
      throw StateError('حسابات 1400/1000/1010 ناقصة.');
    }

    // تحديد الطرف الدائن
    late final Map<String, Object?> creditLine;
    final isCredit =
        method == 'credit' || method == 'على الحساب' || method == 'on account';
    final isBank = method.contains('bank') ||
        method.contains('transfer') ||
        method.contains('visa') ||
        method.contains('master') ||
        method.contains('card') ||
        method.contains('شيك') ||
        method.contains('تحويل') ||
        method.contains('بنك');

    if (isCredit) {
      if (supplierIdStr == null || supplierIdStr.isEmpty) {
        throw StateError('الشراء الآجل يتطلب مورّدًا محددًا.');
      }
      final apId = await DBService.ensureSupplierAccount(supplierIdStr);
      creditLine = {
        'account_id': apId,
        'debit': 0.0,
        'credit': amount,
        'party_type': 'SUPPLIER',
        'party_id': supplierIdStr,
        'invoice_id': null,
        'repair_id': null,
      };
    } else {
      creditLine = {
        'account_id': isBank ? bankId : cashId,
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
      ref: ref ?? purchaseId,
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

    // ربط gl_entry_id
    await db.update(
      'purchases',
      {'gl_entry_id': entryId},
      where: 'id=?',
      whereArgs: [purchaseId],
    );

    return entryId;
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _loading ? null : _openOrCreate,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.receipt_long),
      label: Text(widget.label ?? 'عرض القيد'),
    );
  }
}
