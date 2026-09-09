import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
// ============================================================================
// lib/features/repairs/services/edit_repair_service.dart
// P07 Auto Accounting V10B
// Repair details stay editable. Posted accounting entries remain immutable;
// value changes are represented by additive, audited adjustment entries.
// ============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class EditRepairResult {
  final bool success;
  final double? oldValue;
  final double? newValue;
  final double? difference;

  EditRepairResult({
    required this.success,
    this.oldValue,
    this.newValue,
    this.difference,
  });
}

class EditRepairService {
  static const _uuid = Uuid();

  static double _toDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));

  static Map<String, dynamic> _normalizeLine(Map<String, dynamic> raw) {
    final name = (raw['name'] ?? raw['description'] ?? '').toString().trim();
    if (name.isEmpty) throw StateError('اسم بند الإصلاح أو القطعة مطلوب.');
    var qty = _toDouble(raw['qty'] ?? raw['quantity']);
    if (qty <= 0) qty = 1.0;
    final price = _toDouble(
      raw['price'] ?? raw['unit_price'] ?? raw['unitPrice'] ?? raw['amount'],
    );
    if (price < 0) throw StateError('سعر البند لا يمكن أن يكون سالبًا.');
    return <String, dynamic>{
      ...raw,
      'name': name,
      'qty': qty,
      'price': price,
      'total': _round2(qty * price),
    };
  }

  static List<Map<String, dynamic>> _normalizeLines(
    List<Map<String, dynamic>> lines,
  ) =>
      lines.map(_normalizeLine).toList(growable: false);

  static Future<double> _paidOn(DatabaseExecutor tx, String repairId) async =>
      RepairFinancialTruthService.paidForRepair(repairId, executor: tx);

  static Future<void> _replaceRepairLinesOn(
    DatabaseExecutor tx, {
    required String repairId,
    required List<Map<String, dynamic>> parts,
    required List<Map<String, dynamic>> works,
  }) async {
    await tx
        .delete('repair_lines', where: 'repair_id = ?', whereArgs: [repairId]);
    final now = DateTime.now().toIso8601String();

    Future<void> insert(String type, Map<String, dynamic> line) async {
      await tx.insert(
        'repair_lines',
        <String, Object?>{
          'id': _uuid.v4(),
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

    for (final line in parts) {
      await insert('part', line);
    }
    for (final line in works) {
      await insert('work', line);
    }
  }

  static String _ensureAutoMarker(String notes) {
    final value = notes.trim();
    if (value.contains(RepairAutoAccountingService.autoMarker)) return value;
    return value.isEmpty
        ? RepairAutoAccountingService.autoMarker
        : '$value\n${RepairAutoAccountingService.autoMarker}';
  }

  static Future<EditRepairResult> editRepairWithAccounting({
    required String repairId,
    required Repair updatedRepair,
    required List<Map<String, dynamic>> newParts,
    required List<Map<String, dynamic>> newWorks,
    required String notes,
    required String editedBy,
    Database? database,
  }) async {
    final db = database ?? await DBService.database;
    return SyncFoundationService.transaction<EditRepairResult>(db, (txn) async {
      final original =
          await RepairDatabaseService.getRepairByIdTx(txn, repairId);
      if (original == null) {
        throw StateError('ملف الإصلاح غير موجود ($repairId).');
      }
      if (original.status == RepairAutoAccountingService.cancelledStatus) {
        throw StateError('لا يمكن تعديل ملف محذوف/ملغى.');
      }
      if (updatedRepair.clientId != original.clientId) {
        throw StateError(
          'تغيير العميل لملف قائم يحتاج إجراء مستقل حتى لا تتغير الذمة المالية بصمت.',
        );
      }

      final parts = _normalizeLines(newParts);
      final works = _normalizeLines(newWorks);
      final effectiveNotes = _ensureAutoMarker(notes);
      final newValue = RepairAutoAccountingService.computeAccountingTotal(
        works: works,
        parts: parts,
        notes: effectiveNotes,
      );
      final oldValue = _round2(original.fileValue);
      final paid = _round2(await _paidOn(txn, repairId));
      if (newValue + 0.01 < paid) {
        throw StateError(
          'لا يمكن تخفيض قيمة الملف إلى ${MoneyFormatter.format(newValue)} '
          'لأن عليه دفعات مسجلة بقيمة ${MoneyFormatter.format(paid)}. '
          'عالج الدفعات أولًا ثم أعد التعديل.',
        );
      }

      final rawRows = await txn.query(
        'repairs',
        columns: const <String>['paymentType'],
        where: 'id = ?',
        whereArgs: <Object?>[repairId],
        limit: 1,
      );
      final rawPaymentType = rawRows.isEmpty
          ? updatedRepair.paymentType.name
          : (rawRows.first['paymentType'] ?? updatedRepair.paymentType.name)
              .toString();

      final now = DateTime.now();
      final map = updatedRepair
          .copyWith(
            parts: parts,
            works: works,
            fileValue: newValue,
            finalApprovedAmount: newValue,
            incomeAmount: newValue,
            paidAmount: paid,
            paymentStatus:
                RepairAutoAccountingService.paymentStatusFor(newValue, paid),
            notes: effectiveNotes,
            status: RepairStatusText.approved,
            approvedAt: original.approvedAt ?? now,
            approvedBy: 'AUTO_EDIT',
            isLedgerEnabled: true,
            isLedgerSynced: true,
            updatedAt: now,
          )
          .toMap()
        ..remove('invoice_id')
        ..remove('id');

      // Preserve the raw paymentType marker used by the current intake workflow.
      map['paymentType'] = rawPaymentType;
      map['total_paid_amount'] = paid;
      map['updated_at'] = now.toUtc().toIso8601String();

      await txn.update('repairs', map, where: 'id = ?', whereArgs: [repairId]);
      await _replaceRepairLinesOn(
        txn,
        repairId: repairId,
        parts: parts,
        works: works,
      );

      final clientId = original.clientId;
      if (clientId == null || clientId <= 0) {
        throw StateError(
          'لا يمكن تعديل القيمة محاسبيًا لأن الملف غير مرتبط بعميل صالح.',
        );
      }
      final wasAutoManaged = (original.notes ?? '')
          .contains(RepairAutoAccountingService.autoMarker);
      await RepairAutoAccountingService.reconcileEditedValueOn(
        tx: txn,
        repairId: repairId,
        clientId: clientId,
        oldValue: oldValue,
        newValue: newValue,
        wasAutoManaged: wasAutoManaged,
        paymentType: rawPaymentType,
        reason: 'تعديل ملف الإصلاح بواسطة $editedBy',
      );

      await _insertHistory(
        txn: txn,
        repairId: repairId,
        oldValue: oldValue,
        newValue: newValue,
        editedBy: editedBy,
        notes: notes,
      );

      return EditRepairResult(
        success: true,
        oldValue: oldValue,
        newValue: newValue,
        difference: _round2(newValue - oldValue),
      );
    });
  }

  static Future<void> _insertHistory({
    required DatabaseExecutor txn,
    required String repairId,
    required double oldValue,
    required double newValue,
    required String editedBy,
    required String notes,
  }) async {
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS repair_edit_history(
        id TEXT PRIMARY KEY,
        repair_id TEXT,
        old_value REAL,
        new_value REAL,
        difference REAL,
        edited_by TEXT,
        notes TEXT,
        created_at TEXT
      )
    ''');

    await txn.insert('repair_edit_history', <String, Object?>{
      'id': _uuid.v4(),
      'repair_id': repairId,
      'old_value': _round2(oldValue),
      'new_value': _round2(newValue),
      'difference': _round2(newValue - oldValue),
      'edited_by': editedBy,
      'notes': notes,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
