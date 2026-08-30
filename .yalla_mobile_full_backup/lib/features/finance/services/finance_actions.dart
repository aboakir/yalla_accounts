import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/services/finance_events_service.dart';

/// يسجّل دفعة مباشرةً عبر repairId.
/// يقرأ invoiceId المرتبط بالإصلاح ثم يستدعي recordPayment.
class FinanceActions {
  FinanceActions._();

  static Future<void> recordPaymentForRepair({
    required String repairId,
    required double amount,
    required DateTime date,
    String method = 'cash',
    String? notes,
  }) async {
    final db = await DBService.database;
    final row = await db.query(
      'invoices',
      columns: ['id'],
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (row.isEmpty) {
      throw Exception('لا توجد فاتورة مرتبطة بهذا الإصلاح ($repairId).');
    }
    final invoiceId = row.first['id'] as String;
    final svc = await FinanceEventsService.start();
    await svc.recordPayment(
      invoiceId: invoiceId,
      amount: amount,
      date: date,
      method: method,
      notes: notes,
    );
  }
}
