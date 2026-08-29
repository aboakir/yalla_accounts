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

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

class PaymentService {
  static const String table = 'payments';

  static const _ACC_CASH_CODE = '1000'; // الصندوق
  static const _ACC_BANK_CODE = '1010'; // البنك
  static const _ACC_AR_CODE = '1200'; // ذمم العملاء

  static const _K_STATUS_CONFIRMED = 'confirmed';
  static const _K_PARTY_CLIENT = 'CLIENT';

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
    await exec.execute('''
CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
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
    final r = await db.query(
      'gl_entries',
      columns: ['id'],
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
    await db.transaction((txn) async {
      await _ensureTableAndSchema(txn);
      final map = payment.toMap();
      map['id'] ??= const Uuid().v4();
      final statusStr = '${map['status'] ?? ''}'.trim();
      map['status'] = statusStr.isEmpty ? _K_STATUS_CONFIRMED : statusStr;
      await txn.insert(table, map, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  static Future<int> update(Payment payment) async {
    final db = await DBService.database;
    String? repairForPost;
    final updated = await db.transaction((txn) async {
      await _ensureTableAndSchema(txn);

      final prevRows = await txn.query(table,
          where: 'id=?', whereArgs: [payment.id], limit: 1);
      if (prevRows.isEmpty) {
        // لا يوجد سجل سابق → أدخل كجديد ثم GL
        final map = payment.toMap();
        map['id'] ??= const Uuid().v4();
        final statusStr = '${map['status'] ?? ''}'.trim();
        map['status'] = statusStr.isEmpty ? _K_STATUS_CONFIRMED : statusStr;
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
      map['status'] = statusStr.isEmpty ? _K_STATUS_CONFIRMED : statusStr;
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

  static Future<int> delete(String id) async {
    final db = await DBService.database;
    String? repairForPost;
    final count = await db.transaction((txn) async {
      await _ensureTableAndSchema(txn);
      final rows =
          await txn.query(table, where: 'id=?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return 0;
      final p = Payment.fromMap(rows.first);
      repairForPost = _pickRepairId(p);

      if (await _glExists(txn, id)) {
        throw StateError(
          'Posted receipt $id cannot be deleted. '
          'Use a formal reversal/correcting receipt workflow.',
        );
      }

      await _reverseIfExists(txn, id);
      await _reverseAdjustsIfAny(txn, id);
      final c = await txn.delete(table, where: 'id = ?', whereArgs: [id]);

      if (repairForPost != null && repairForPost!.isNotEmpty) {
        await _refreshRepairSnapshot(txn, repairForPost!);
      }
      return c;
    });

    try {
      if (repairForPost != null && repairForPost!.isNotEmpty) {
        await InvoiceService.I.recomputeForRepair(repairForPost!);
      }
    } catch (_) {}
    return count;
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

  // ───────── Receipt + GL (لا معاملات متداخلة) ─────────
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

    final db = await DBService.database;
    String? repairForPost;

    await db.transaction((txn) async {
      await _ensureTableAndSchema(txn);

      final rawRepairId = payment.repairId?.trim().isNotEmpty == true
          ? payment.repairId!.trim()
          : (payment.relatedRepairId ?? '').trim();
      final repairId = rawRepairId.isEmpty ? null : rawRepairId;
      repairForPost = repairId;

      final accountName = (payment.accountName?.trim().isNotEmpty == true)
          ? payment.accountName!.trim()
          : _resolveAccountFromMethod(method);

      final status = payment.status.trim().isEmpty
          ? _K_STATUS_CONFIRMED
          : payment.status.trim();
      final paymentId = payment.id.isEmpty ? const Uuid().v4() : payment.id;

      final existing = await txn.query(
        table,
        where: 'id=?',
        whereArgs: [paymentId],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        var persisted = Payment.fromMap(existing.first);

        final sameMaterialDocument =
            (persisted.amount - payment.amount).abs() <= 0.01 &&
                persisted.method.trim().toLowerCase() ==
                    payment.method.trim().toLowerCase() &&
                (persisted.clientId ?? 0) == (payment.clientId ?? 0) &&
                _pickRepairId(persisted) == _pickRepairId(payment);

        if (!sameMaterialDocument) {
          throw StateError(
            'Receipt $paymentId already exists with different material fields.',
          );
        }

        if (ChequeAccountingService.isChequeMethod(method) &&
            persisted.chequeId == null) {
          if (chequeDraft == null) {
            throw StateError(
              'Cheque receipt exists without a cheque link. '
              'Provide cheque details before retrying.',
            );
          }

          final chequeId =
              await ChequeAccountingService.createLinkedChequeOnTxn(
            txn: txn,
            draft: chequeDraft,
            type: ChequeType.incoming,
            amount: persisted.amount,
            currency:
                (await CommercialSettingsService.instance.get(executor: txn))
                    .baseCurrencyCode,
            sourceType: 'PAYMENT',
            sourceId: paymentId,
            clientId: persisted.clientId,
            recipientType: 'WORKSHOP',
            recipientName: 'Workshop',
          );

          await txn.update(
            table,
            {'cheque_id': chequeId},
            where: 'id=?',
            whereArgs: [paymentId],
          );
          persisted = persisted.copyWith(chequeId: chequeId);
        }

        await _ensurePaymentGLAndLinksOnTxn(
          txn: txn,
          paymentId: paymentId,
          payment: persisted,
          accountName: (persisted.accountName?.trim().isNotEmpty == true)
              ? persisted.accountName!.trim()
              : accountName,
          customerName: customerName,
          repairId: repairId,
          descriptionOverride: descriptionOverride,
        );

        if (repairId != null) {
          await _refreshRepairSnapshot(txn, repairId);
        }
        return;
      }

      var storedPayment = payment.copyWith(
        id: paymentId,
        accountName: accountName,
        status: status,
        relatedRepairId: repairId,
      );

      if (ChequeAccountingService.isChequeMethod(method)) {
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
          clientId: storedPayment.clientId,
          recipientType: 'WORKSHOP',
          recipientName: 'Workshop',
        );

        storedPayment = storedPayment.copyWith(chequeId: chequeId);
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

      if (repairId != null) {
        await _refreshRepairSnapshot(txn, repairId);
      }
    });

    if (updateInvoice && repairForPost != null && repairForPost!.isNotEmpty) {
      try {
        await InvoiceService.I.recomputeForRepair(repairForPost!);
      } catch (_) {}
    }
  }

  // ───── postPaymentFromDbId (Idempotent) ─────
// يستبدل الدالة كاملة
  static Future<int> postPaymentFromDbId(String paymentId) async {
    final db = await DBService.database;

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
      await db.update(table, {'gl_entry_id': glId},
          where: 'id=?', whereArgs: [paymentId]);
      return glId;
    }

    String? repairForPost;

    final glId = await db.transaction((txn) async {
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
    final r = await txn.query(
      'gl_entries',
      columns: ['id'],
      where: 'source=? AND source_id=?',
      whereArgs: ['PAYMENT', paymentId],
      limit: 1,
    );
    if (r.isEmpty) return;
    final glId = (r.first['id'] as num).toInt();
    await DBService.reverseEntryGLOn(txn, glId,
        note: 'Reverse on payment edit/delete');
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
        ? (await _getAccountIdByCode(txn, _ACC_BANK_CODE))!
        : (await _getAccountIdByCode(txn, _ACC_CASH_CODE))!;

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
          'party_type': _K_PARTY_CLIENT,
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

    final cashId = await _getAccountIdByCode(txn, _ACC_CASH_CODE);
    final bankId = await _getAccountIdByCode(txn, _ACC_BANK_CODE);

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
        columns: ['id', 'source_type', 'source_id'],
        where: 'id=?',
        whereArgs: [chequeId],
        limit: 1,
      );
      if (chequeRows.isEmpty ||
          (chequeRows.first['source_type'] ?? '').toString().toUpperCase() !=
              'PAYMENT' ||
          (chequeRows.first['source_id'] ?? '').toString() != paymentId) {
        throw StateError(
          'Cheque receipt link does not match the PAYMENT document.',
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
          'party_type': _K_PARTY_CLIENT,
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
    // جمع كل المدفوعات المرتبطة بالملف
    final sumRows = await txn.rawQuery(
      'SELECT IFNULL(SUM(amount),0) s FROM $table WHERE repair_id=? OR relatedRepairId=?',
      [repairId, repairId],
    );
    final paidSumRaw = sumRows.first['s'];
    final paidSum = paidSumRaw is num
        ? paidSumRaw.toDouble()
        : double.tryParse('$paidSumRaw') ?? 0.0;

    // قراءة قيمة الملف الأصلية (fileValue)
    double fileValue = 0.0;
    final r = await txn.rawQuery(
        'SELECT IFNULL(fileValue,0) f FROM repairs WHERE id=? LIMIT 1',
        [repairId]);
    if (r.isNotEmpty) {
      final f = r.first['f'];
      fileValue = f is num ? f.toDouble() : double.tryParse('$f') ?? 0.0;
    }

    // تحديد حالة السداد
    final newStatus = paidSum >= fileValue
        ? 'مسدد'
        : (paidSum > 0 ? 'مسدد جزئي' : 'غير مسدد');

    // تحديث الأعمدة الصحيحة
    await txn.update(
      'repairs',
      {
        'total_paid_amount': paidSum,
        'paymentStatus': newStatus,
        'isArchived': paidSum >= fileValue ? 1 : 0,
      },
      where: 'id=?',
      whereArgs: [repairId],
    );
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
        ? _K_STATUS_CONFIRMED
        : payment.status.trim();

    await db.transaction((txn) async {
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
      final cashAccId = await _getAccountIdByCode(txn, _ACC_CASH_CODE);
      final bankAccId = await _getAccountIdByCode(txn, _ACC_BANK_CODE);

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
