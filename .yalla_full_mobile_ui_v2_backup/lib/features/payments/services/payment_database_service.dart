// P1.001 — read-only compatibility adapter for the legacy payment-history UI.
//
// Historical versions opened a second `payments.db`, allowing off-ledger
// receipts. This service now reads the canonical DB and blocks direct writes.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/payments/models/payment_record.dart';

class PaymentDatabaseService {
  static Future<Database> get database => DBService.database;

  static Future<List<PaymentRecord>> getPaymentsByRepairId(
    String repairId,
  ) async {
    final db = await database;

    final rows = await db.query(
      'payments',
      columns: [
        'id',
        'repair_id',
        'relatedRepairId',
        'amount',
        'date',
        'notes',
      ],
      where: 'isIncome = 1 AND (repair_id = ? OR relatedRepairId = ?)',
      whereArgs: [repairId, repairId],
      orderBy: 'date DESC, id DESC',
    );

    return rows.map((row) {
      final rawAmount = row['amount'];

      return PaymentRecord(
        id: row['id'].toString(),
        repairId:
            (row['repair_id'] ?? row['relatedRepairId'] ?? repairId).toString(),
        amount: rawAmount is num
            ? rawAmount.toDouble()
            : double.tryParse(rawAmount?.toString() ?? '') ?? 0.0,
        date: DateTime.parse(row['date'].toString()),
        notes: row['notes']?.toString() ?? '',
      );
    }).toList(growable: false);
  }

  static Never _legacyWriteBlocked() {
    throw StateError(
      'Legacy payment-history writes are disabled. '
      'Use the canonical receipt voucher/payment workflow.',
    );
  }

  static Future<void> insertPayment(PaymentRecord payment) async {
    _legacyWriteBlocked();
  }

  static Future<void> deletePayment(String id) async {
    _legacyWriteBlocked();
  }

  static Future<void> updatePayment(PaymentRecord payment) async {
    _legacyWriteBlocked();
  }
}
