import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import '../../../vouchers/models/voucher_payment_model.dart';
import '../../../vouchers/services/voucher_payment_service.dart';

class SupplierPaymentService {
  static Future<int> insertAndPost({
    required String operationId,
    required int supplierId,
    required double amount,
    required DateTime date,
    required String method,
    String? note,
    Database? database,
  }) async {
    if (operationId.trim().isEmpty) {
      throw ArgumentError('Operation ID required');
    }
    final posted = await VoucherPaymentService.insertAndPost(
      database: database,
      voucher: VoucherPayment(
          id: operationId,
          voucherType: 'PAYMENT',
          partyType: 'SUPPLIER',
          partyId: '$supplierId',
          amount: amount,
          currency: 'ILS',
          date: date,
          method: method.toUpperCase(),
          notes: note),
      partyName: 'Supplier $supplierId',
    );
    return posted.glEntryId!;
  }

  /// One row per posted GL entry, including legacy payments without vouchers.
  static Future<List<Map<String, Object?>>> list(
      {String? supplierId, Database? database}) async {
    final db = database ?? await DBService.database;
    return db.rawQuery('''
      SELECT e.source_id AS id, e.id AS gl_entry_id, l.party_id,
        SUM(l.debit-l.credit) AS amount, e.date, e.note AS notes,
        COALESCE((SELECT method FROM vouchers WHERE gl_entry_id=e.id LIMIT 1),
          (SELECT method FROM payments WHERE gl_entry_id=e.id LIMIT 1),
          (SELECT method FROM purchase_payments WHERE gl_entry_id=e.id LIMIT 1), '') AS method,
        CASE WHEN EXISTS (SELECT 1 FROM gl_entries rev WHERE rev.reversal_of=e.id)
          THEN 'REVERSED' ELSE 'POSTED' END AS status
      FROM gl_entries e JOIN gl_lines l ON l.entry_id=e.id
      WHERE UPPER(l.party_type)='SUPPLIER' AND e.reversal_of IS NULL
        AND UPPER(e.source) IN ('VOUCHER','PURCHASE_PAYMENT','PURCHASE_PAY','SUPPLIER_PAYMENT','PAYMENT','PAYMENT_OUT')
        ${supplierId == null || supplierId.isEmpty ? '' : 'AND l.party_id=?'}
      GROUP BY e.id, l.party_id
      ORDER BY e.date DESC, e.id DESC LIMIT 300
    ''', [if (supplierId != null && supplierId.isNotEmpty) supplierId]);
  }

  static Future<int> reverse(String paymentId, {Database? database}) async {
    final db = database ?? await DBService.database;
    final vouchers =
        await db.query('vouchers', where: 'id=?', whereArgs: [paymentId]);
    if (vouchers.isNotEmpty) {
      await VoucherPaymentService.reverseVoucher(paymentId,
          reason: 'Supplier payment reversal', database: db);
      final rows =
          await db.query('vouchers', where: 'id=?', whereArgs: [paymentId]);
      return (rows.first['reversal_gl_entry_id'] as num).toInt();
    }
    return SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn
          .query('purchase_payments', where: 'id=?', whereArgs: [paymentId]);
      if (rows.isEmpty || rows.first['gl_entry_id'] == null) {
        throw StateError('Posted payment not found');
      }
      final id = (rows.first['gl_entry_id'] as num).toInt();
      final reversal = await DBService.reverseEntryGLOn(txn, id,
          note: 'Supplier payment reversal');
      await txn.update('purchase_payments', {'status': 'REVERSED'},
          where: 'id=?', whereArgs: [paymentId]);
      return reversal;
    });
  }
}
