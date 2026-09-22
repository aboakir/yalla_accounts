import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

class RepairSettlementResult {
  const RepairSettlementResult({
    required this.id,
    required this.repairId,
    required this.oldValue,
    required this.adjustment,
    required this.newValue,
    required this.paid,
    required this.remaining,
    required this.credit,
    required this.customerArBalance,
    required this.recognizedRevenue,
    required this.reason,
    required this.createdBy,
    required this.createdAt,
    this.glEntryId,
  });

  final String id;
  final String repairId;
  final double oldValue;
  final double adjustment;
  final double newValue;
  final double paid;
  final double remaining;
  final double credit;
  final double customerArBalance;
  final double recognizedRevenue;
  final String reason;
  final String createdBy;
  final DateTime createdAt;
  final int? glEntryId;
}

class RepairSettlementService {
  RepairSettlementService._();

  static const _uuid = Uuid();

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));

  static Future<void> ensureSchema({DatabaseExecutor? executor}) async {
    final db = executor ?? await DBService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repair_settlements(
        id TEXT PRIMARY KEY,
        operation_id TEXT,
        repair_id TEXT NOT NULL,
        invoice_id TEXT,
        old_value REAL NOT NULL,
        adjustment REAL NOT NULL,
        new_value REAL NOT NULL,
        paid_at_settlement REAL NOT NULL,
        remaining_before REAL NOT NULL,
        remaining_after REAL NOT NULL,
        credit_after REAL NOT NULL,
        customer_ar_after REAL NOT NULL,
        revenue_after REAL NOT NULL,
        gl_entry_id INTEGER,
        reason TEXT NOT NULL,
        note TEXT,
        created_by TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info(repair_settlements)');
    final columnNames = columns.map((row) => row['name']?.toString()).toSet();
    if (!columnNames.contains('operation_id')) {
      await db.execute(
        'ALTER TABLE repair_settlements ADD COLUMN operation_id TEXT',
      );
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_repair_settlements_operation '
      'ON repair_settlements(operation_id) WHERE operation_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_settlements_repair '
      'ON repair_settlements(repair_id, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_settlements_gl '
      'ON repair_settlements(gl_entry_id)',
    );
  }

  static Future<List<Map<String, Object?>>> historyForRepair(
    String repairId, {
    DatabaseExecutor? executor,
    int limit = 50,
  }) async {
    final db = executor ?? await DBService.database;
    await ensureSchema(executor: db);
    final rows = await db.query(
      'repair_settlements',
      where: 'repair_id=?',
      whereArgs: [repairId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  static RepairSettlementResult _resultFromRow(Map<String, Object?> row) {
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final glRaw = row['gl_entry_id'];
    return RepairSettlementResult(
      id: row['id']?.toString() ?? '',
      repairId: row['repair_id']?.toString() ?? '',
      oldValue: _d(row['old_value']),
      adjustment: _d(row['adjustment']),
      newValue: _d(row['new_value']),
      paid: _d(row['paid_at_settlement']),
      remaining: _d(row['remaining_after']),
      credit: _d(row['credit_after']),
      customerArBalance: _d(row['customer_ar_after']),
      recognizedRevenue: _d(row['revenue_after']),
      reason: row['reason']?.toString() ?? '',
      createdBy: row['created_by']?.toString() ?? '',
      createdAt: createdAt,
      glEntryId: glRaw == null
          ? null
          : (glRaw is int ? glRaw : int.tryParse(glRaw.toString())),
    );
  }

  static Future<String?> _invoiceIdForRepair(
    DatabaseExecutor db,
    String repairId,
    Map<String, Object?> repair,
  ) async {
    final cached =
        (repair['invoice_id'] ?? repair['invoiceId'])?.toString().trim();
    if (cached != null && cached.isNotEmpty) return cached;
    final rows = await db.query(
      'invoices',
      columns: const ['id'],
      where: 'repair_id=?',
      whereArgs: [repairId],
      orderBy: 'datetime(created_at) ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id']?.toString();
  }

  static Future<void> _syncLegacyArSnapshot({
    required DatabaseExecutor db,
    required Map<String, Object?> repair,
    required RepairFinancialTruth truth,
  }) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='accounts_receivable' LIMIT 1",
    );
    if (table.isEmpty) return;

    final repairId = repair['id']?.toString() ?? '';
    if (repairId.isEmpty) return;
    if (truth.remaining <= 0.005) {
      await db.delete(
        'accounts_receivable',
        where: 'repairId=?',
        whereArgs: [repairId],
      );
      return;
    }

    await db.insert(
      'accounts_receivable',
      <String, Object?>{
        'id': 'AR_$repairId',
        'repairId': repairId,
        'amount': truth.remaining,
        'date': DateTime.now().toUtc().toIso8601String(),
        'isPaid': 0,
        'paidDate': null,
        'dueDate': repair['receivedDate']?.toString(),
        'customer': repair['beneficiaryName']?.toString() ?? '',
        'method': 'تسوية ملف',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<RepairSettlementResult> apply({
    required String repairId,
    required double adjustment,
    required String reason,
    String? note,
    String? actorId,
    String? operationId,
    Database? database,
  }) async {
    final signed = _round2(adjustment);
    final cleanReason = reason.trim();
    final cleanNote = note?.trim() ?? '';
    final operationKey = operationId?.trim().isNotEmpty == true
        ? operationId!.trim()
        : _uuid.v4();
    if (signed.abs() < 0.01) {
      throw ArgumentError('قيمة التسوية يجب أن تكون أكبر من صفر.');
    }
    if (cleanReason.isEmpty) {
      throw ArgumentError('سبب التسوية مطلوب.');
    }

    final db = database ?? await DBService.database;
    final actor = actorId?.trim().isNotEmpty == true
        ? actorId!.trim()
        : (await CurrentUserContext.userId() ?? 'LOCAL_USER');
    final settlementId = operationKey;
    final createdAt = DateTime.now().toUtc();
    return SyncFoundationService.transaction<RepairSettlementResult>(
      db,
      (tx) async {
        await ensureSchema(executor: tx);

        final prior = await tx.query(
          'repair_settlements',
          where: 'operation_id=?',
          whereArgs: [operationKey],
          limit: 1,
        );
        if (prior.isNotEmpty) {
          final row = Map<String, Object?>.from(prior.single);
          final sameRequest = row['repair_id']?.toString() == repairId &&
              (_d(row['adjustment']) - signed).abs() <= 0.005 &&
              row['reason']?.toString().trim() == cleanReason &&
              (row['note']?.toString().trim() ?? '') == cleanNote;
          if (!sameRequest) {
            throw StateError(
              'تم استخدام معرّف عملية التسوية بطلب مختلف سابقًا.',
            );
          }
          return _resultFromRow(row);
        }

        final rows = await tx.query(
          'repairs',
          where: 'id=?',
          whereArgs: [repairId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('ملف الإصلاح غير موجود.');
        }
        final beforeRow = Map<String, Object?>.from(rows.single);
        if ((beforeRow['status'] ?? '').toString().toUpperCase() ==
            RepairAutoAccountingService.cancelledStatus) {
          throw StateError('لا يمكن تسوية ملف ملغى.');
        }

        final clientRaw = beforeRow['client_id'];
        final clientId = clientRaw is int
            ? clientRaw
            : int.tryParse(clientRaw?.toString() ?? '');
        if (clientId == null || clientId <= 0) {
          throw StateError('الملف غير مرتبط بعميل صالح.');
        }

        final oldValue = _round2(_d(beforeRow['fileValue']));
        var newValue = _round2(oldValue + signed);
        if (newValue < -0.005) {
          throw StateError(
            'لا يمكن أن تصبح قيمة الملف سالبة. '
            'القيمة الحالية: ${oldValue.toStringAsFixed(2)}',
          );
        }
        if (newValue < 0) newValue = 0;

        final beforeTruth = await RepairFinancialTruthService.load(
          repairId,
          executor: tx,
        );
        final rawPaymentType = (beforeRow['paymentType'] ?? 'cash').toString();
        final wasAutoManaged = (beforeRow['notes'] ?? '')
            .toString()
            .contains(RepairAutoAccountingService.autoMarker);
        final accountingReason = cleanNote.isEmpty
            ? 'تسوية ملف — $cleanReason'
            : 'تسوية ملف — $cleanReason — $cleanNote';

        final adjustmentGlId =
            await RepairAutoAccountingService.reconcileEditedValueOn(
          tx: tx,
          repairId: repairId,
          clientId: clientId,
          oldValue: oldValue,
          newValue: newValue,
          wasAutoManaged: wasAutoManaged,
          paymentType: rawPaymentType,
          reason: accountingReason,
          preserveOperationalStatus: true,
          reconcilePostedLedger: true,
          adjustmentSource: 'REPAIR_SETTLEMENT',
          adjustmentId: settlementId,
        );

        final afterTruth = await RepairFinancialTruthService.load(
          repairId,
          executor: tx,
        );
        if ((afterTruth.fileValue - newValue).abs() > 0.005 ||
            !afterTruth.isLedgerConsistent) {
          throw StateError(
            'تعذر اعتماد التسوية لأن الرصيد المحاسبي لم يتطابق مع قيمة الملف.',
          );
        }

        final currentRows = await tx.query(
          'repairs',
          where: 'id=?',
          whereArgs: [repairId],
          limit: 1,
        );
        final afterRow = Map<String, Object?>.from(currentRows.single);
        final invoiceId = await _invoiceIdForRepair(tx, repairId, afterRow);
        await _syncLegacyArSnapshot(
          db: tx,
          repair: afterRow,
          truth: afterTruth,
        );

        await tx.insert('repair_settlements', <String, Object?>{
          'id': settlementId,
          'operation_id': operationKey,
          'repair_id': repairId,
          'invoice_id': invoiceId,
          'old_value': oldValue,
          'adjustment': signed,
          'new_value': newValue,
          'paid_at_settlement': afterTruth.paid,
          'remaining_before': beforeTruth.remaining,
          'remaining_after': afterTruth.remaining,
          'credit_after': afterTruth.credit,
          'customer_ar_after': afterTruth.customerArBalance,
          'revenue_after': afterTruth.recognizedRevenue,
          'gl_entry_id': adjustmentGlId,
          'reason': cleanReason,
          'note': cleanNote.isEmpty ? null : cleanNote,
          'created_by': actor,
          'created_at': createdAt.toIso8601String(),
        });

        await AuditTrailService.log(
          executor: tx,
          action: 'REPAIR_SETTLEMENT_APPLIED',
          entityType: 'repair',
          entityId: repairId,
          before: beforeRow,
          after: afterRow,
          reason: accountingReason,
          metadata: <String, Object?>{
            'settlement_id': settlementId,
            'operation_id': operationKey,
            'adjustment': signed,
            'old_value': oldValue,
            'new_value': newValue,
            'paid': afterTruth.paid,
            'remaining': afterTruth.remaining,
            'credit': afterTruth.credit,
            'gl_entry_id': adjustmentGlId,
            'actor': actor,
          },
        );

        return RepairSettlementResult(
          id: settlementId,
          repairId: repairId,
          oldValue: oldValue,
          adjustment: signed,
          newValue: newValue,
          paid: afterTruth.paid,
          remaining: afterTruth.remaining,
          credit: afterTruth.credit,
          customerArBalance: afterTruth.customerArBalance,
          recognizedRevenue: afterTruth.recognizedRevenue,
          reason: cleanReason,
          createdBy: actor,
          createdAt: createdAt,
          glEntryId: adjustmentGlId,
        );
      },
    );
  }
}
