import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/events/app_event_bus.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/finance/models/invoice.dart';
import 'package:yalla_accounts/features/finance/services/invoice_database_service.dart';

/// FinanceEventsService (v26)
/// - لا ينشئ جداول؛ يعتمد على DBService لإنشاء/ترقية الـ schema.
/// - عند RepairCreated: ينشئ/يجلب الفاتورة عبر InvoiceDatabaseService.
/// - recordPayment: يدرج في payments (id TEXT) ويحدّث الفاتورة + مزامنة repair.
/// - يطلق PaymentRecorded للاستخدام بالـ UI إن لزم.
class FinanceEventsService {
  final Database db;
  late final StreamSubscription<AppEvent> _sub;

  FinanceEventsService(this.db) {
    _sub = AppEventBus.stream.listen(_onEvent);
  }

  static Future<FinanceEventsService> start() async {
    final db = await DBService.database;
    return FinanceEventsService(db);
  }

  Future<void> dispose() async {
    await _sub.cancel();
  }

  //==================== Events ====================

  Future<void> _onEvent(AppEvent e) async {
    if (e is RepairCreated) {
      await _createOrSyncInvoiceFromRepair(e.repairId);
    }
  }

  Future<void> _createOrSyncInvoiceFromRepair(String repairId) async {
    // اجلب الإصلاح
    final rows = await db.query(
      'repairs',
      where: 'id=?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final repair = Repair.fromMap(rows.first);

    final total = repair.totalFileValue;
    final paid = repair.totalPaidAmount;

    // تشغيل العملية داخل transaction لأن createOrGetByRepair يتطلب txn
    await db.transaction((txn) async {
      await InvoiceDatabaseService.instance.createOrGetByRepair(
        txn: txn,
        repairId: repair.id,
        date: repair.receivedDate,
        total: total,
        paid: paid,
        notes: repair.notes,
      );
    });
  }

  //==================== Payments ====================

  /// تسجيل دفعة على فاتورة
  /// - يكتب صف في payments (id TEXT).
  /// - يحدّث paid/status للفاتورة عبر InvoiceDatabaseService.
  /// - يحدّث paidAmount/paymentStatus في repairs (للتوافق مع الواجهات).
  Future<void> recordPayment({
    required String invoiceId,
    required double amount,
    required DateTime date,
    String method = 'cash',
    String? notes,
  }) async {
    // اقرأ الفاتورة
    final invRow = await db.query('invoices',
        where: 'id=?', whereArgs: [invoiceId], limit: 1);
    if (invRow.isEmpty) {
      throw StateError('Invoice not found: $invoiceId');
    }
    final inv = Invoice.fromMap(invRow.first);

    // محاولة معرفة client_id من repairs (عبر الفاتورة)
    int? clientId;
    String? partyId;
    String? repairId = inv.repairId;

    if (repairId.isNotEmpty) {
      final rRows = await db.query(
        'repairs',
        columns: ['id', 'client_id', 'beneficiaryName'],
        where: 'id = ?',
        whereArgs: [repairId],
        limit: 1,
      );
      if (rRows.isNotEmpty) {
        clientId = (rRows.first['client_id'] as num?)?.toInt();
        partyId = (rRows.first['beneficiaryName'] ?? '').toString();
      }
    }

    final paymentId = const Uuid().v4();
    final nowIso = date.toIso8601String();

    await db.transaction((txn) async {
      // 1) إدراج الدفعة في payments (id TEXT PRIMARY KEY)
      await txn.insert('payments', {
        'id': paymentId,
        'party_id': partyId, // اسـم العميل (اختياري/معلوماتي)
        'client_id': clientId, // يسهّل التقارير
        'repair_id': repairId, // الربط المباشر بالملف
        'invoice_id': invoiceId, // الربط بالفاتورة
        'amount': amount,
        'date': nowIso,
        'method': method,
        'accountName': null, // ممكن تعبئته من UI لاحقًا
        'status': 'confirmed',
        'notes': notes,
        'attachments': null,
        'relatedRepairId': repairId, // توافق قديم
      });

      // 2) حدّث Paid/Status للفاتورة
// 2) حدّث Paid/Status للفاتورة// 2) تحديث Paid/Status للفاتورة داخل نفس الـ TX
      final newPaid = inv.paid + amount;
      await InvoiceDatabaseService.instance.updatePaidAmount(
        repairId: inv.repairId,
        newPaid: newPaid,
        txn: txn,
      );

      // 3) مزامنة حقلَي paidAmount/paymentStatus في جدول repairs (توافق UI)
      if (repairId.isNotEmpty) {
        // اجلب الإجمالي بدقة (لو الموديل لم يكن متاحًا)
        double totalRef = inv.total;
        if (totalRef <= 0) {
          final r2 = await txn.query('repairs',
              where: 'id=?', whereArgs: [repairId], limit: 1);
          if (r2.isNotEmpty) {
            try {
              totalRef = Repair.fromMap(r2.first).totalFileValue;
            } catch (_) {}
          }
        }
        final status = newPaid >= totalRef
            ? 'مسدد'
            : (newPaid > 0 ? 'مسدد جزئي' : 'غير مسدد');

        await txn.update(
          'repairs',
          {'paidAmount': newPaid, 'paymentStatus': status},
          where: 'id=?',
          whereArgs: [repairId],
        );
      }
    });

    // 4) أطلق حدث اختياري للـ UI
    AppEventBus.emit(PaymentRecorded(invoiceId: invoiceId, amount: amount));
  }
}
