import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'dart:convert';
// 📁 lib/features/finance/payments/services/payment_service.dart
//
// PaymentService — دفعات + نشر GL بلا معاملات متداخلة.
// - GL: Dr 1000/1010 حسب الطريقة، Cr 1200 أو حساب العميل الفرعي.
// - ربط repair_id و invoice_id و client_id على gl_lines.
// - Idempotent عبر uq_gl_source (source='PAYMENT', source_id=paymentId).
// - عند التعديل: Reverse لقيد PAYMENT ثم Reverse لكل ADJUST ثم ADJUST جديد.
// - عند الحذف: Reverse للجميع ثم حذف السجل.
// - لا استدعاء لخدمات خارج txn. أي recompute للفواتير بعد إغلاق txn.

import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/receipt_tables.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

class ReceiptAllocationInput {
  const ReceiptAllocationInput({
    required this.repairId,
    required this.amount,
    this.paymentId,
  });
  final String repairId;
  final double amount;
  final String? paymentId;
}

class ReceiptInstrumentInput {
  const ReceiptInstrumentInput({
    required this.instrumentKey,
    required this.method,
    required this.amount,
    this.allocations = const [],
    this.unallocatedAmount = 0,
    this.unallocatedPaymentId,
    this.chequeDraft,
    this.bankAccountId,
    this.currency,
  });

  final String instrumentKey;
  final String method;
  final double amount;
  final List<ReceiptAllocationInput> allocations;
  final double unallocatedAmount;
  final String? unallocatedPaymentId;
  final Map<String, dynamic>? chequeDraft;
  final int? bankAccountId;
  final String? currency;
}

class CanonicalReceiptResult {
  const CanonicalReceiptResult({
    required this.receiptNumber,
    required this.paymentIds,
    required this.allocatedAmount,
    required this.customerCredit,
  });

  final int receiptNumber;
  final List<String> paymentIds;
  final double allocatedAmount;
  final double customerCredit;
}

class PaymentService {
  static const String table = 'payments';

  static const _kStatusConfirmed = 'confirmed';
  static const _kPartyClient = 'CLIENT';

  // ─────────── Utils ───────────
  static String _resolveAccountFromMethod(String methodRaw) {
    final m = methodRaw.trim().toLowerCase();
    const cash = {'cash', 'صندوق', 'كاش', 'نقد', 'نقدا', 'نقدًا'};
    const bank = {
      'bank',
      'بنك',
      'تحويل',
      'تحويل بنكي',
      'تحويل تأمين',
      'حوالة',
      'حوالة تأمين',
      'card',
      'credit',
      'bank_transfer',
      'transfer',
      'visa',
      'master',
      'بطاقة',
      'فيزا',
      'ماستر',
      'pos'
    };

    if (cash.any((e) => m.contains(e))) return 'الصندوق';
    if (bank.any((e) => m.contains(e))) return 'البنك';

    // شيكات → حساب وسيط خاص
    if (m.contains('cheque') || m.contains('شيك') || m.contains('check')) {
      return 'شيكات';
    }

    return 'الصندوق';
  }

  static String _pickRepairId(Payment p) {
    final a = (p.repairId ?? '').trim();
    final b = (p.relatedRepairId ?? '').trim();
    return a.isNotEmpty ? a : b;
  }

  static bool _needsAdjust(Payment prev, Payment next) {
    return (prev.amount.toStringAsFixed(2) != next.amount.toStringAsFixed(2)) ||
        (prev.method.trim().toLowerCase() !=
            next.method.trim().toLowerCase()) ||
        ((prev.clientId ?? 0) != (next.clientId ?? 0)) ||
        ((prev.invoiceId ?? '') != (next.invoiceId ?? '')) ||
        (_pickRepairId(prev) != _pickRepairId(next)) ||
        (prev.date.toIso8601String() != next.date.toIso8601String());
  }

  // ─────────── Schema ───────────
  static Future<void> _ensureTableAndSchema(DatabaseExecutor exec) async {
    await ReceiptTables.createAllTables(exec);
    await exec.execute('''
CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  receipt_number INTEGER,
  reversal_of_payment_id TEXT,
  client_id INTEGER,
  repair_id TEXT,
  invoice_id TEXT,
  relatedRepairId TEXT,
  amount REAL NOT NULL,
  date TEXT NOT NULL,
  method TEXT NOT NULL,
  accountName TEXT,
  status TEXT NOT NULL DEFAULT 'confirmed',
  notes TEXT,
  attachments TEXT,
  gl_entry_id INTEGER,
  cheque_id INTEGER,
  isIncome INTEGER NOT NULL DEFAULT 1
)
    ''');
    final paymentColumns = await exec.rawQuery('PRAGMA table_info(payments)');
    final names = paymentColumns.map((row) => row['name']?.toString()).toSet();
    if (!names.contains('receipt_number')) {
      await exec
          .execute('ALTER TABLE payments ADD COLUMN receipt_number INTEGER');
    }
    if (!names.contains('reversal_of_payment_id')) {
      await exec.execute(
        'ALTER TABLE payments ADD COLUMN reversal_of_payment_id TEXT',
      );
    }
    await exec.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_receipt_num ON payments(receipt_number)',
    );
    await exec.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_reversal_of ON payments(reversal_of_payment_id)',
    );

    await exec.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_client ON $table(client_id)');
    await exec.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_repair ON $table(repair_id)');
    await exec.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_invoice ON $table(invoice_id)');
    await exec.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_date ON $table(date)');
    await exec.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_gl ON $table(gl_entry_id)');
  }

  // ─────────── Helpers on the SAME txn ───────────

  // يلتقط/ينشئ فاتورة خفيفة داخل نفس txn
  static Future<String?> _findInvoiceIdOnTxn({
    required Transaction txn,
    required String repairId,
  }) async {
    if (repairId.trim().isEmpty) return null;

    final invRow = await txn.rawQuery(
      'SELECT id FROM invoices WHERE repair_id=? LIMIT 1',
      [repairId],
    );

    if (invRow.isEmpty) return null;

    final id = (invRow.first['id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  static Future<int> _ensureClientAccountOnTxn(
      Transaction txn, int clientId) async {
    final cur = await txn.query('clients',
        columns: ['name', 'account_id'],
        where: 'id=?',
        whereArgs: [clientId],
        limit: 1);
    if (cur.isEmpty) throw StateError('client not found');
    final exist = cur.first['account_id'];
    if (exist != null) {
      return (exist is int) ? exist : int.parse(exist.toString());
    }
    final name = (cur.first['name'] ?? 'عميل $clientId').toString();
    final accId = await txn.insert('accounts', {
      'code': '1200.C$clientId',
      'name': 'عميل: $name',
      'type': 'ASSET',
      'normal_balance': 'DEBIT',
    });
    await txn.update('clients', {'account_id': accId},
        where: 'id=?', whereArgs: [clientId]);
    return accId;
  }

  static Future<int?> _getAccountIdByCode(
      DatabaseExecutor db, String code) async {
    final r = await db.query('accounts',
        columns: ['id'], where: 'code=?', whereArgs: [code], limit: 1);
    if (r.isEmpty) return null;
    final v = r.first['id'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  static Future<bool> _glExists(DatabaseExecutor db, String paymentId) async {
    final linked = await db.query(
      table,
      columns: const ['gl_entry_id'],
      where: 'id=?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (linked.isNotEmpty && linked.first['gl_entry_id'] != null) return true;
    final r = await db.query(
      'gl_entries',
      columns: const ['id'],
      where: 'source=? AND source_id=?',
      whereArgs: ['PAYMENT', paymentId],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  static String _fingerprint({
    required double amount,
    required String dateIso,
    required String accountName,
    required int clientId,
    required String invoiceId,
    required String repairId,
    required String method,
  }) {
    return [
      amount.toStringAsFixed(2),
      dateIso,
      accountName,
      clientId.toString(),
      invoiceId,
      repairId,
      method.trim().toLowerCase(),
    ].join('|');
  }

  // ─────────── CRUD ───────────

  static Future<void> insert(Payment payment) async {
    final db = await DBService.database;
    await SyncFoundationService.transaction(db, (txn) async {
      await _ensureTableAndSchema(txn);
      final map = payment.toMap();
      map['id'] ??= const Uuid().v4();
      final statusStr = '${map['status'] ?? ''}'.trim();
      map['status'] = statusStr.isEmpty ? _kStatusConfirmed : statusStr;
      await txn.insert(table, map, conflictAlgorithm: ConflictAlgorithm.abort);
      await AuditTrailService.log(
          executor: txn,
          action: 'PAYMENT_CREATED',
          entityType: 'PAYMENT',
          entityId: '${map['id']}',
          after: map);
    });
  }

  static Future<int> update(Payment payment) async {
    final db = await DBService.database;
    String? repairForPost;
    final updated = await SyncFoundationService.transaction(db, (txn) async {
      await _ensureTableAndSchema(txn);

      final prevRows = await txn.query(table,
          where: 'id=?', whereArgs: [payment.id], limit: 1);
      if (prevRows.isEmpty) {
        // لا يوجد سجل سابق → أدخل كجديد ثم GL
        final map = payment.toMap();
        map['id'] ??= const Uuid().v4();
        final statusStr = '${map['status'] ?? ''}'.trim();
        map['status'] = statusStr.isEmpty ? _kStatusConfirmed : statusStr;
        await txn.insert(table, map,
            conflictAlgorithm: ConflictAlgorithm.abort);

        final rid = _pickRepairId(payment);
        if (rid.isNotEmpty) {
          repairForPost = rid;
          await _ensurePaymentGLAndLinksOnTxn(
            txn: txn,
            paymentId: map['id'] as String,
            payment: payment,
            accountName: _resolveAccountFromMethod(payment.method),
            customerName: '',
            repairId: rid,
          );
          await _refreshRepairSnapshot(txn, rid);
        }
        await AuditTrailService.log(
            executor: txn,
            action: 'PAYMENT_CREATED',
            entityType: 'PAYMENT',
            entityId: '${map['id']}',
            after:
                (await txn.query(table, where: 'id=?', whereArgs: [map['id']]))
                    .single);
        return 1;
      }

      final prev = Payment.fromMap(prevRows.first);

      if (await _glExists(txn, payment.id)) {
        throw StateError(
          'Posted receipt ${payment.id} is immutable. '
          'Use a formal reversal/correcting receipt workflow.',
        );
      }

      final map = payment.toMap();
      final statusStr = '${map['status'] ?? ''}'.trim();
      map['status'] = statusStr.isEmpty ? _kStatusConfirmed : statusStr;
      final count = await txn.update(
        table,
        map,
        where: 'id = ?',
        whereArgs: [payment.id],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final needsAdjust = _needsAdjust(prev, payment);
      final pickedRepairId = _pickRepairId(payment);
      repairForPost = pickedRepairId.isEmpty ? null : pickedRepairId;

      if (needsAdjust) {
        await _reverseIfExists(txn, payment.id);
        await _reverseAdjustsIfAny(txn, payment.id);
        await _postAdjustOnTxn(txn: txn, payment: payment);
      } else {
        await _ensurePaymentGLAndLinksOnTxn(
          txn: txn,
          paymentId: payment.id,
          payment: payment,
          accountName: _resolveAccountFromMethod(payment.method),
          customerName: '',
          repairId: repairForPost,
        );
      }

      if (repairForPost != null) {
        await _refreshRepairSnapshot(txn, repairForPost!);
      }
      await AuditTrailService.log(
          executor: txn,
          action: 'PAYMENT_UPDATED',
          entityType: 'PAYMENT',
          entityId: payment.id,
          before: prevRows.single,
          after:
              (await txn.query(table, where: 'id=?', whereArgs: [payment.id]))
                  .single);
      return count;
    });

    // بعد إغلاق الصفقة: أعد احتساب الفاتورة
    try {
      if (repairForPost != null && repairForPost!.isNotEmpty) {
        await InvoiceService.I.recomputeForRepair(repairForPost!);
      }
    } catch (_) {}
    return updated;
  }

  static Future<int> delete(String id,
      {String reason = 'Payment cancelled'}) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Cancellation reason required');
    }
    final db = await DBService.database;
    final rows = await db.query(table, where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return 0;
    final payment = Payment.fromMap(rows.single);
    if (['void', 'reversed', 'reversal']
        .contains(payment.status.toLowerCase())) {
      return 0;
    }
    if (payment.isIncome && await _glExists(db, id)) {
      await reverseReceiptByPaymentId(id, reason: reason);
      return 1;
    }
    return SyncFoundationService.transaction(db, (txn) async {
      final before =
          (await txn.query(table, where: 'id=?', whereArgs: [id])).single;
      await _reverseIfExists(txn, id);
      await _reverseAdjustsIfAny(txn, id);
      final count = await txn.update(table, {'status': 'void'},
          where: 'id=?', whereArgs: [id]);
      await AuditTrailService.log(
          executor: txn,
          action: 'PAYMENT_VOIDED',
          entityType: 'PAYMENT',
          entityId: id,
          before: before,
          after: {...before, 'status': 'void'},
          reason: reason);
      return count;
    });
  }

  static Future<List<Payment>> getAll() async {
    final db = await DBService.database;
    final maps = await db.query(table, orderBy: 'date DESC, id DESC');
    return maps.map(Payment.fromMap).toList();
  }

  static Future<List<Payment>> getByInvoice(String invoiceId) async {
    final db = await DBService.database;
    final maps = await db.query(
      table,
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map(Payment.fromMap).toList();
  }

  static Future<List<Payment>> filterByDateOrStatus({
    DateTime? from,
    DateTime? to,
    String? status,
    String? partyId,
    String? invoiceId,
    String? clientId,
    String? repairId,
  }) async {
    final db = await DBService.database;

    final where = <String>[];
    final args = <dynamic>[];

    if (from != null) {
      where.add('date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(to.toIso8601String());
    }
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      args.add(status);
    }
    if (clientId != null && clientId.isNotEmpty) {
      where.add('(CAST(client_id AS TEXT) = ?)');
      args.add(clientId);
    }
    if (invoiceId != null && invoiceId.isNotEmpty) {
      where.add('invoice_id = ?');
      args.add(invoiceId);
    }
    if (repairId != null && repairId.isNotEmpty) {
      where.add('(repair_id = ? OR relatedRepairId = ?)');
      args
        ..add(repairId)
        ..add(repairId);
    }

    final maps = await db.query(
      table,
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return maps.map(Payment.fromMap).toList();
  }

  // ───────── P11 Canonical Receipt + GL ─────────
  static Future<int> _nextReceiptNumberOnTxn(DatabaseExecutor db) async {
    await ReceiptTables.createAllTables(db);
    final rows = await db.rawQuery('''
      SELECT COALESCE(MAX(n), 0) + 1 AS next_no
      FROM (
        SELECT MAX(receipt_number) AS n FROM receipt_headers
        UNION ALL
        SELECT MAX(receipt_number) AS n FROM payments
      )
    ''');
    final raw = rows.first['next_no'];
    return raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;
  }

  static String _canonicalReceiptMethod(String raw) {
    final value = raw.trim().toLowerCase();
    if (ChequeAccountingService.isChequeMethod(value)) return 'cheque';
    if (value == 'card' ||
        value == 'credit' ||
        value == 'visa' ||
        value == 'master' ||
        value == 'pos' ||
        value.contains('بطاقة')) {
      return 'card';
    }
    if (value == 'bank_transfer' ||
        value == 'transfer' ||
        value == 'bank' ||
        value.contains('تحويل') ||
        value.contains('حوالة') ||
        value.contains('بنك')) {
      return 'bank_transfer';
    }
    return 'cash';
  }

  static Future<void> _insertReceiptHeaderOnTxn({
    required Transaction txn,
    required int receiptNumber,
    required int clientId,
    required DateTime date,
    required String method,
    required double totalAmount,
    required double allocatedAmount,
    required double creditAmount,
    String status = 'posted',
    int? reversalOfReceiptNumber,
    String? notes,
  }) async {
    await ReceiptTables.createAllTables(txn);
    await txn.insert(
      'receipt_headers',
      {
        'receipt_number': receiptNumber,
        'client_id': clientId,
        'date': date.toIso8601String(),
        'method': method,
        'total_amount': double.parse(totalAmount.toStringAsFixed(2)),
        'allocated_amount': double.parse(allocatedAmount.toStringAsFixed(2)),
        'credit_amount': double.parse(creditAmount.toStringAsFixed(2)),
        'status': status,
        'reversal_of_receipt_number': reversalOfReceiptNumber,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<void> _insertReceiptAllocationOnTxn({
    required Transaction txn,
    required int receiptNumber,
    required Payment payment,
    required String allocationType,
  }) async {
    await ReceiptTables.createAllTables(txn);
    await txn.insert(
      'receipt_allocations',
      {
        'receipt_number': receiptNumber,
        'payment_id': payment.id,
        'repair_id':
            _pickRepairId(payment).isEmpty ? null : _pickRepairId(payment),
        'amount': payment.amount,
        'allocation_type': allocationType,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  static Future<Payment> _insertAndPostReceiptOnTxn({
    required Transaction txn,
    required Payment payment,
    required String customerName,
    required String method,
    required int receiptNumber,
    String? descriptionOverride,
    Map<String, dynamic>? chequeDraft,
    int? chequeIdOverride,
  }) async {
    await _ensureTableAndSchema(txn);
    if (payment.amount <= 0) throw ArgumentError('amount must be > 0');
    if (!payment.isIncome) {
      throw StateError('Canonical receipt accepts income payments only.');
    }

    final canonicalMethod = _canonicalReceiptMethod(method);
    final rawRepairId = payment.repairId?.trim().isNotEmpty == true
        ? payment.repairId!.trim()
        : (payment.relatedRepairId ?? '').trim();
    final repairId = rawRepairId.isEmpty ? null : rawRepairId;
    final accountName = (payment.accountName?.trim().isNotEmpty == true)
        ? payment.accountName!.trim()
        : _resolveAccountFromMethod(canonicalMethod);
    final status = payment.status.trim().isEmpty
        ? _kStatusConfirmed
        : payment.status.trim();
    final paymentId = payment.id.isEmpty ? const Uuid().v4() : payment.id;

    final existing = await txn.query(
      table,
      where: 'id=?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final persisted = Payment.fromMap(existing.first);
      if (['void', 'reversed', 'reversal']
          .contains(persisted.status.toLowerCase())) {
        throw StateError('Cancelled receipt cannot be posted.');
      }
      final sameMaterialDocument =
          (persisted.amount * 100).round() == (payment.amount * 100).round() &&
              _canonicalReceiptMethod(persisted.method) == canonicalMethod &&
              (persisted.clientId ?? 0) == (payment.clientId ?? 0) &&
              _pickRepairId(persisted) == _pickRepairId(payment);
      if (!sameMaterialDocument) {
        throw StateError(
          'Receipt payment $paymentId already exists with different material fields.',
        );
      }
      await _ensurePaymentGLAndLinksOnTxn(
        txn: txn,
        paymentId: paymentId,
        payment: persisted,
        accountName: persisted.accountName?.trim().isNotEmpty == true
            ? persisted.accountName!.trim()
            : accountName,
        customerName: customerName,
        repairId: repairId,
        descriptionOverride: descriptionOverride,
      );
      if (repairId != null) await _refreshRepairSnapshot(txn, repairId);
      return persisted;
    }

    var storedPayment = payment.copyWith(
      id: paymentId,
      receiptNumber: receiptNumber,
      method: canonicalMethod,
      accountName: accountName,
      status: status,
      relatedRepairId: repairId,
    );

    if (ChequeAccountingService.isChequeMethod(canonicalMethod)) {
      if (chequeIdOverride != null) {
        storedPayment = storedPayment.copyWith(chequeId: chequeIdOverride);
      } else {
        if (chequeDraft == null) {
          throw StateError('Cheque receipt requires cheque details.');
        }
        final chequeId = await ChequeAccountingService.createLinkedChequeOnTxn(
          txn: txn,
          draft: chequeDraft,
          type: ChequeType.incoming,
          amount: storedPayment.amount,
          currency:
              (await CommercialSettingsService.instance.get(executor: txn))
                  .baseCurrencyCode,
          sourceType: 'PAYMENT',
          sourceId: paymentId,
          instrumentKey: chequeDraft['instrument_key']?.toString(),
          clientId: storedPayment.clientId,
          sourcePartyType: 'CLIENT',
          sourcePartyId: storedPayment.clientId?.toString(),
          recipientType: 'WORKSHOP',
          recipientName: 'Workshop',
        );
        storedPayment = storedPayment.copyWith(chequeId: chequeId);
      }
    }

    await txn.insert(
      table,
      storedPayment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await _ensurePaymentGLAndLinksOnTxn(
      txn: txn,
      paymentId: paymentId,
      payment: storedPayment,
      accountName: accountName,
      customerName: customerName,
      repairId: repairId,
      descriptionOverride: descriptionOverride,
    );
    if (repairId != null) await _refreshRepairSnapshot(txn, repairId);

    final persistedRows = await txn.query(
      table,
      where: 'id=?',
      whereArgs: [paymentId],
      limit: 1,
    );
    return Payment.fromMap(persistedRows.first);
  }

  static Future<CanonicalReceiptResult> insertCanonicalReceiptWithInstruments({
    required String operationId,
    Database? database,
    required int clientId,
    required String customerName,
    required DateTime date,
    required List<ReceiptInstrumentInput> instruments,
    String? notes,
    String? requestJsonOverride,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.receiptCreate);
    if (clientId <= 0) throw StateError('Receipt requires a valid client.');
    if (operationId.trim().isEmpty) {
      throw ArgumentError('Receipt operation id required');
    }
    if (instruments.isEmpty) {
      throw StateError('Receipt requires at least one payment instrument.');
    }

    final keys = <String>{};
    var requestedTotal = 0.0;
    for (final instrument in instruments) {
      final key = instrument.instrumentKey.trim();
      if (key.isEmpty || !keys.add(key)) {
        throw StateError(
            'Receipt instrument keys must be unique and non-empty.');
      }
      if (!instrument.amount.isFinite || instrument.amount <= 0.005) {
        throw StateError('Receipt instrument amount must be positive.');
      }
      if (!instrument.unallocatedAmount.isFinite ||
          instrument.unallocatedAmount < 0 ||
          instrument.allocations.any(
            (line) => !line.amount.isFinite || line.amount < 0,
          )) {
        throw StateError('Receipt instrument allocations are invalid.');
      }
      final duplicateTargets = <String>{};
      for (final line in instrument.allocations) {
        if (!duplicateTargets.add(line.repairId)) {
          throw StateError(
            'One instrument cannot repeat the same repair allocation.',
          );
        }
      }
      final detailTotal = instrument.allocations.fold<double>(
            0,
            (sum, line) => sum + line.amount,
          ) +
          instrument.unallocatedAmount;
      if ((detailTotal - instrument.amount).abs() > 0.005) {
        throw StateError(
          'Instrument allocations must equal the instrument amount.',
        );
      }
      final canonicalMethod = _canonicalReceiptMethod(instrument.method);
      if (canonicalMethod == 'cheque' && instrument.chequeDraft == null) {
        throw StateError('Cheque instrument requires cheque details.');
      }
      requestedTotal += instrument.amount;
    }

    if (requestedTotal <= 0.005) {
      throw StateError('Receipt amount must be greater than zero.');
    }

    final request = requestJsonOverride ??
        jsonEncode({
          'client': clientId,
          'date': date.toIso8601String(),
          'notes': notes,
          'instruments': [
            for (final instrument in instruments)
              {
                'key': instrument.instrumentKey,
                'method': _canonicalReceiptMethod(instrument.method),
                'amount': instrument.amount,
                'allocations': [
                  for (final a in instrument.allocations)
                    [a.repairId, a.amount, a.paymentId]
                ],
                'unallocated': instrument.unallocatedAmount,
                'unallocated_payment_id': instrument.unallocatedPaymentId,
                'cheque': instrument.chequeDraft,
                'bank_account_id': instrument.bankAccountId,
                'currency': instrument.currency,
              }
          ],
        });

    final db = database ?? await DBService.database;
    final affectedRepairs = <String>{};

    final result =
        await SyncFoundationService.transaction<CanonicalReceiptResult>(
      db,
      (txn) async {
        await _ensureTableAndSchema(txn);
        await ReceiptTables.createAllTables(txn);

        final prior = await txn.query(
          'receipt_requests',
          where: 'operation_id=?',
          whereArgs: [operationId],
        );
        if (prior.isNotEmpty) {
          if (prior.single['request_json'] != request) {
            throw StateError('Receipt retry differs from original request');
          }
          final number = (prior.single['receipt_number'] as num).toInt();
          final headerRows = await txn.query(
            'receipt_headers',
            where: 'receipt_number=?',
            whereArgs: [number],
            limit: 1,
          );
          if (headerRows.isEmpty || headerRows.single['status'] != 'posted') {
            throw StateError('Receipt is no longer active');
          }
          final stored = await txn.query(
            'receipt_allocations',
            where: 'receipt_number=?',
            whereArgs: [number],
          );
          final header = headerRows.single;
          return CanonicalReceiptResult(
            receiptNumber: number,
            paymentIds: stored.map((r) => r['payment_id'].toString()).toList(),
            allocatedAmount: (header['allocated_amount'] as num).toDouble(),
            customerCredit: (header['credit_amount'] as num).toDouble(),
          );
        }

        final receiptNumber = await _nextReceiptNumberOnTxn(txn);
        final paymentIds = <String>[];
        final instrumentRows = <Map<String, Object?>>[];
        final chequeIds = <String, int>{};
        var allocatedAmount = 0.0;
        var creditAmount = 0.0;
        final baseCurrency =
            (await CommercialSettingsService.instance.get(executor: txn))
                .baseCurrencyCode;

        for (final instrument in instruments) {
          final key = instrument.instrumentKey.trim();
          final method = _canonicalReceiptMethod(instrument.method);
          int? chequeId;

          if (method == 'cheque') {
            final draft = Map<String, dynamic>.from(instrument.chequeDraft!);
            draft['instrument_key'] = key;
            chequeId = await ChequeAccountingService.createLinkedChequeOnTxn(
              txn: txn,
              draft: draft,
              type: ChequeType.incoming,
              amount: instrument.amount,
              currency: (instrument.currency ?? baseCurrency).trim(),
              sourceType: 'RECEIPT',
              sourceId: receiptNumber.toString(),
              instrumentKey: key,
              receiptVoucherId: receiptNumber,
              sourcePartyType: 'CLIENT',
              sourcePartyId: clientId.toString(),
              clientId: clientId,
              recipientType: 'WORKSHOP',
              recipientName: 'Workshop',
              bankAccountId: instrument.bankAccountId,
              createdBy: p16Actor?.id,
            );
            chequeIds[key] = chequeId;
          }

          var instrumentAllocated = 0.0;
          var instrumentCredit = instrument.unallocatedAmount;

          for (final line in instrument.allocations) {
            if (line.amount <= 0.005) continue;
            final repairRows = await txn.query(
              'repairs',
              columns: const ['id', 'client_id', 'fileValue'],
              where: 'id=?',
              whereArgs: [line.repairId],
              limit: 1,
            );
            if (repairRows.isEmpty) {
              throw StateError('Repair ' + line.repairId + ' not found.');
            }
            final rawClient = repairRows.first['client_id'];
            final repairClientId = rawClient is num
                ? rawClient.toInt()
                : int.tryParse(rawClient?.toString() ?? '');
            if (repairClientId != clientId) {
              throw StateError(
                'All receipt allocations must belong to the same client.',
              );
            }
            final fileValue =
                (repairRows.first['fileValue'] as num?)?.toDouble() ??
                    double.tryParse(
                      repairRows.first['fileValue']?.toString() ?? '',
                    ) ??
                    0.0;
            final alreadyPaid = await RepairFinancialTruthService.paidForRepair(
              line.repairId,
              executor: txn,
            );
            final remaining =
                (fileValue - alreadyPaid).clamp(0.0, double.infinity);
            final accepted = line.amount > remaining ? remaining : line.amount;
            final overflow = line.amount - accepted;
            if (overflow > 0.005) instrumentCredit += overflow;

            if (accepted <= 0.005) continue;
            final payment = Payment(
              id: line.paymentId?.trim().isNotEmpty == true
                  ? line.paymentId!.trim()
                  : const Uuid().v4(),
              receiptNumber: receiptNumber,
              clientId: clientId,
              repairId: line.repairId,
              relatedRepairId: line.repairId,
              invoiceId: null,
              amount: double.parse(accepted.toStringAsFixed(2)),
              date: date,
              method: method,
              accountName: null,
              status: _kStatusConfirmed,
              notes: notes,
              attachments: null,
              glEntryId: null,
              chequeId: chequeId,
              isIncome: true,
            );
            final stored = await _insertAndPostReceiptOnTxn(
              txn: txn,
              payment: payment,
              customerName: customerName,
              method: method,
              receiptNumber: receiptNumber,
              descriptionOverride: notes,
              chequeIdOverride: chequeId,
            );
            paymentIds.add(stored.id);
            instrumentAllocated += stored.amount;
            allocatedAmount += stored.amount;
            affectedRepairs.add(line.repairId);
            await _insertReceiptAllocationOnTxn(
              txn: txn,
              receiptNumber: receiptNumber,
              payment: stored,
              allocationType: 'REPAIR',
            );
            if (chequeId != null) {
              await ChequeAccountingService.allocateChequeOnTxn(
                txn: txn,
                chequeId: chequeId,
                voucherType: 'RECEIPT',
                voucherId: receiptNumber.toString(),
                allocationType: 'REPAIR',
                targetId: line.repairId,
                amount: stored.amount,
              );
            }
          }

          if (instrumentCredit > 0.005) {
            final credit = Payment(
              id: instrument.unallocatedPaymentId?.trim().isNotEmpty == true
                  ? instrument.unallocatedPaymentId!.trim()
                  : const Uuid().v4(),
              receiptNumber: receiptNumber,
              clientId: clientId,
              repairId: null,
              relatedRepairId: null,
              invoiceId: null,
              amount: double.parse(instrumentCredit.toStringAsFixed(2)),
              date: date,
              method: method,
              accountName: null,
              status: _kStatusConfirmed,
              notes: [
                if (notes?.trim().isNotEmpty == true) notes!.trim(),
                'رصيد دائن غير مخصص للعميل',
              ].join(' — '),
              attachments: null,
              glEntryId: null,
              chequeId: chequeId,
              isIncome: true,
            );
            final stored = await _insertAndPostReceiptOnTxn(
              txn: txn,
              payment: credit,
              customerName: customerName,
              method: method,
              receiptNumber: receiptNumber,
              descriptionOverride: credit.notes,
              chequeIdOverride: chequeId,
            );
            paymentIds.add(stored.id);
            creditAmount += stored.amount;
            await _insertReceiptAllocationOnTxn(
              txn: txn,
              receiptNumber: receiptNumber,
              payment: stored,
              allocationType: 'CREDIT',
            );
            if (chequeId != null) {
              await ChequeAccountingService.allocateChequeOnTxn(
                txn: txn,
                chequeId: chequeId,
                voucherType: 'RECEIPT',
                voucherId: receiptNumber.toString(),
                allocationType: 'CREDIT',
                targetId: null,
                amount: stored.amount,
              );
            }
          }

          final postedForInstrument = instrumentAllocated + instrumentCredit;
          if ((postedForInstrument - instrument.amount).abs() > 0.01) {
            throw StateError(
              'Instrument posting total does not match instrument amount.',
            );
          }

          instrumentRows.add({
            'id': operationId + ':' + key,
            'receipt_number': receiptNumber,
            'instrument_key': key,
            'method': method,
            'amount': instrument.amount,
            'currency': (instrument.currency ?? baseCurrency).trim(),
            'cheque_id': chequeId,
            'bank_account_id': instrument.bankAccountId,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        final methodNames = {
          for (final instrument in instruments)
            _canonicalReceiptMethod(instrument.method)
        };
        final receiptMethod =
            methodNames.length == 1 ? methodNames.single : 'mixed';

        await _insertReceiptHeaderOnTxn(
          txn: txn,
          receiptNumber: receiptNumber,
          clientId: clientId,
          date: date,
          method: receiptMethod,
          totalAmount: requestedTotal,
          allocatedAmount: allocatedAmount,
          creditAmount: creditAmount,
          notes: notes,
        );

        for (final row in instrumentRows) {
          await txn.insert(
            'receipt_instruments',
            row,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }

        for (final entry in chequeIds.entries) {
          final instrument =
              instruments.firstWhere((item) => item.instrumentKey == entry.key);
          await ChequeAccountingService.linkChequeToVoucherOnTxn(
            txn: txn,
            chequeId: entry.value,
            voucherType: 'RECEIPT',
            voucherId: receiptNumber.toString(),
            instrumentKey: entry.key,
            amount: instrument.amount,
          );
        }

        await txn.insert('receipt_requests', {
          'operation_id': operationId,
          'request_json': request,
          'receipt_number': receiptNumber,
        });

        await AuditTrailService.log(
          executor: txn,
          actorUserId: p16Actor?.id,
          actorRole: p16Actor?.role,
          action: 'RECEIPT_POSTED',
          entityType: 'RECEIPT',
          entityId: 'RC-' + receiptNumber.toString().padLeft(6, '0'),
          after: await _receiptSnapshot(txn, receiptNumber),
          metadata: {
            'instrument_count': instruments.length,
            'cheque_count': chequeIds.length,
          },
        );

        return CanonicalReceiptResult(
          receiptNumber: receiptNumber,
          paymentIds: paymentIds,
          allocatedAmount: double.parse(allocatedAmount.toStringAsFixed(2)),
          customerCredit: double.parse(creditAmount.toStringAsFixed(2)),
        );
      },
    );

    for (final repairId in database == null ? affectedRepairs : <String>{}) {
      try {
        await InvoiceService.I.recomputeForRepair(repairId);
      } catch (_) {}
    }
    return result;
  }

  /// One source document, one SQLite transaction, N repair allocations.
  /// Requested over-allocation is capped at each repair's remaining balance;
  /// any surplus becomes an unallocated customer credit line on the same
  /// receipt. A physical cheque remains one payment/one linked cheque.
  static Future<CanonicalReceiptResult> insertCanonicalReceipt({
    required String operationId,
    Database? database,
    required int clientId,
    required String customerName,
    required String method,
    required DateTime date,
    required List<ReceiptAllocationInput> allocations,
    double unallocatedAmount = 0,
    String? unallocatedPaymentId,
    String? notes,
    Map<String, dynamic>? chequeDraft,
  }) async {
    final canonicalMethod = _canonicalReceiptMethod(method);
    final requestedTotal = allocations.fold<double>(
          0,
          (sum, line) => sum + line.amount,
        ) +
        unallocatedAmount;

    final legacyRequest = jsonEncode({
      'client': clientId,
      'method': canonicalMethod,
      'date': date.toIso8601String(),
      'allocations': [
        for (final a in allocations) [a.repairId, a.amount]
      ],
      'unallocated': unallocatedAmount,
      'notes': notes,
      'cheque': chequeDraft,
    });

    final rawKey = chequeDraft?['instrument_key']?.toString().trim();
    final rawUuid = chequeDraft?['uuid']?.toString().trim();
    final instrumentKey = (rawKey != null && rawKey.isNotEmpty)
        ? rawKey
        : (rawUuid != null && rawUuid.isNotEmpty)
            ? rawUuid
            : 'legacy-' + operationId;

    return insertCanonicalReceiptWithInstruments(
      operationId: operationId,
      database: database,
      clientId: clientId,
      customerName: customerName,
      date: date,
      notes: notes,
      requestJsonOverride: legacyRequest,
      instruments: [
        ReceiptInstrumentInput(
          instrumentKey: instrumentKey,
          method: canonicalMethod,
          amount: requestedTotal,
          allocations: allocations,
          unallocatedAmount: unallocatedAmount,
          unallocatedPaymentId: unallocatedPaymentId,
          chequeDraft: chequeDraft,
        ),
      ],
    );
  }

  /// Backward-compatible single-line API. New callers should prefer
  /// insertCanonicalReceipt; legacy callers still receive a real receipt number.
  static Future<void> insertAndPostReceipt({
    required Payment payment,
    required String customerName,
    required String method,
    bool updateInvoice = true,
    String? descriptionOverride,
    Map<String, dynamic>? chequeDraft,
  }) async {
    if (payment.amount <= 0) throw ArgumentError('amount must be > 0');
    if (!payment.isIncome) {
      throw StateError(
        'insertAndPostReceipt accepts receipt/income payments only.',
      );
    }
    final clientId = payment.clientId;
    if (clientId == null || clientId <= 0) {
      throw StateError('Receipt requires a valid client_id.');
    }

    // Preserve retry/idempotency semantics for old callers that supply an ID.
    if (payment.id.trim().isNotEmpty) {
      final db = await DBService.database;
      await _ensureTableAndSchema(db);
      final existing = await db.query(
        table,
        where: 'id=?',
        whereArgs: [payment.id.trim()],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final previous = Payment.fromMap(existing.first);
        if ((previous.amount * 100).round() != (payment.amount * 100).round() ||
            previous.clientId != clientId ||
            _pickRepairId(previous) != _pickRepairId(payment) ||
            _canonicalReceiptMethod(previous.method) !=
                _canonicalReceiptMethod(method) ||
            !previous.isIncome) {
          throw StateError(
              'Payment identifier already belongs to a different receipt.');
        }
        await postPaymentFromDbId(payment.id.trim());
        return;
      }
    }

    final repairId = _pickRepairId(payment);
    await insertCanonicalReceipt(
      operationId: payment.id.trim().isEmpty
          ? const Uuid().v4()
          : 'payment:${payment.id}',
      clientId: clientId,
      customerName: customerName,
      method: method,
      date: payment.date,
      allocations: repairId.isEmpty
          ? const <ReceiptAllocationInput>[]
          : <ReceiptAllocationInput>[
              ReceiptAllocationInput(
                repairId: repairId,
                amount: payment.amount,
                paymentId: payment.id.isEmpty ? null : payment.id,
              ),
            ],
      unallocatedAmount: repairId.isEmpty ? payment.amount : 0,
      unallocatedPaymentId:
          repairId.isEmpty && payment.id.isNotEmpty ? payment.id : null,
      notes: descriptionOverride ?? payment.notes,
      chequeDraft: chequeDraft,
    );
  }

  /// Unallocated customer credit is receipt money already posted to AR but not
  /// yet attributed to a repair, minus any later repair allocations from it.
  static Future<double> customerCreditForClient(
    int clientId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    await _ensureTableAndSchema(db);
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS available
      FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      LEFT JOIN gl_entries original ON original.id=e.reversal_of
      WHERE l.party_id=? AND (a.code='1200' OR a.code LIKE '1200.%')
        AND COALESCE(l.repair_id,'')=''
        AND COALESCE(original.source,e.source) IN
          ('PAYMENT','CREDIT_ALLOCATION','PAYMENT-ADJUST','CHEQUE_STATUS','CHEQUE_ENDORSE')
    ''', [clientId]);
    final raw = rows.first['available'];
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
    return value <= 0.005 ? 0.0 : double.parse(value.toStringAsFixed(2));
  }

  /// Applies previously received customer credit to one repair without moving
  /// cash/bank again. GL only re-dimensions AR from unallocated client credit to
  /// the selected repair, so total customer AR is unchanged.
  static Future<double> allocateCustomerCreditToRepair({
    required int clientId,
    required String repairId,
    required double amount,
    String? notes,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.receiptCreate);
    if (clientId <= 0 || repairId.trim().isEmpty || amount <= 0.005) {
      throw ArgumentError('Valid client, repair and amount are required.');
    }
    final db = await DBService.database;
    final paymentId = const Uuid().v4();
    late double applied;
    await SyncFoundationService.transaction(db, (txn) async {
      await _ensureTableAndSchema(txn);
      await ReceiptTables.createAllTables(txn);
      final repairs = await txn.query(
        'repairs',
        columns: const ['client_id', 'fileValue'],
        where: 'id=?',
        whereArgs: [repairId],
        limit: 1,
      );
      if (repairs.isEmpty) throw StateError('Repair $repairId not found.');
      final repairClientRaw = repairs.first['client_id'];
      final repairClientId = repairClientRaw is num
          ? repairClientRaw.toInt()
          : int.tryParse('$repairClientRaw');
      if (repairClientId != clientId) {
        throw StateError(
            'Customer credit can only be applied to the same client.');
      }

      final available = await customerCreditForClient(clientId, executor: txn);
      if (available <= 0.005) throw StateError('No available customer credit.');
      final fileValue = (repairs.first['fileValue'] as num?)?.toDouble() ??
          double.tryParse('${repairs.first['fileValue']}') ??
          0.0;
      final paid = await RepairFinancialTruthService.paidForRepair(
        repairId,
        executor: txn,
      );
      final remaining = (fileValue - paid).clamp(0.0, double.infinity);
      if (remaining <= 0.005) {
        throw StateError('Repair is already fully settled.');
      }
      applied = amount;
      if (available < applied) applied = available;
      if (remaining < applied) applied = remaining.toDouble();
      applied = double.parse(applied.toStringAsFixed(2));
      if (applied <= 0.005) throw StateError('Nothing can be allocated.');

      final arAccountId = await _ensureClientAccountOnTxn(txn, clientId);
      final glId = await DBService.postEntryGLOn(
        ex: txn,
        date: DateTime.now(),
        source: 'CREDIT_ALLOCATION',
        sourceId: paymentId,
        note: notes?.trim().isNotEmpty == true
            ? notes!.trim()
            : 'تخصيص رصيد دائن للملف $repairId',
        lines: [
          {
            'account_id': arAccountId,
            'debit': applied,
            'credit': 0.0,
            'party_type': _kPartyClient,
            'party_id': clientId,
            'invoice_id': null,
            'repair_id': null,
          },
          {
            'account_id': arAccountId,
            'debit': 0.0,
            'credit': applied,
            'party_type': _kPartyClient,
            'party_id': clientId,
            'invoice_id': await _findInvoiceIdOnTxn(
              txn: txn,
              repairId: repairId,
            ),
            'repair_id': repairId,
          },
        ],
      );

      final payment = Payment(
        id: paymentId,
        clientId: clientId,
        repairId: repairId,
        relatedRepairId: repairId,
        invoiceId: await _findInvoiceIdOnTxn(txn: txn, repairId: repairId),
        amount: applied,
        date: DateTime.now(),
        method: 'customer_credit',
        accountName: 'رصيد العميل',
        status: _kStatusConfirmed,
        notes: notes ?? 'تخصيص من رصيد العميل الدائن',
        attachments: null,
        glEntryId: glId,
        chequeId: null,
        isIncome: true,
      );
      await txn.insert(
        table,
        payment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(
        'customer_credit_allocations',
        {
          'id': const Uuid().v4(),
          'client_id': clientId,
          'repair_id': repairId,
          'payment_id': paymentId,
          'amount': applied,
          'gl_entry_id': glId,
          'date': payment.date.toIso8601String(),
          'notes': notes,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _refreshRepairSnapshot(txn, repairId);
      await AuditTrailService.log(
        executor: txn,
        actorUserId: p16Actor?.id,
        actorRole: p16Actor?.role,
        action: 'CUSTOMER_CREDIT_ALLOCATED',
        entityType: 'REPAIR',
        entityId: repairId,
        before: {'available_credit': available, 'paid': paid},
        after: {
          'available_credit': available - applied,
          'paid': paid + applied,
          'payment': payment.toMap(),
          'gl_entry_id': glId
        },
        reason: notes,
      );
    });

    try {
      await InvoiceService.I.recomputeForRepair(repairId);
    } catch (_) {}
    return applied;
  }

  static Future<Map<String, Object?>> _receiptSnapshot(
          DatabaseExecutor db, int number) async =>
      {
        'header': await db.query('receipt_headers',
            where: 'receipt_number=?', whereArgs: [number]),
        'payments': await db
            .query(table, where: 'receipt_number=?', whereArgs: [number]),
        'allocations': await db.query('receipt_allocations',
            where: 'receipt_number=?', whereArgs: [number]),
      };

  static Future<void> reverseReceiptByPaymentId(
    String paymentId, {
    String? reason,
  }) async {
    final db = await DBService.database;
    await _ensureTableAndSchema(db);
    final rows = await db.query(
      table,
      columns: const ['receipt_number'],
      where: 'id=?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Payment not found.');
    final raw = rows.first['receipt_number'];
    final receiptNumber = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (receiptNumber == null) {
      await _reverseLegacySinglePayment(paymentId, reason: reason);
      return;
    }
    await reverseReceipt(receiptNumber, reason: reason);
  }

  static Future<void> reverseReceiptByGlEntryId(
    int glEntryId, {
    String? reason,
  }) async {
    final db = await DBService.database;
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'gl_entry_id=?',
      whereArgs: [glEntryId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Payment for GL entry not found.');
    await reverseReceiptByPaymentId(
      rows.first['id'].toString(),
      reason: reason,
    );
  }

  static Future<void> _reverseLegacySinglePayment(
    String paymentId, {
    String? reason,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.receiptReverse);
    final db = await DBService.database;
    final affectedRepairs = <String>{};
    await SyncFoundationService.transaction(db, (txn) async {
      await _ensureTableAndSchema(txn);
      await ReceiptTables.createAllTables(txn);
      final rows = await txn.query(
        table,
        where: 'id=?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final original = Payment.fromMap(rows.first);
      final duplicate = await txn.query(
        table,
        columns: const ['id'],
        where: 'reversal_of_payment_id=?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Payment is already reversed.');
      }
      final nextNo = await _nextReceiptNumberOnTxn(txn);
      final reversal = await _reversePaymentLineOnTxn(
        txn: txn,
        original: original,
        reversalReceiptNumber: nextNo,
        reason: reason,
      );
      await _insertReceiptAllocationOnTxn(
        txn: txn,
        receiptNumber: nextNo,
        payment: reversal,
        allocationType: 'REVERSAL',
      );
      await _insertReceiptHeaderOnTxn(
        txn: txn,
        receiptNumber: nextNo,
        clientId: original.clientId ?? 0,
        date: reversal.date,
        method: original.method,
        totalAmount: reversal.amount,
        allocatedAmount: _pickRepairId(original).isEmpty ? 0 : reversal.amount,
        creditAmount: _pickRepairId(original).isEmpty ? reversal.amount : 0,
        notes: reason ?? 'عكس رسمي لدفعة قديمة',
      );
      final repairId = _pickRepairId(original);
      if (repairId.isNotEmpty) affectedRepairs.add(repairId);
      await AuditTrailService.log(
        executor: txn,
        before: rows.first,
        after: {
          'original':
              (await txn.query(table, where: 'id=?', whereArgs: [paymentId]))
                  .single,
          'reversal': reversal.toMap()
        },
        actorUserId: p16Actor?.id,
        actorRole: p16Actor?.role,
        action: 'LEGACY_PAYMENT_REVERSED',
        entityType: 'PAYMENT',
        entityId: paymentId,
        reason: reason,
      );
    });
    for (final repairId in affectedRepairs) {
      try {
        await InvoiceService.I.recomputeForRepair(repairId);
      } catch (_) {}
    }
  }

  static Future<void> reverseReceipt(
    int receiptNumber, {
    String? reason,
    Database? database,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.receiptReverse);
    final db = database ?? await DBService.database;
    final affectedRepairs = <String>{};
    await SyncFoundationService.transaction(db, (txn) async {
      await _ensureTableAndSchema(txn);
      await ReceiptTables.createAllTables(txn);
      final beforeSnapshot = await _receiptSnapshot(txn, receiptNumber);
      final header = await txn.query(
        'receipt_headers',
        where: 'receipt_number=?',
        whereArgs: [receiptNumber],
        limit: 1,
      );
      if (header.isNotEmpty &&
          (header.first['status'] ?? '').toString().toLowerCase() ==
              'reversed') {
        throw StateError('Receipt is already reversed.');
      }

      final rows = await txn.query(
        table,
        where: 'receipt_number=? AND amount>0 AND COALESCE(isIncome,1)=1',
        whereArgs: [receiptNumber],
        orderBy: 'id',
      );
      if (rows.isEmpty) {
        throw StateError(
          'Receipt RC-${receiptNumber.toString().padLeft(6, '0')} not found.',
        );
      }
      final originals = rows.map(Payment.fromMap).toList();
      for (final original in originals) {
        final duplicate = await txn.query(
          table,
          columns: const ['id'],
          where: 'reversal_of_payment_id=?',
          whereArgs: [original.id],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw StateError('Receipt is already reversed.');
        }
      }

      final reversalReceiptNumber = await _nextReceiptNumberOnTxn(txn);
      var reversalAllocated = 0.0;
      var reversalCredit = 0.0;
      for (final original in originals) {
        final repairId = _pickRepairId(original);
        if (repairId.isNotEmpty) affectedRepairs.add(repairId);
        final reversal = await _reversePaymentLineOnTxn(
          txn: txn,
          original: original,
          reversalReceiptNumber: reversalReceiptNumber,
          reason: reason,
        );
        await _insertReceiptAllocationOnTxn(
          txn: txn,
          receiptNumber: reversalReceiptNumber,
          payment: reversal,
          allocationType: 'REVERSAL',
        );
        if (repairId.isEmpty) {
          reversalCredit += reversal.amount;
        } else {
          reversalAllocated += reversal.amount;
        }
      }

      int? clientId;
      for (final original in originals) {
        if ((original.clientId ?? 0) > 0) {
          clientId = original.clientId;
          break;
        }
      }
      if (clientId == null || clientId <= 0) {
        throw StateError('Receipt has no valid client.');
      }
      await _insertReceiptHeaderOnTxn(
        txn: txn,
        receiptNumber: reversalReceiptNumber,
        clientId: clientId,
        date: DateTime.now(),
        method: originals.first.method,
        totalAmount: reversalAllocated + reversalCredit,
        allocatedAmount: reversalAllocated,
        creditAmount: reversalCredit,
        reversalOfReceiptNumber: receiptNumber,
        notes: reason ??
            'عكس رسمي للسند RC-${receiptNumber.toString().padLeft(6, '0')}',
      );
      if (header.isNotEmpty) {
        await txn.update(
          'receipt_headers',
          {'status': 'reversed'},
          where: 'receipt_number=?',
          whereArgs: [receiptNumber],
        );
      }
      await AuditTrailService.log(
        executor: txn,
        before: beforeSnapshot,
        after: {
          'original': await _receiptSnapshot(txn, receiptNumber),
          'reversal': await _receiptSnapshot(txn, reversalReceiptNumber)
        },
        actorUserId: p16Actor?.id,
        actorRole: p16Actor?.role,
        action: 'RECEIPT_REVERSED',
        entityType: 'RECEIPT',
        entityId: 'RC-${receiptNumber.toString().padLeft(6, '0')}',
        reason: reason,
      );
    });

    for (final repairId in database == null ? affectedRepairs : <String>{}) {
      try {
        await InvoiceService.I.recomputeForRepair(repairId);
      } catch (_) {}
    }
  }

  static Future<Payment> _reversePaymentLineOnTxn({
    required Transaction txn,
    required Payment original,
    required int reversalReceiptNumber,
    String? reason,
  }) async {
    int? reversalGlId;
    if (original.chequeId != null) {
      final chequeRows = await txn.query(
        'cheques',
        where: 'id=?',
        whereArgs: [original.chequeId],
        limit: 1,
      );
      if (chequeRows.isEmpty) throw StateError('Linked cheque not found.');
      final cheque = Cheque.fromMap(chequeRows.first);
      if (cheque.status == ChequeStatus.collected || cheque.isEndorsed == 1) {
        throw StateError(
          'Collected/endorsed cheque must use the cheque return lifecycle before receipt correction.',
        );
      }
      await ChequeAccountingService.transitionStatusOnTxn(
        txn: txn,
        chequeId: original.chequeId!,
        newStatus: ChequeStatus.cancelled,
        reason: reason ?? 'Formal receipt reversal',
      );
      final statusGl = await txn.query(
        'gl_entries',
        columns: const ['id'],
        where: 'source=? AND source_id=?',
        whereArgs: ['CHEQUE_STATUS', '${original.chequeId}:cancelled'],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (statusGl.isNotEmpty) {
        final raw = statusGl.first['id'];
        reversalGlId = raw is num ? raw.toInt() : int.tryParse('$raw');
      }
    } else {
      var glId = original.glEntryId;
      if (glId == null) {
        final glRows = await txn.query(
          'gl_entries',
          columns: const ['id'],
          where: 'source=? AND source_id=?',
          whereArgs: ['PAYMENT', original.id],
          limit: 1,
        );
        if (glRows.isNotEmpty) {
          final raw = glRows.first['id'];
          glId = raw is num ? raw.toInt() : int.tryParse('$raw');
        }
      }
      if (glId == null) {
        throw StateError('Posted GL entry not found for ${original.id}.');
      }
      reversalGlId = await DBService.reverseEntryGLOn(
        txn,
        glId,
        note: reason ?? 'Formal receipt reversal',
      );
    }

    final reversal = Payment(
      id: const Uuid().v4(),
      receiptNumber: reversalReceiptNumber,
      reversalOfPaymentId: original.id,
      clientId: original.clientId,
      repairId: original.repairId,
      invoiceId: original.invoiceId,
      relatedRepairId: original.relatedRepairId,
      amount: -original.amount,
      date: DateTime.now(),
      method: original.method,
      accountName: original.accountName,
      status: 'reversal',
      notes: [
        'عكس رسمي للسند ${original.receiptNumber == null ? original.id : 'RC-${original.receiptNumber!.toString().padLeft(6, '0')}'}',
        if (reason?.trim().isNotEmpty == true) reason!.trim(),
      ].join(' — '),
      attachments: null,
      glEntryId: reversalGlId,
      chequeId: original.chequeId,
      isIncome: true,
    );
    await txn.insert(
      table,
      reversal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await txn.update(
      table,
      {'status': 'reversed'},
      where: 'id=?',
      whereArgs: [original.id],
    );
    final repairId = _pickRepairId(original);
    if (repairId.isNotEmpty) await _refreshRepairSnapshot(txn, repairId);
    return reversal;
  }

  // ───── postPaymentFromDbId (Idempotent) ─────
// يستبدل الدالة كاملة
  static Future<int> postPaymentFromDbId(String paymentId) async {
    final db = await DBService.database;

    final document =
        await db.query(table, where: 'id=?', whereArgs: [paymentId], limit: 1);
    if (document.isEmpty) throw StateError('Payment not found.');
    if (['void', 'reversed', 'reversal']
        .contains('${document.first['status']}'.toLowerCase())) {
      throw StateError('A cancelled payment cannot be posted again.');
    }

    // موجود مسبقًا؟
    final existed = await db.query(
      'gl_entries',
      columns: ['id'],
      where: 'source=? AND source_id=?',
      whereArgs: ['PAYMENT', paymentId],
      limit: 1,
    );
    if (existed.isNotEmpty) {
      final glId = (existed.first['id'] as num).toInt();
      await SyncFoundationService.writeOn(
          db,
          (txn) => txn.update(table, {'gl_entry_id': glId},
              where: 'id=?', whereArgs: [paymentId]));
      return glId;
    }

    String? repairForPost;

    final glId = await SyncFoundationService.transaction(db, (txn) async {
      await _ensureTableAndSchema(txn);

      final row = await txn.query(table,
          where: 'id=?', whereArgs: [paymentId], limit: 1);
      if (row.isEmpty) throw StateError('payment not found: $paymentId');

      final payment = Payment.fromMap(row.first);
      if (payment.amount <= 0) throw StateError('payment amount must be > 0');
      if (!payment.isIncome) {
        throw StateError(
          'PAYMENT GL source is reserved for receipt/income payments.',
        );
      }

      final accountName = (payment.accountName?.trim().isNotEmpty == true)
          ? payment.accountName!.trim()
          : _resolveAccountFromMethod(payment.method);

      final rawRepairId = payment.repairId?.trim().isNotEmpty == true
          ? payment.repairId!.trim()
          : (payment.relatedRepairId ?? '').trim();
      final repairId = rawRepairId.isEmpty ? null : rawRepairId;
      repairForPost = repairId;

      await _ensurePaymentGLAndLinksOnTxn(
        txn: txn,
        paymentId: payment.id,
        payment: payment,
        accountName: accountName,
        customerName: '',
        repairId: repairId,
      );

      final r = await txn.query(
        'gl_entries',
        columns: ['id'],
        where: 'source=? AND source_id=?',
        whereArgs: ['PAYMENT', payment.id],
        limit: 1,
      );
      if (r.isEmpty) throw StateError('GL not created for payment $paymentId');

      final id = (r.first['id'] as num).toInt();
      await txn.update('payments', {'gl_entry_id': id},
          where: 'id=?', whereArgs: [paymentId]);
      return id; // ← يرجّع glId من داخل txn
    });

    // خارج txn
    try {
      if (repairForPost != null && repairForPost!.isNotEmpty) {
        await InvoiceService.I.recomputeForRepair(repairForPost!);
      }
    } catch (_) {}

    return glId;
  }

  // ───── internal on-txn ops ─────

  static Future<void> _reverseIfExists(
      Transaction txn, String paymentId) async {
    final rows = await txn.rawQuery('''
      SELECT e.id FROM gl_entries e
      WHERE e.source IN ('PAYMENT','PAYMENT_OUT','CREDIT_ALLOCATION')
        AND e.source_id=? AND e.reversal_of IS NULL
        AND NOT EXISTS (SELECT 1 FROM gl_entries r WHERE r.reversal_of=e.id)
    ''', [paymentId]);
    for (final row in rows) {
      await DBService.reverseEntryGLOn(txn, (row['id'] as num).toInt(),
          note: 'Payment cancelled');
    }
  }

  static Future<void> _reverseAdjustsIfAny(
      Transaction txn, String paymentId) async {
    final rows = await txn.query(
      'gl_entries',
      columns: ['id'],
      where: 'source=? AND source_id LIKE ?',
      whereArgs: ['PAYMENT-ADJUST', '$paymentId#%'],
    );
    for (final r in rows) {
      final gid = (r['id'] as num).toInt();
      await DBService.reverseEntryGLOn(txn, gid,
          note: 'Reverse on payment adjust/delete');
    }
  }

  static Future<void> _postAdjustOnTxn({
    required Transaction txn,
    required Payment payment,
  }) async {
    final repairId = _pickRepairId(payment);
    if (repairId.isEmpty) return;

    String? invoiceId = payment.invoiceId?.trim();
    if (invoiceId == null || invoiceId.isEmpty) {
      invoiceId = await _findInvoiceIdOnTxn(
        txn: txn,
        repairId: repairId,
      );
    }

    await txn.update(
      table,
      {'invoice_id': invoiceId},
      where: 'id=?',
      whereArgs: [payment.id],
    );

    int? clientId = payment.clientId;
    if ((clientId == null || clientId <= 0) &&
        invoiceId != null &&
        invoiceId.isNotEmpty) {
      final rows = await txn.rawQuery(
        'SELECT client_id FROM invoices WHERE id=? LIMIT 1',
        [invoiceId],
      );
      if (rows.isNotEmpty) {
        final value = rows.first['client_id'];
        if (value is int) {
          clientId = value;
        } else if (value != null) {
          clientId = int.tryParse(value.toString());
        }
      }
    }

    if (clientId == null || clientId <= 0) {
      throw StateError(
        'Cannot post payment adjustment without valid client_id',
      );
    }

    final arSubId = await _ensureClientAccountOnTxn(txn, clientId);

    final accountName = payment.accountName?.trim().isNotEmpty == true
        ? payment.accountName!.trim()
        : _resolveAccountFromMethod(payment.method);

    if (accountName == 'شيكات') {
      throw StateError(
        'Cheque receipt adjustment is blocked until P0.008.',
      );
    }

    final fp = _fingerprint(
      amount: payment.amount,
      dateIso: payment.date.toIso8601String(),
      accountName: accountName,
      clientId: clientId,
      invoiceId: invoiceId ?? '',
      repairId: repairId,
      method: payment.method,
    );

    final debitAccId = accountName == 'البنك'
        ? (await _getAccountIdByCode(txn, GL.bank))!
        : (await _getAccountIdByCode(txn, GL.cash))!;

    final note =
        'تسوية دفعة (Adjust) — ${accountName == "الصندوق" ? "نقدية" : "بنكية"}';

    final glId = await DBService.postEntryGLOn(
      ex: txn,
      date: payment.date,
      ref: invoiceId,
      source: 'PAYMENT-ADJUST',
      sourceId: '${payment.id}#$fp',
      note: note,
      lines: [
        {
          'account_id': debitAccId,
          'debit': payment.amount,
          'credit': 0.0,
          'party_type': null,
          'party_id': null,
          'invoice_id': invoiceId,
          'repair_id': repairId,
        },
        {
          'account_id': arSubId,
          'debit': 0.0,
          'credit': payment.amount,
          'party_type': _kPartyClient,
          'party_id': clientId,
          'invoice_id': invoiceId,
          'repair_id': repairId,
        },
      ],
    );

    await txn.update(
      table,
      {'gl_entry_id': glId},
      where: 'id=?',
      whereArgs: [payment.id],
    );
  }

  static Future<void> _ensurePaymentGLAndLinksOnTxn({
    required Transaction txn,
    required String paymentId,
    required Payment payment,
    required String accountName,
    required String customerName,
    String? repairId,
    String? descriptionOverride,
  }) async {
    final normalizedRepairId =
        repairId?.trim().isNotEmpty == true ? repairId!.trim() : null;

    String? invoiceId = payment.invoiceId?.trim();
    if (invoiceId == null || invoiceId.isEmpty) {
      if (normalizedRepairId != null) {
        invoiceId = await _findInvoiceIdOnTxn(
          txn: txn,
          repairId: normalizedRepairId,
        );
      }
    }

    await txn.update(
      table,
      {'invoice_id': invoiceId},
      where: 'id=?',
      whereArgs: [paymentId],
    );

    int? clientId = payment.clientId;

    if ((clientId == null || clientId <= 0) &&
        invoiceId != null &&
        invoiceId.isNotEmpty) {
      final rows = await txn.rawQuery(
        'SELECT client_id FROM invoices WHERE id=? LIMIT 1',
        [invoiceId],
      );
      if (rows.isNotEmpty) {
        final value = rows.first['client_id'];
        if (value is int) {
          clientId = value;
        } else if (value != null) {
          clientId = int.tryParse(value.toString());
        }
      }
    }

    if (clientId == null || clientId <= 0) {
      throw StateError('Receipt $paymentId requires a valid client_id');
    }

    if ((payment.clientId ?? 0) <= 0) {
      await txn.update(
        table,
        {'client_id': clientId},
        where: 'id=?',
        whereArgs: [paymentId],
      );
    }

    final arSubId = await _ensureClientAccountOnTxn(txn, clientId);

    if (await _glExists(txn, paymentId)) {
      final entries = await txn.query(
        'gl_entries',
        columns: ['id'],
        where: 'source=? AND source_id=?',
        whereArgs: ['PAYMENT', paymentId],
        limit: 1,
      );
      if (entries.isNotEmpty) {
        final raw = entries.first['id'];
        final glId = raw is int ? raw : int.parse(raw.toString());

        if (accountName == 'شيكات') {
          final chequeId = payment.chequeId;
          if (chequeId == null) {
            throw StateError(
              'Posted cheque receipt has no valid cheque link.',
            );
          }
          await ChequeAccountingService.attachInitialGlOnTxn(
            txn: txn,
            chequeId: chequeId,
            glEntryId: glId,
          );
        }

        await txn.update(
          table,
          {'gl_entry_id': glId},
          where: 'id=?',
          whereArgs: [paymentId],
        );
      }
      return;
    }

    final cashId = await _getAccountIdByCode(txn, GL.cash);
    final bankId = await _getAccountIdByCode(txn, GL.bank);

    if (cashId == null || bankId == null) {
      throw StateError('الحسابات الأساسية 1000/1010 غير موجودة');
    }

    int? chequeId;
    int debitAccId;

    if (accountName == 'شيكات') {
      chequeId = payment.chequeId;
      if (chequeId == null) {
        throw StateError('Cheque receipt requires a valid cheque link.');
      }

      final chequeRows = await txn.query(
        'cheques',
        columns: [
          'id',
          'source_type',
          'source_id',
          'receipt_voucher_id',
          'direction',
        ],
        where: 'id=?',
        whereArgs: [chequeId],
        limit: 1,
      );
      if (chequeRows.isEmpty) {
        throw StateError('Cheque receipt points to a missing cheque.');
      }
      final chequeRow = chequeRows.first;
      final sourceType =
          (chequeRow['source_type'] ?? '').toString().toUpperCase();
      final legacyPaymentLink = sourceType == 'PAYMENT' &&
          chequeRow['source_id']?.toString() == paymentId;
      final receiptNumber = payment.receiptNumber;
      final canonicalReceiptLink = receiptNumber != null &&
          (sourceType == 'RECEIPT' ||
              chequeRow['receipt_voucher_id'] != null) &&
          (chequeRow['receipt_voucher_id']?.toString() ==
                  receiptNumber.toString() ||
              chequeRow['source_id']?.toString() == receiptNumber.toString());
      final receivedDirection =
          (chequeRow['direction'] ?? 'RECEIVED').toString().toUpperCase() ==
              'RECEIVED';
      if ((!legacyPaymentLink && !canonicalReceiptLink) || !receivedDirection) {
        throw StateError(
          'Cheque receipt link does not match the receipt document.',
        );
      }

      debitAccId = await _getAccountIdByCode(txn, '1020') ??
          (throw StateError('Missing incoming cheque account 1020'));
    } else {
      debitAccId = accountName == 'البنك' ? bankId : cashId;
    }
    final who = customerName.trim().isNotEmpty ? customerName.trim() : 'العميل';
    final note = descriptionOverride != null &&
            descriptionOverride.trim().isNotEmpty
        ? descriptionOverride.trim()
        : 'دفعة قبض ${accountName == "الصندوق" ? "نقدية" : accountName == "شيكات" ? "بشيك" : "بنكية"} — $who';

    final glId = await DBService.postEntryGLOn(
      ex: txn,
      date: payment.date,
      ref: invoiceId,
      source: 'PAYMENT',
      sourceId: paymentId,
      note: note,
      lines: [
        {
          'account_id': debitAccId,
          'debit': payment.amount,
          'credit': 0.0,
          'party_type': null,
          'party_id': null,
          'invoice_id': invoiceId,
          'repair_id': normalizedRepairId,
          'cheque_id': chequeId,
        },
        {
          'account_id': arSubId,
          'debit': 0.0,
          'credit': payment.amount,
          'party_type': _kPartyClient,
          'party_id': clientId,
          'invoice_id': invoiceId,
          'repair_id': normalizedRepairId,
          'cheque_id': chequeId,
        },
      ],
    );

    if (chequeId != null) {
      await ChequeAccountingService.attachInitialGlOnTxn(
        txn: txn,
        chequeId: chequeId,
        glEntryId: glId,
      );
    }

    await txn.update(
      table,
      {'gl_entry_id': glId},
      where: 'id=?',
      whereArgs: [paymentId],
    );
  }

  static Future<void> _refreshRepairSnapshot(
      Transaction txn, String repairId) async {
    await RepairFinancialTruthService.refreshRepairPaymentCache(txn, repairId);
  }
  // ---------------------------------------------------------------------------
// 🧾 insertAndPostPayment — نظام سند صرف كامل (OUTFLOW)
// - partyType: SUPPLIER / EMPLOYEE / EXPENSE / PURCHASE / OTHER
// - GL Posting:
//      Dr Expense/Supplier/Employee/...
//      Cr Cash/Bank/Cheque
// - No interference with receipt logic
// - Idempotent: يمنع التكرار
// ---------------------------------------------------------------------------

  static Future<Payment> insertAndPostPayment({
    required Payment payment,
    required String method,
    required String
        partyType, // SUPPLIER / EMPLOYEE / EXPENSE / PURCHASE / OTHER
    required String partyName,
    String? descriptionOverride,
  }) async {
    if (payment.amount <= 0) {
      throw ArgumentError("amount must be > 0");
    }

    if (ChequeAccountingService.isChequeMethod(method)) {
      throw StateError(
        'Outgoing cheque payments must use VoucherPaymentService so the '
        'voucher, cheque and GL are created atomically.',
      );
    }

    final db = await DBService.database;

    // توليد ID إذا غير موجود
    final paymentId = payment.id.isEmpty ? const Uuid().v4() : payment.id;

    // تحديد الحساب المستخدم للدفع
    final accountName = (payment.accountName?.trim().isNotEmpty == true)
        ? payment.accountName!.trim()
        : _resolveAccountFromMethod(method);

    final statusStr = payment.status.trim().isEmpty
        ? _kStatusConfirmed
        : payment.status.trim();

    await SyncFoundationService.transaction(db, (txn) async {
      await _ensureTableAndSchema(txn);

      // إدخال السند إذا لم يكن موجودًا
      final exists = await txn.query(
        table,
        columns: ['id'],
        where: 'id=?',
        whereArgs: [paymentId],
        limit: 1,
      );

      if (exists.isEmpty) {
        await txn.insert(
          table,
          payment
              .copyWith(
                id: paymentId,
                status: statusStr,
                accountName: accountName,
              )
              .toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      // منع تكرار GL
      final glRow = await txn.query(
        'gl_entries',
        columns: ['id'],
        where: 'source=? AND source_id=?',
        whereArgs: ['PAYMENT_OUT', paymentId],
        limit: 1,
      );
      if (glRow.isNotEmpty) {
        final glId = (glRow.first['id'] as num).toInt();
        await txn.update(table, {'gl_entry_id': glId},
            where: 'id=?', whereArgs: [paymentId]);
        return;
      }

      //-----------------------------------------------------------------------
      // تجهيز partyId الصحيح (INT)
      //-----------------------------------------------------------------------
      final int? pid = payment.clientId;

      //-----------------------------------------------------------------------
      // حساب الطرف (مدين)
      //-----------------------------------------------------------------------
      int debitAccId;

      if (partyType == "SUPPLIER" || partyType == "PURCHASE") {
        if (pid == null) throw StateError("Invalid supplier id");

        final rows = await txn.query(
          'suppliers',
          columns: ['id', 'name'],
          where: 'id=?',
          whereArgs: [pid],
          limit: 1,
        );

        if (rows.isEmpty) throw StateError("Supplier not found");

        // P0.005 — suppliers table is normalized to (id, name).
        final code = "2200.S${pid.toString().padLeft(4, '0')}";
        final accounts = await txn.query(
          'accounts',
          columns: ['id'],
          where: 'code=?',
          whereArgs: [code],
          limit: 1,
        );

        if (accounts.isNotEmpty) {
          final value = accounts.first['id'];
          debitAccId = value is int ? value : int.parse(value.toString());
        } else {
          debitAccId = await txn.insert('accounts', {
            'code': code,
            'name': rows.first['name']?.toString() ?? 'مورد $pid',
            'type': 'LIABILITY',
            'normal_balance': 'CREDIT',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      } else if (partyType == "EMPLOYEE") {
        debitAccId = await txn.insert('accounts', {
          'code': '5000.E$pid',
          'name': 'راتب موظف: $partyName',
          'type': 'EXPENSE',
          'normal_balance': 'DEBIT',
        });
      } else if (partyType == "EXPENSE") {
        final rows = await txn.query(
          'expense_categories',
          columns: ['account_id', 'name'],
          where: 'id=?',
          whereArgs: [pid],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError("Expense not found");

        final acc = rows.first['account_id'];
        if (acc == null) {
          debitAccId = await txn.insert('accounts', {
            'code': '5000.X$pid',
            'name': 'مصروف: ${rows.first['name']}',
            'type': 'EXPENSE',
            'normal_balance': 'DEBIT',
          });

          await txn.update('expense_categories', {'account_id': debitAccId},
              where: 'id=?', whereArgs: [pid]);
        } else {
          debitAccId = acc is int ? acc : int.parse(acc.toString());
        }
      } else {
        // OTHER
        debitAccId = await txn.insert('accounts', {
          'code': '5000.O$pid',
          'name': 'مصروف طرف: $partyName',
          'type': 'EXPENSE',
          'normal_balance': 'DEBIT',
        });
      }

      //-----------------------------------------------------------------------
      // حساب الصندوق/البنك (دائن)
      //-----------------------------------------------------------------------
      final cashAccId = await _getAccountIdByCode(txn, GL.cash);
      final bankAccId = await _getAccountIdByCode(txn, GL.bank);

      if (cashAccId == null || bankAccId == null) {
        throw StateError("Missing main accounts 1000/1010");
      }

      late int creditAccId;

      if (accountName == "البنك") {
        creditAccId = bankAccId;
      } else if (accountName == "شيكات") {
        throw StateError(
          'Outgoing cheque accounting must use VoucherPaymentService.',
        );
      } else {
        creditAccId = cashAccId;
      }

      //-----------------------------------------------------------------------
      // GL Posting
      //-----------------------------------------------------------------------
      final note = descriptionOverride ??
          'سند صرف — ${accountName == "الصندوق" ? "نقدي" : "بنكي"} — $partyName';

      final glId = await DBService.postEntryGLOn(
        ex: txn,
        date: payment.date,
        ref: null,
        source: "PAYMENT_OUT",
        sourceId: paymentId,
        note: note,
        lines: [
          {
            'account_id': debitAccId,
            'debit': payment.amount,
            'credit': 0.0,
            'party_type': partyType,
            'party_id': pid,
            'invoice_id': null,
            'repair_id': null,
          },
          {
            'account_id': creditAccId,
            'debit': 0.0,
            'credit': payment.amount,
            'party_type': null,
            'party_id': null,
            'invoice_id': null,
            'repair_id': null,
          }
        ],
      );

      await txn.update(table, {'gl_entry_id': glId},
          where: 'id=?', whereArgs: [paymentId]);
    });

    return payment.copyWith(id: paymentId);
  }

  // ---------------------------------------------------------------------------
  // DELETE ALL PAYMENTS OF A CHEQUE — BY cheque.uuid
  // ---------------------------------------------------------------------------
  static Future<void> deletePaymentsByChequeUUID(String chequeUUID) async {
    final db = await DBService.database;

    // جميع الدفعات التي تحتوي على نفس uuid
    final rows = await db.query(
      'payments',
      where: 'notes LIKE ? OR relatedRepairId = ?',
      whereArgs: ['%$chequeUUID%', chequeUUID],
    );

    for (final r in rows) {
      final id = r['id']?.toString();
      if (id == null || id.isEmpty) continue;

      await delete(id); // سيقوم بحذف + reverse GL
    }
  }
}
