import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';

/// Automatic accounting lifecycle for repair files.
///
/// Product rule:
/// - saving a repair activates it immediately;
/// - a positive value is posted automatically;
/// - later value changes create immutable correcting GL entries;
/// - delete is a user-facing soft delete with formal GL reversals;
/// - repairs with receipts cannot be deleted until those receipts are handled.
class RepairAutoAccountingService {
  RepairAutoAccountingService._();

  static const String autoMarker = '[YALLA_AUTO_ACCOUNTING_V1]';
  static const String deletedMarker = '[YALLA_DELETED]';
  static const String cancelledStatus = 'CANCELLED';
  static const _uuid = Uuid();

  static double _toDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));

  static bool workshopSuppliesParts(String? notes) {
    final value = notes ?? '';
    if (value.contains('[YALLA_PARTS_SUPPLY] العميل')) return false;
    if (value.contains('[YALLA_PARTS_SUPPLY] شركة التأمين')) return false;
    return true;
  }

  static double _lineTotal(Map<String, dynamic> line) {
    final explicit = _toDouble(line['total']);
    if (explicit > 0) return _round2(explicit);
    final qty = _toDouble(line['qty'] ?? line['quantity']);
    final price = _toDouble(
      line['price'] ??
          line['unit_price'] ??
          line['unitPrice'] ??
          line['amount'],
    );
    return _round2((qty <= 0 ? 1.0 : qty) * price);
  }

  /// Pure helper used by tests and edit screens.
  static double computeAccountingTotal({
    required List<Map<String, dynamic>> works,
    required List<Map<String, dynamic>> parts,
    required String? notes,
  }) {
    final worksTotal = works.fold<double>(
      0.0,
      (sum, line) => sum + _lineTotal(line),
    );
    final partsTotal = workshopSuppliesParts(notes)
        ? parts.fold<double>(
            0.0,
            (sum, line) => sum + _lineTotal(line),
          )
        : 0.0;
    return _round2(worksTotal + partsTotal);
  }

  static String paymentStatusFor(double total, double paid) {
    final t = _round2(total);
    final p = _round2(paid);
    if (t <= 0) return 'مسدد';
    if (p >= t) return 'مسدد';
    if (p > 0) return 'مسدد جزئي';
    return 'غير مسدد';
  }

  static Future<double> _sumPaymentsOn(
    DatabaseExecutor tx,
    String repairId,
  ) async =>
      RepairFinancialTruthService.paidForRepair(repairId, executor: tx);

  static Future<void> _ensureAdjustmentSchema(DatabaseExecutor tx) async {
    await tx.execute('''
      CREATE TABLE IF NOT EXISTS repair_accounting_adjustments(
        id TEXT PRIMARY KEY,
        repair_id TEXT NOT NULL,
        invoice_id TEXT,
        old_value REAL NOT NULL,
        new_value REAL NOT NULL,
        difference REAL NOT NULL,
        gl_entry_id INTEGER,
        reason TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await tx.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_accounting_adjustments_repair '
      'ON repair_accounting_adjustments(repair_id)',
    );
  }

  static Future<List<Map<String, dynamic>>> _loadLines(
    DatabaseExecutor tx,
    String repairId,
  ) async {
    final info = await tx.rawQuery('PRAGMA table_info(repair_lines)');
    final columns = info
        .map((row) => (row['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toSet();

    String? first(List<String> candidates) {
      for (final candidate in candidates) {
        if (columns.contains(candidate)) return candidate;
      }
      return null;
    }

    final repairColumn = first(const ['repair_id', 'repairId']);
    if (repairColumn == null) {
      throw StateError('تعذر تحديد رابط بنود ملف الإصلاح.');
    }

    final rows = await tx.query(
      'repair_lines',
      where: '$repairColumn = ?',
      whereArgs: [repairId],
      orderBy: columns.contains('created_at') ? 'created_at ASC' : null,
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static String _lineType(Map<String, dynamic> row) {
    return (row['line_type'] ?? row['type'] ?? row['category'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  static Map<String, dynamic> _lineForJson(Map<String, dynamic> row) {
    final qty = _toDouble(row['qty'] ?? row['quantity']);
    final price = _toDouble(
      row['price'] ?? row['unit_price'] ?? row['unitPrice'] ?? row['amount'],
    );
    final total = _toDouble(row['total'] ?? row['line_total'] ?? row['amount']);
    return <String, dynamic>{
      'name': (row['name'] ?? row['description'] ?? row['item_name'] ?? '')
          .toString(),
      'qty': qty <= 0 ? 1.0 : qty,
      'price': price,
      'total':
          total > 0 ? _round2(total) : _round2((qty <= 0 ? 1.0 : qty) * price),
      if (row['notes'] != null) 'notes': row['notes'],
    };
  }

  static String _withAutoMarker(String? notes) {
    final value = (notes ?? '').trim();
    if (value.contains(autoMarker)) return value;
    if (value.isEmpty) return autoMarker;
    return '$value\n$autoMarker';
  }

  static Future<int> _ensureClientAccountOn(
    DatabaseExecutor tx,
    int clientId,
  ) async {
    final clientRows = await tx.query(
      'clients',
      columns: const ['name', 'account_id'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (clientRows.isEmpty) {
      throw StateError('تعذر العثور على حساب العميل المرتبط بالملف.');
    }

    final existing = clientRows.first['account_id'];
    if (existing != null) {
      return existing is int ? existing : int.parse(existing.toString());
    }

    final code = '1200.C$clientId';
    final accountRows = await tx.query(
      'accounts',
      columns: const ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );

    int accountId;
    if (accountRows.isNotEmpty) {
      final raw = accountRows.first['id'];
      accountId = raw is int ? raw : int.parse(raw.toString());
    } else {
      accountId = await tx.insert('accounts', {
        'code': code,
        'name': 'عميل: ${(clientRows.first['name'] ?? clientId).toString()}',
        'type': 'ASSET',
        'normal_balance': 'DEBIT',
      });
    }

    await tx.update(
      'clients',
      {'account_id': accountId},
      where: 'id = ?',
      whereArgs: [clientId],
    );
    return accountId;
  }

  static Future<int> _revenueAccountOn(DatabaseExecutor tx) async {
    final rows = await tx.query(
      'accounts',
      columns: const ['id'],
      where: 'code = ?',
      whereArgs: const ['4000'],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('حساب إيرادات الإصلاح 4000 غير موجود.');
    }
    final raw = rows.first['id'];
    return raw is int ? raw : int.parse(raw.toString());
  }

  static Future<double> _recognizedRevenueOn(
    DatabaseExecutor tx,
    String repairId,
  ) async {
    final rows = await tx.rawQuery('''
      SELECT IFNULL(SUM(l.credit - l.debit), 0) AS amount
      FROM gl_lines l
      JOIN accounts a ON a.id = l.account_id
      WHERE l.repair_id = ? AND a.code = '4000'
    ''', [repairId]);
    return rows.isEmpty ? 0.0 : _round2(_toDouble(rows.first['amount']));
  }

  static Future<Map<String, Object?>?> _invoiceOn(
    DatabaseExecutor tx,
    String repairId,
  ) async {
    final rows = await tx.query(
      'invoices',
      where: 'repair_id = ?',
      whereArgs: [repairId],
      orderBy: 'datetime(created_at) ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<int?> _invoiceGlIdOn(
    DatabaseExecutor tx,
    String invoiceId,
  ) async {
    final rows = await tx.query(
      'gl_entries',
      columns: const ['id'],
      where: 'source = ? AND source_id = ?',
      whereArgs: ['INVOICE', invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['id'];
    return raw is int ? raw : int.parse(raw.toString());
  }

  static Future<int> _postValueAdjustmentOn({
    required DatabaseExecutor tx,
    required String repairId,
    required int clientId,
    required String? invoiceId,
    required double oldValue,
    required double newValue,
    required double difference,
    required String reason,
    String source = 'REPAIR_VALUE_ADJ',
    String? eventId,
  }) async {
    final diff = _round2(difference);
    if (diff.abs() < 0.01) return 0;

    final arId = await _ensureClientAccountOn(tx, clientId);
    final revenueId = await _revenueAccountOn(tx);
    final adjustmentId = eventId ?? _uuid.v4();
    final absDiff = diff.abs();

    final lines = diff > 0
        ? <Map<String, Object?>>[
            {
              'account_id': arId,
              'debit': absDiff,
              'credit': 0.0,
              'party_type': 'CLIENT',
              'party_id': clientId.toString(),
              'invoice_id': invoiceId,
              'repair_id': repairId,
            },
            {
              'account_id': revenueId,
              'debit': 0.0,
              'credit': absDiff,
              'invoice_id': invoiceId,
              'repair_id': repairId,
            },
          ]
        : <Map<String, Object?>>[
            {
              'account_id': arId,
              'debit': 0.0,
              'credit': absDiff,
              'party_type': 'CLIENT',
              'party_id': clientId.toString(),
              'invoice_id': invoiceId,
              'repair_id': repairId,
            },
            {
              'account_id': revenueId,
              'debit': absDiff,
              'credit': 0.0,
              'invoice_id': invoiceId,
              'repair_id': repairId,
            },
          ];

    final glId = await DBService.postEntryGLOn(
      ex: tx,
      date: DateTime.now(),
      ref: invoiceId ?? repairId,
      source: source,
      sourceId: adjustmentId,
      note: reason,
      lines: lines,
    );

    await tx.insert('repair_accounting_adjustments', {
      'id': adjustmentId,
      'repair_id': repairId,
      'invoice_id': invoiceId,
      'old_value': _round2(oldValue),
      'new_value': _round2(newValue),
      'difference': diff,
      'gl_entry_id': glId,
      'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return glId;
  }

  static Future<String?> _ensureAccountingDocumentOn({
    required DatabaseExecutor tx,
    required String repairId,
    required int clientId,
    required double value,
    required String paymentType,
  }) async {
    final invoice = await _invoiceOn(tx, repairId);

    if (invoice == null) {
      if (value <= 0) return null;
      return InvoiceService.I.createInvoiceOnTransaction(
        txn: tx,
        repairId: repairId,
        date: DateTime.now(),
        total: value,
        subtotal: value,
        vatAmount: 0.0,
        status: 'unpaid',
        notes: 'فاتورة ملف إصلاح ($repairId)',
        method: paymentType,
        clientId: clientId,
        postToGL: true,
      );
    }

    final invoiceId = invoice['id'].toString();
    final glId = await _invoiceGlIdOn(tx, invoiceId);

    if (glId == null) {
      if (value <= 0) {
        await tx.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);
        await tx.update(
          'repairs',
          {'invoice_id': null, 'invoiceId': null},
          where: 'id = ?',
          whereArgs: [repairId],
        );
        return null;
      }
      return InvoiceService.I.createInvoiceOnTransaction(
        txn: tx,
        id: invoiceId,
        repairId: repairId,
        date: DateTime.now(),
        total: value,
        subtotal: value,
        vatAmount: 0.0,
        status: 'unpaid',
        notes: 'فاتورة ملف إصلاح ($repairId)',
        method: paymentType,
        clientId: clientId,
        postToGL: true,
      );
    }

    return invoiceId;
  }

  /// Called from the P07 intake transaction after repair_lines are persisted.
  static Future<void> finalizeNewRepairOn(
    DatabaseExecutor tx,
    String repairId,
  ) async {
    await _ensureAdjustmentSchema(tx);

    final repairRows = await tx.query(
      'repairs',
      where: 'id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (repairRows.isEmpty) throw StateError('ملف الإصلاح غير موجود.');

    final repair = repairRows.first;
    if (repair['status'] == cancelledStatus) {
      throw StateError('Cancelled repair cannot be posted.');
    }
    final clientRaw = repair['client_id'];
    final clientId = clientRaw is int
        ? clientRaw
        : int.tryParse((clientRaw ?? '').toString());
    if (clientId == null || clientId <= 0) {
      throw StateError('لا يمكن اعتماد الملف دون عميل صالح.');
    }

    final notes = _withAutoMarker(repair['notes']?.toString());
    final rawLines = await _loadLines(tx, repairId);
    final works = <Map<String, dynamic>>[];
    final parts = <Map<String, dynamic>>[];
    for (final row in rawLines) {
      final type = _lineType(row);
      final normalized = _lineForJson(row);
      if (type.contains('part') || type.contains('قط')) {
        parts.add(normalized);
      } else {
        works.add(normalized);
      }
    }

    final total = computeAccountingTotal(
      works: works,
      parts: parts,
      notes: notes,
    );
    final paid = await _sumPaymentsOn(tx, repairId);
    final paymentType = (repair['paymentType'] ?? 'cash').toString();

    final invoiceId = await _ensureAccountingDocumentOn(
      tx: tx,
      repairId: repairId,
      clientId: clientId,
      value: total,
      paymentType: paymentType,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    await tx.update(
      'repairs',
      {
        'parts': jsonEncode(parts),
        'works': jsonEncode(works),
        'fileValue': total,
        'incomeAmount': total,
        'finalApprovedAmount': total,
        'paidAmount': paid,
        'total_paid_amount': paid,
        'paymentStatus': paymentStatusFor(total, paid),
        'status': 'APPROVED',
        'approved_at': now,
        'approved_by': 'AUTO_SAVE',
        'isLedgerEnabled': 1,
        'isLedgerSynced': 1,
        'notes': notes,
        if (invoiceId != null) 'invoice_id': invoiceId,
        if (invoiceId != null) 'invoiceId': invoiceId,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [repairId],
    );
    await AuditTrailService.log(
        executor: tx,
        action: 'REPAIR_FINANCIAL_CREATED',
        entityType: 'repair',
        entityId: repairId,
        before: repair,
        after: (await tx.query('repairs', where: 'id=?', whereArgs: [repairId]))
            .single,
        reason: 'Initial financial posting');
  }

  /// Reconciles a value change after an edit while keeping posted documents
  /// immutable. [wasAutoManaged] should describe the state before this edit.
  static Future<int?> reconcileEditedValueOn({
    required DatabaseExecutor tx,
    required String repairId,
    required int clientId,
    required double oldValue,
    required double newValue,
    required bool wasAutoManaged,
    required String paymentType,
    String reason = 'تعديل قيمة ملف الإصلاح',
    bool preserveOperationalStatus = false,
    bool reconcilePostedLedger = false,
    String adjustmentSource = 'REPAIR_VALUE_ADJ',
    String? adjustmentId,
  }) async {
    await _ensureAdjustmentSchema(tx);

    final state = await tx.query('repairs',
        columns: ['status'], where: 'id=?', whereArgs: [repairId]);
    if (state.isNotEmpty && state.first['status'] == cancelledStatus) {
      throw StateError('Cancelled repair cannot be edited.');
    }
    final invoiceBefore = await _invoiceOn(tx, repairId);
    final invoiceIdBefore = invoiceBefore?['id']?.toString();
    final postedBefore = invoiceIdBefore != null &&
        await _invoiceGlIdOn(tx, invoiceIdBefore) != null;

    final invoiceId = await _ensureAccountingDocumentOn(
      tx: tx,
      repairId: repairId,
      clientId: clientId,
      value: newValue,
      paymentType: paymentType,
    );

    // If this edit created/posted the first invoice, that invoice already posts
    // the full current value. An adjustment is needed only when accounting was
    // already posted before this edit.
    int? adjustmentGlId;
    if (postedBefore && invoiceId != null) {
      final recognized = await _recognizedRevenueOn(tx, repairId);
      // Settlement flows must reconcile against the ledger actually posted,
      // not only against the old repair scalar. Legacy repairs can have a
      // valid posted invoice but no historical auto-accounting marker; using
      // oldValue there preserves an existing GL mismatch and blocks settlement.
      final diff = (reconcilePostedLedger || wasAutoManaged)
          ? _round2(newValue - recognized)
          : _round2(newValue - oldValue);
      adjustmentGlId = await _postValueAdjustmentOn(
        tx: tx,
        repairId: repairId,
        clientId: clientId,
        invoiceId: invoiceId,
        oldValue: oldValue,
        newValue: newValue,
        difference: diff,
        reason: reason,
        source: adjustmentSource,
        eventId: adjustmentId,
      );
    }

    final paid = await _sumPaymentsOn(tx, repairId);
    final now = DateTime.now().toUtc().toIso8601String();
    await tx.update(
      'repairs',
      {
        'fileValue': _round2(newValue),
        'incomeAmount': _round2(newValue),
        'finalApprovedAmount': _round2(newValue),
        'paidAmount': paid,
        'total_paid_amount': paid,
        'paymentStatus': paymentStatusFor(newValue, paid),
        if (!preserveOperationalStatus) 'status': 'APPROVED',
        'isLedgerEnabled': 1,
        'isLedgerSynced': 1,
        if (!preserveOperationalStatus) 'approved_at': now,
        if (!preserveOperationalStatus) 'approved_by': 'AUTO_EDIT',
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [repairId],
    );
    await AuditTrailService.log(
        executor: tx,
        action: 'REPAIR_FINANCIAL_UPDATED',
        entityType: 'repair',
        entityId: repairId,
        before: {'fileValue': oldValue, 'invoice': invoiceBefore},
        after: (await tx.query('repairs', where: 'id=?', whereArgs: [repairId]))
            .single,
        reason: reason);
    return adjustmentGlId;
  }

  static Future<void> deleteRepair(String repairId,
      {String reason = 'Repair cancelled', Database? database}) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Cancellation reason required');
    }
    final db = database ?? await DBService.database;
    await SyncFoundationService.transaction(db, (tx) async {
      await _ensureAdjustmentSchema(tx);

      final repairRows = await tx.query(
        'repairs',
        where: 'id = ?',
        whereArgs: [repairId],
        limit: 1,
      );
      if (repairRows.isEmpty) return;
      if (repairRows.first['status'] == cancelledStatus) return;

      // STAGE1_P0_REPAIR_DELETE_AFTER_REVERSAL
      // Payment rows are immutable audit records. A formal reversal leaves the
      // original row plus a negative reversal row, so COUNT(*) can never become
      // zero again. Gate deletion on the net economic balance instead.
      final paymentBalance = await _sumPaymentsOn(tx, repairId);
      if (paymentBalance.abs() > 0.005) {
        throw StateError(
          'لا يمكن حذف هذا الملف قبل معالجة الدفعات المسجلة عليه. '
          'اعكس الدفعات أولًا ثم أعد الحذف.',
        );
      }

      // Reverse every active revenue-bearing entry for this repair. This keeps
      // the immutable GL audit trail intact instead of deleting accounting data.
      final glRows = await tx.rawQuery('''
        SELECT DISTINCT e.id
        FROM gl_entries e
        JOIN gl_lines l ON l.entry_id = e.id
        JOIN accounts a ON a.id = l.account_id
        WHERE l.repair_id = ?
          AND a.code = '4000'
          AND e.reversal_of IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM gl_entries rev WHERE rev.reversal_of = e.id
          )
        ORDER BY e.id ASC
      ''', [repairId]);

      for (final row in glRows) {
        final raw = row['id'];
        final entryId = raw is int ? raw : int.parse(raw.toString());
        await DBService.reverseEntryGLOn(
          tx,
          entryId,
          note: 'حذف ملف إصلاح $repairId — عكس مالي تلقائي',
        );
      }

      final oldValue = _toDouble(repairRows.first['fileValue']);
      final invoice = await _invoiceOn(tx, repairId);
      final now = DateTime.now().toUtc().toIso8601String();
      final existingNotes = (repairRows.first['notes'] ?? '').toString().trim();
      final deleteNote = '$deletedMarker $now';
      final notes = existingNotes.isEmpty
          ? deleteNote
          : existingNotes.contains(deletedMarker)
              ? existingNotes
              : '$existingNotes\n$deleteNote';

      await tx.insert('repair_accounting_adjustments', {
        'id': _uuid.v4(),
        'repair_id': repairId,
        'invoice_id': invoice?['id']?.toString(),
        'old_value': oldValue,
        'new_value': 0.0,
        'difference': -oldValue,
        'gl_entry_id': null,
        'reason': 'DELETE / CANCEL',
        'created_at': now,
      });

      await tx.update(
        'repairs',
        {
          'fileValue': 0.0,
          'incomeAmount': 0.0,
          'finalApprovedAmount': 0.0,
          'paymentStatus': 'مسدد',
          'status': cancelledStatus,
          'isArchived': 1,
          'isLedgerEnabled': 1,
          'isLedgerSynced': 1,
          'notes': notes,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [repairId],
      );
      final linkedInvoices = await tx
          .query('invoices', where: 'repair_id=?', whereArgs: [repairId]);
      for (final original in linkedInvoices) {
        await tx.update('invoices', {'status': 'VOID', 'updated_at': now},
            where: 'id=?', whereArgs: [original['id']]);
        await AuditTrailService.log(
            executor: tx,
            action: 'INVOICE_VOIDED',
            entityType: 'invoice',
            entityId: '${original['id']}',
            before: original,
            after: {...original, 'status': 'VOID'},
            reason: reason);
      }
      await AuditTrailService.log(
          executor: tx,
          action: 'REPAIR_VOIDED',
          entityType: 'repair',
          entityId: repairId,
          before: repairRows.first,
          after:
              (await tx.query('repairs', where: 'id=?', whereArgs: [repairId]))
                  .single,
          reason: reason,
          metadata: {'reversed_entries': glRows});
    });
  }
}
