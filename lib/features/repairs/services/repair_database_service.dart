// ---------------------------------------------------------------------------
// 📁 lib/features/repairs/services/repair_database_service.dart
//
// نسخة نهائية — نظيفة — بدون أخطاء — متوافقة مع DBService v38 +
// RepairTables + AccountingTables + InvoiceService
//
// ✔ كل عمليات الكتابة داخل معاملات (TX-safe)
// ✔ GL posting بعد commit فقط
// ✔ يدعم create/update/delete/approveQuote
// ✔ يدعم subtotal + vat_amount + total
// ✔ يدعم migration من invoiceId القديم
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/finance/services/work_cost_calculator.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';

class RepairDatabaseService {
  RepairDatabaseService._();
  static final RepairDatabaseService instance = RepairDatabaseService._();

  static Future<Database> get database async => DBService.database;

  // ======================================================================
  // Helpers
  // ======================================================================

  static double _toD(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _roundLine(double value) =>
      double.parse(value.toStringAsFixed(2));

  static Map<String, dynamic>? _normalizeRepairLine(Object? raw) {
    if (raw is! Map) return null;

    final item = Map<String, dynamic>.from(raw);
    final name = (item['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    var qty = _toD(item['qty']);
    if (qty <= 0) qty = 1.0;

    final price = _toD(
      item['price'] ?? item['amount'] ?? item['cost'],
    );

    if (price < 0) {
      throw StateError('Repair line price cannot be negative: $name');
    }

    return <String, dynamic>{
      ...item,
      'name': name,
      'qty': qty,
      'price': price,
      'total': _roundLine(qty * price),
    };
  }

  static List<Map<String, dynamic>> _normalizeRepairLines(
    List<dynamic> list,
  ) {
    final result = <Map<String, dynamic>>[];

    for (final raw in list) {
      final normalized = _normalizeRepairLine(raw);
      if (normalized != null) result.add(normalized);
    }

    return result;
  }

  static double _sumListLike(List<dynamic> list) {
    return _normalizeRepairLines(list).fold<double>(
      0.0,
      (sum, line) => sum + _toD(line['total']),
    );
  }

  static Future<void> _replaceRepairLinesOn(
    DatabaseExecutor tx, {
    required String repairId,
    required List<Map<String, dynamic>> parts,
    required List<Map<String, dynamic>> works,
  }) async {
    await tx.delete(
      'repair_lines',
      where: 'repair_id = ?',
      whereArgs: [repairId],
    );

    final batch = tx.batch();
    final now = DateTime.now().toIso8601String();

    void addLines(
      String type,
      List<Map<String, dynamic>> lines,
    ) {
      for (final line in lines) {
        batch.insert(
          'repair_lines',
          {
            'id': const Uuid().v4(),
            'repair_id': repairId,
            'line_type': type,
            'name': line['name'],
            'qty': line['qty'],
            'price': line['price'],
            'total': line['total'],
            'notes': line['notes'],
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    }

    addLines('part', parts);
    addLines('work', works);

    await batch.commit(noResult: true);
  }

  static Future<int> getRepairsCount() async {
    final db = await DBService.database;

    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs');

    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<double> _sumPaymentsForRepair(
      DatabaseExecutor db, String repairId) async {
    final rows = await db.rawQuery(
      'SELECT IFNULL(SUM(amount),0) AS tot FROM payments WHERE repair_id = ? OR relatedRepairId = ?',
      [repairId, repairId],
    );
    if (rows.isEmpty) return 0.0;
    return _toD(rows.first['tot']);
  }

  static String _statusFor(double file, double paid) {
    if (paid >= file) return 'مسدد';
    if (paid > 0) return 'مسدد جزئي';
    return 'غير مسدد';
  }

  static Map<String, dynamic> _toDb(Repair r) => {
        'id': r.id,
        'invoiceNumber': r.invoiceNumber,
        'vehicleModel': r.vehicleModel,
        'vehicleType': r.vehicleType,
        'vehicleNumber': r.vehicleNumber,
        'receivedDate': r.receivedDate.toIso8601String(),
        'beneficiaryType': r.beneficiaryType,
        'beneficiaryName': r.beneficiaryName,
        'client_id': r.clientId,
        'insuranceStatus': r.insuranceStatus,
        'repairType': r.repairType,
        'vehicleStatus': r.vehicleStatus,
        'parts': jsonEncode(r.parts),
        'works': jsonEncode(r.works),
        'fileValue': r.fileValue,
        'paymentType': r.paymentType.name,
        'paidAmount': r.paidAmount,
        'paymentStatus': r.paymentStatus,
        'notes': r.notes,
        'imagePaths': jsonEncode(r.imagePaths),
        'isArchived': r.isArchived ? 1 : 0,
        'finalApprovedAmount': r.finalApprovedAmount,
        'isLedgerEnabled': r.isLedgerEnabled ? 1 : 0,
        'isLedgerSynced': r.isLedgerSynced ? 1 : 0,
        'workCost': r.workCost,
        'incomeAmount': r.incomeAmount,
        'invoice_id': r.invoiceId,
      };

  static Map<String, dynamic> _normalize(Map<String, dynamic> m) {
    final copy = Map<String, dynamic>.from(m);
    if (copy.containsKey('client_id') && !copy.containsKey('clientId')) {
      copy['clientId'] = copy['client_id'];
    }
    if (copy.containsKey('invoice_id') && !copy.containsKey('invoiceId')) {
      copy['invoiceId'] = copy['invoice_id'];
    }
    return copy;
  }

  // ======================================================================
  // INSERT
  // ======================================================================

  static Future<String> insertRepair(Repair r) async {
    final newId = r.id.isNotEmpty ? r.id : const Uuid().v4();

    final normalizedParts = _normalizeRepairLines(r.parts);
    final normalizedWorks = _normalizeRepairLines(r.works);
    final fileValue =
        _sumListLike(normalizedParts) + _sumListLike(normalizedWorks);
    final wc = await WorkCostCalculator.calculateForMonth(r.receivedDate);

    await DBService.inTx((tx) async {
      final paid = await _sumPaymentsForRepair(tx, newId);
      final paymentStatus = _statusFor(fileValue, paid);

      final nr = r.copyWith(
        id: newId,
        parts: normalizedParts,
        works: normalizedWorks,
        fileValue: fileValue,
        paidAmount: paid,
        paymentStatus: paymentStatus,
        isArchived: r.isArchived,
        workCost: wc,
        incomeAmount: fileValue,
      );

      // P0.006 — saving a workshop repair does NOT create an invoice.
      await tx.insert(
        'repairs',
        _toDb(nr),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // P0.009 — repair_lines is derived from the same normalized JSON detail.
      await _replaceRepairLinesOn(
        tx,
        repairId: newId,
        parts: normalizedParts,
        works: normalizedWorks,
      );
    });

    return newId;
  }

  // ======================================================================
  // INSERT + RETURN INVOICE
  // ======================================================================

  static Future<String> insertRepairWithInvoice(Repair r) async {
    final repairId = await insertRepair(r);

    // Explicit method name = explicit invoicing event.
    return approveQuote(
      repairId: repairId,
      approvedBy: 'SYSTEM',
      approvedAt: DateTime.now(),
      invoiceDate: r.receivedDate,
    );
  }

  // ======================================================================
  // APPROVE QUOTE
  // ======================================================================

  static Future<String> approveQuote({
    required String repairId,
    String? approvedBy,
    DateTime? approvedAt,
    DateTime? invoiceDate,
  }) async {
    return DBService.inTx((tx) async {
      final rows = await tx.query(
        'repairs',
        where: 'id=?',
        whereArgs: [repairId],
        limit: 1,
      );

      if (rows.isEmpty) throw StateError('Repair not found');

      final m = rows.first;
      final parts =
          jsonDecode((m['parts'] ?? '[]').toString()) as List<dynamic>;
      final works =
          jsonDecode((m['works'] ?? '[]').toString()) as List<dynamic>;

      final fileValue = _sumListLike(parts) + _sumListLike(works);
      final clientId = (m['client_id'] as int?) ??
          int.tryParse((m['client_id'] ?? '').toString());

      if (fileValue <= 0) {
        throw StateError('Cannot invoice repair $repairId with value <= 0');
      }
      if (clientId == null || clientId <= 0) {
        throw StateError('Cannot invoice repair $repairId without client_id');
      }

      final invId = await InvoiceService.I.createInvoiceOnTransaction(
        txn: tx,
        repairId: repairId,
        date: invoiceDate ?? DateTime.now(),
        total: fileValue,
        subtotal: fileValue,
        vatAmount: 0.0,
        status: 'unpaid',
        notes: 'فاتورة ملف إصلاح ($repairId)',
        method: (m['paymentType'] ?? 'credit').toString(),
        clientId: clientId,
        postToGL: true,
      );

      final now = DateTime.now().toIso8601String();

      await tx.update(
        'repairs',
        {
          'invoice_id': invId,
          'status': 'INVOICED',
          'approved_at': (approvedAt ?? DateTime.now()).toIso8601String(),
          'approved_by': approvedBy,
          'isLedgerSynced': 1,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [repairId],
      );

      return invId;
    });
  }

  // ======================================================================
  // UPDATE
  // ======================================================================

  static Future<void> updateRepair(Repair r) async {
    await database;

    final normalizedParts = _normalizeRepairLines(r.parts);
    final normalizedWorks = _normalizeRepairLines(r.works);
    final fileValue =
        _sumListLike(normalizedParts) + _sumListLike(normalizedWorks);
    final wc = await WorkCostCalculator.calculateForMonth(r.receivedDate);

    await DBService.inTx((tx) async {
      final paid = await _sumPaymentsForRepair(tx, r.id);
      final paymentStatus = _statusFor(fileValue, paid);

      final nr = r.copyWith(
        parts: normalizedParts,
        works: normalizedWorks,
        fileValue: fileValue,
        paidAmount: paid,
        paymentStatus: paymentStatus,
        isArchived: r.isArchived,
        workCost: wc,
        incomeAmount: fileValue,
      );

      final data = _toDb(nr)..remove('invoice_id');

      // P0.006 — operational edit only.
      // Never create/recompute/repost the invoice from a Repair update.
      await tx.update(
        'repairs',
        data,
        where: 'id=?',
        whereArgs: [r.id],
      );

      // P0.009 — keep the derived query table synchronized in the SAME TX.
      await _replaceRepairLinesOn(
        tx,
        repairId: r.id,
        parts: normalizedParts,
        works: normalizedWorks,
      );
    });
  }

  // ======================================================================
  // P06 ARCHIVE
  // ======================================================================

  static Future<void> setArchived(String id, bool archived) async {
    await DBService.inTx((tx) async {
      await setArchivedOn(tx, id, archived);
    });
  }

  static Future<int> setArchivedOn(
    DatabaseExecutor db,
    String id,
    bool archived,
  ) async {
    final rows = await db.query(
      'repairs',
      columns: const ['id', 'isArchived'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Repair not found ($id)');
    }

    final current =
        rows.first['isArchived'] == 1 || rows.first['isArchived'] == true;
    if (current == archived) return 0;

    final now = DateTime.now().toUtc().toIso8601String();

    final changed = await db.update(
      'repairs',
      {
        'isArchived': archived ? 1 : 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (changed > 0) {
      await OfflineOutboxService.enqueue(
        db,
        channel: OfflineOutboxService.channelSync,
        operation: 'UPSERT',
        entityType: 'repair',
        entityId: id,
        idempotencyKey: 'repair:$id:archive:${archived ? 1 : 0}:$now',
        payload: {
          'schema': 1,
          'entity_type': 'repair',
          'entity_id': id,
          'is_archived': archived,
        },
      );
    }

    return changed;
  }

  static Future<void> archiveRepair(String id) => setArchived(id, true);

  static Future<void> restoreRepair(String id) => setArchived(id, false);

  // ======================================================================
  // DELETE
  // ======================================================================

  static Future<void> deleteRepair(String id) async {
    await RepairAutoAccountingService.deleteRepair(id);
  }

  // ======================================================================
  // READ
  // ======================================================================

  static Future<List<Repair>> getAllRepairs() async {
    final db = await database;
    final rows = await db.query(
      'repairs',
      where: "status IS NULL OR status <> ?",
      whereArgs: const <Object?>[RepairAutoAccountingService.cancelledStatus],
      orderBy: 'datetime(receivedDate) DESC',
    );
    return rows.map((m) => Repair.fromMap(_normalize(m))).toList();
  }

  static Future<Repair?> getRepairById(String id) async {
    final db = await database;
    final rows =
        await db.query('repairs', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Repair.fromMap(_normalize(rows.first));
  }

  static Future<Repair?> getRepairByIdTx(DatabaseExecutor db, String id) async {
    final rows =
        await db.query('repairs', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Repair.fromMap(_normalize(rows.first));
  }

  // ======================================================================
  // PAYMENTS
  // ======================================================================

  static Future<void> insertPayment({
    required String repairId,
    required double amount,
    required DateTime date,
    String method = '',
    String? notes,
  }) async {
    final repair = await getRepairById(repairId);
    if (repair == null) throw ArgumentError('Repair not found');

    final pay = Payment(
      id: const Uuid().v4(),
      clientId: repair.clientId,
      repairId: repairId,
      relatedRepairId: repairId,
      invoiceId: repair.invoiceId,
      amount: amount,
      date: date,
      method: method.isEmpty ? repair.paymentType.name : method,
      accountName: method.isEmpty ? repair.paymentType.name : method,
      status: 'confirmed',
      notes: notes,
      attachments: null,
      glEntryId: null,
      isIncome: true, // ← REQUIRED
    );
    await PaymentService.insertAndPostReceipt(
      payment: pay,
      customerName: repair.beneficiaryName,
      method: pay.method,
      descriptionOverride: pay.notes,
      updateInvoice: true,
    );
  }

  static Future<List<Map<String, Object?>>> fetchPaymentsByRepair(
      String id) async {
    final db = await database;
    return await db.query(
      'payments',
      where: 'repair_id=? OR relatedRepairId=?',
      whereArgs: [id, id],
      orderBy: 'datetime(date) DESC',
    );
  }
}

extension FirstOrNullExt<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
