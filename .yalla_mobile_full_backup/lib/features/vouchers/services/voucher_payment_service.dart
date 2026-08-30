// -----------------------------------------------------------------------------
// 📁 lib/features/vouchers/services/voucher_payment_service.dart
// Voucher Payment Service — v54 (AUTO FIFO SETTLEMENT)
// -----------------------------------------------------------------------------
// ✓ ترقيم تلقائي R-0001 / P-0001
// ✓ GL هو المصدر المحاسبي الوحيد
// ✓ الدفع على المورد (AP) دائمًا
// ✓ الربط الذكي بالفواتير: تسوية FIFO تلقائية (اختياري عبر reference)
// ✓ لا يعدّل purchase_invoices (paid_total/status/remaining) إطلاقًا
// ✓ بدون جداول إضافية غير: invoice_settlements (جدول ربط فقط)
// -----------------------------------------------------------------------------

import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/services/db_service.dart';
import '../../../core/services/document_number_service.dart';
import '../../cheques/models/cheque.dart';
import '../../cheques/services/cheque_accounting_service.dart';
import '../models/voucher_payment_model.dart';

class VoucherPaymentService {
  static const String table = "vouchers";

  // ---------------------------------------------------------------------------
  // SCHEMA
  // ---------------------------------------------------------------------------
  static Future<void> ensureSchema(DatabaseExecutor db) async {
    // === vouchers ===
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vouchers (
        id TEXT PRIMARY KEY,

        voucher_type TEXT NOT NULL,
        voucher_number TEXT,
        voucher_code TEXT,

        party_type TEXT,
        party_id TEXT,

        amount REAL NOT NULL,
        currency TEXT DEFAULT 'ILS',
        date TEXT NOT NULL,

        method TEXT NOT NULL,
        cheque_id TEXT,

        reference TEXT,
        source TEXT,
        source_id TEXT,

        gl_entry_id INTEGER,
        is_posted INTEGER NOT NULL DEFAULT 0,
        posted_by TEXT,
        posted_at TEXT,

        notes TEXT,
        attachments TEXT,

        created_at TEXT,
        updated_at TEXT
      );
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vouchers_date ON vouchers(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vouchers_party ON vouchers(party_id)');

    // === invoice_settlements (ربط فقط) ===
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_settlements (
        id TEXT PRIMARY KEY,
        supplier_id INTEGER NOT NULL,
        invoice_id TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        amount_applied REAL NOT NULL,
        created_at TEXT
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_settlements_supplier
      ON invoice_settlements(supplier_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_settlements_invoice
      ON invoice_settlements(invoice_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_settlements_voucher
      ON invoice_settlements(voucher_id);
    ''');

    // P0.007 — settlement side effects must also be idempotent.
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_settlements_voucher_invoice
      ON invoice_settlements(voucher_id, invoice_id);
    ''');
  }

  // ---------------------------------------------------------------------------
  // توليد رقم السند الجديد (R-0001 / P-0001)
  // ---------------------------------------------------------------------------
  static Future<String> _generateVoucherNumber(
      Transaction txn, String voucherType) async {
    final type = voucherType.toUpperCase() == 'RECEIPT'
        ? 'RECEIPT_VOUCHER'
        : 'PAYMENT_VOUCHER';
    return DocumentNumberService.nextOn(txn, documentType: type);
  }

  // ---------------------------------------------------------------------------
  // INSERT + POST GL + (AUTO SETTLEMENT FIFO)
  // ---------------------------------------------------------------------------
  static Future<VoucherPayment> insertAndPost({
    required VoucherPayment voucher,
    required String partyName,
    Map<String, dynamic>? chequeDraft,
  }) async {
    if (voucher.amount <= 0) throw ArgumentError('Amount must be > 0');

    final db = await DBService.database;
    final id = voucher.id.isEmpty ? const Uuid().v4() : voucher.id;

    await db.transaction((txn) async {
      await ensureSchema(txn);

      final existingRows = await txn.query(
        table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      late VoucherPayment postingVoucher;
      late String voucherNumber;

      if (existingRows.isEmpty) {
        voucherNumber = await _generateVoucherNumber(
          txn,
          voucher.voucherType.toUpperCase(),
        );

        postingVoucher = voucher.copyWith(
          id: id,
          voucherNumber: voucherNumber,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );

        if (ChequeAccountingService.isChequeMethod(postingVoucher.method)) {
          if (chequeDraft == null) {
            throw StateError(
              'Cheque payment voucher requires cheque details.',
            );
          }

          final chequeId =
              await ChequeAccountingService.createLinkedChequeOnTxn(
            txn: txn,
            draft: chequeDraft,
            type: ChequeType.outgoing,
            amount: postingVoucher.amount,
            currency: postingVoucher.currency,
            sourceType: 'VOUCHER',
            sourceId: id,
            supplierPid: postingVoucher.partyType?.toUpperCase() == 'SUPPLIER'
                ? postingVoucher.partyId
                : null,
            recipientType: postingVoucher.partyType,
            recipientId: postingVoucher.partyId,
            recipientName: partyName,
          );

          postingVoucher = postingVoucher.copyWith(
            chequeId: chequeId.toString(),
          );
        }

        await txn.insert(
          table,
          postingVoucher.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        postingVoucher = VoucherPayment.fromMap(existingRows.first);
        voucherNumber = postingVoucher.voucherNumber ?? '';

        bool sameText(String? a, String? b) =>
            (a ?? '').trim() == (b ?? '').trim();

        final sameMaterialDocument = postingVoucher.voucherType.toUpperCase() ==
                voucher.voucherType.toUpperCase() &&
            postingVoucher.partyType?.toUpperCase() ==
                voucher.partyType?.toUpperCase() &&
            sameText(postingVoucher.partyId, voucher.partyId) &&
            (postingVoucher.amount - voucher.amount).abs() <= 0.01 &&
            postingVoucher.currency.toUpperCase() ==
                voucher.currency.toUpperCase() &&
            postingVoucher.date.toIso8601String() ==
                voucher.date.toIso8601String() &&
            postingVoucher.method.toUpperCase() ==
                voucher.method.toUpperCase() &&
            sameText(postingVoucher.reference, voucher.reference) &&
            sameText(postingVoucher.source, voucher.source) &&
            sameText(postingVoucher.sourceId, voucher.sourceId);

        if (!sameMaterialDocument) {
          throw StateError(
            'Voucher $id already exists with different material fields. '
            'Posted vouchers are immutable; create a correcting document.',
          );
        }

        if (ChequeAccountingService.isChequeMethod(postingVoucher.method) &&
            (postingVoucher.chequeId == null ||
                postingVoucher.chequeId!.trim().isEmpty)) {
          if (chequeDraft == null) {
            throw StateError(
              'Cheque voucher exists without a cheque link. '
              'Provide cheque details before retrying.',
            );
          }

          final chequeId =
              await ChequeAccountingService.createLinkedChequeOnTxn(
            txn: txn,
            draft: chequeDraft,
            type: ChequeType.outgoing,
            amount: postingVoucher.amount,
            currency: postingVoucher.currency,
            sourceType: 'VOUCHER',
            sourceId: id,
            supplierPid: postingVoucher.partyType?.toUpperCase() == 'SUPPLIER'
                ? postingVoucher.partyId
                : null,
            recipientType: postingVoucher.partyType,
            recipientId: postingVoucher.partyId,
            recipientName: partyName,
          );

          await txn.update(
            table,
            {'cheque_id': chequeId.toString()},
            where: 'id=?',
            whereArgs: [id],
          );
          postingVoucher = postingVoucher.copyWith(
            chequeId: chequeId.toString(),
          );
        }
      }

      final glRowsBefore = await txn.query(
        'gl_entries',
        columns: ['id'],
        where: 'source = ? AND source_id = ?',
        whereArgs: ['VOUCHER', id],
        limit: 1,
      );

      if (glRowsBefore.isNotEmpty) {
        final raw = glRowsBefore.first['id'];
        final glId = raw is int ? raw : int.parse(raw.toString());

        if (ChequeAccountingService.isChequeMethod(postingVoucher.method)) {
          final chequeId = int.tryParse(postingVoucher.chequeId ?? '');
          if (chequeId == null) {
            throw StateError('Posted cheque voucher has no valid cheque link.');
          }
          final chequeRows = await txn.query(
            'cheques',
            columns: ['id'],
            where: 'id=?',
            whereArgs: [chequeId],
            limit: 1,
          );
          if (chequeRows.isEmpty) {
            throw StateError(
                'Posted cheque voucher points to a missing cheque.');
          }
          await ChequeAccountingService.attachInitialGlOnTxn(
            txn: txn,
            chequeId: chequeId,
            glEntryId: glId,
          );
        }

        await txn.update(
          table,
          {
            'gl_entry_id': glId,
            'is_posted': 1,
            'posted_at':
                postingVoucher.postedAt ?? DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        // Retry of an already-posted voucher stops here.
        // Do not repeat logs or supplier invoice settlement side effects.
        return;
      }

      final method = postingVoucher.method.trim().toUpperCase();

      final cashAcc = await _getAccountIdByCode(txn, '1000') ??
          (throw StateError('Missing ACC 1000'));
      final bankAcc = await _getAccountIdByCode(txn, '1010') ??
          (throw StateError('Missing ACC 1010'));

      late int creditAccId;
      if (method == 'BANK' || method == 'TRANSFER') {
        creditAccId = bankAcc;
      } else if (method == 'CHEQUE') {
        creditAccId = await _getAccountIdByCode(txn, '1030') ??
            (throw StateError('Missing outgoing cheque account 1030'));
      } else {
        creditAccId = cashAcc;
      }

      final debitAccId = await _resolveDebitAccount(
        txn: txn,
        voucher: postingVoucher,
        partyName: partyName,
      );

      final glId = await DBService.postEntryGLOn(
        ex: txn,
        date: postingVoucher.date,
        ref: postingVoucher.reference,
        source: 'VOUCHER',
        sourceId: id,
        sourceNumber: voucherNumber,
        note: 'سند دفع — ${postingVoucher.method} — $partyName',
        lines: [
          {
            'account_id': debitAccId,
            'debit': postingVoucher.amount,
            'credit': 0.0,
            'party_type': postingVoucher.partyType,
            'party_id': postingVoucher.partyId,
            'invoice_id': postingVoucher.reference,
            'repair_id': null,
            'cheque_id': int.tryParse(postingVoucher.chequeId ?? ''),
          },
          {
            'account_id': creditAccId,
            'debit': 0.0,
            'credit': postingVoucher.amount,
            'party_type': null,
            'party_id': null,
            'invoice_id': postingVoucher.reference,
            'repair_id': null,
            'cheque_id': int.tryParse(postingVoucher.chequeId ?? ''),
          },
        ],
      );

      if (method == 'CHEQUE') {
        final chequeId = int.tryParse(postingVoucher.chequeId ?? '');
        if (chequeId == null) {
          throw StateError(
              'Cheque voucher lost its cheque link before posting.');
        }
        await ChequeAccountingService.attachInitialGlOnTxn(
          txn: txn,
          chequeId: chequeId,
          glEntryId: glId,
        );
      }

      await txn.update(
        table,
        {
          'gl_entry_id': glId,
          'is_posted': 1,
          'posted_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await _applyNonSupplierPaymentLogs(
        txn,
        postingVoucher.copyWith(
          glEntryId: glId,
          voucherNumber: voucherNumber,
        ),
      );

      if (postingVoucher.partyType?.toUpperCase() == 'SUPPLIER' &&
          postingVoucher.reference != null &&
          postingVoucher.reference!.trim().isNotEmpty) {
        await _autoSettleSupplierInvoicesFIFO(
          txn: txn,
          voucherId: id,
          supplierId: int.tryParse(postingVoucher.partyId ?? ''),
          amount: postingVoucher.amount,
          preferredInvoiceId: postingVoucher.reference!.trim(),
        );
      }
    });

    final postedRow = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (postedRow.isEmpty) {
      throw StateError('Voucher $id disappeared after posting');
    }

    return VoucherPayment.fromMap(postedRow.first);
  }

  // =============================================================================
  // LOGS (غير المورد) — يبقى كما هو
  // =============================================================================
  static Future<void> _applyNonSupplierPaymentLogs(
      Transaction txn, VoucherPayment voucher) async {
    final type = voucher.partyType?.toUpperCase();

    if (type == "EMPLOYEE") {
      await txn.insert("payments", {
        "id": const Uuid().v4(),
        "invoice_id": null,
        "amount": voucher.amount,
        "date": voucher.date.toIso8601String(),
        "method": voucher.method.toLowerCase(),
        "status": "posted",
        "notes": voucher.notes,
        "gl_entry_id": voucher.glEntryId,
        "cheque_id": int.tryParse(voucher.chequeId ?? ''),
        "isIncome": 0,
        "party_id": voucher.partyId,
      });
      return;
    }

    if (type == "EXPENSE") {
      await txn.insert("payments", {
        "id": const Uuid().v4(),
        "invoice_id": null,
        "amount": voucher.amount,
        "date": voucher.date.toIso8601String(),
        "method": voucher.method.toLowerCase(),
        "status": "posted",
        "notes": voucher.notes,
        "gl_entry_id": voucher.glEntryId,
        "cheque_id": int.tryParse(voucher.chequeId ?? ''),
        "isIncome": 0,
        "party_id": voucher.partyId,
      });
      return;
    }
  }

  // =============================================================================
  // AUTO SETTLEMENT FIFO (SUPPLIER)
  // =============================================================================
  static Future<void> _autoSettleSupplierInvoicesFIFO({
    required Transaction txn,
    required String voucherId,
    required int? supplierId,
    required double amount,
    String? preferredInvoiceId,
  }) async {
    if (supplierId == null || amount <= 0) return;

    if (preferredInvoiceId != null && preferredInvoiceId.trim().isNotEmpty) {
      await _applyToSingleInvoiceIfOutstanding(
        txn: txn,
        supplierId: supplierId,
        voucherId: voucherId,
        invoiceId: preferredInvoiceId.trim(),
        amountToApply: amount,
      );

      // A selected reference is explicit. Never spill the remainder
      // to unrelated purchase invoices.
      return;
    }

    // Payment on supplier account: AP GL is sufficient.
    // No invoice settlement side effect is created without an explicit invoice.
  }

  static Future<double> _applyToSingleInvoiceIfOutstanding({
    required Transaction txn,
    required int supplierId,
    required String voucherId,
    required String invoiceId,
    required double amountToApply,
  }) async {
    if (amountToApply <= 0 || invoiceId.trim().isEmpty) return 0.0;

    final invRows = await txn.rawQuery('''
      SELECT id, supplier_id, amount_total
      FROM purchase_invoices
      WHERE id = ? AND supplier_id = ?
      LIMIT 1
    ''', [invoiceId, supplierId]);

    if (invRows.isEmpty) {
      throw StateError(
        'Purchase invoice $invoiceId does not belong to supplier $supplierId',
      );
    }

    final total = (invRows.first['amount_total'] as num?)?.toDouble() ?? 0.0;
    if (total <= 0) {
      throw StateError('Purchase invoice $invoiceId has non-positive total');
    }

    final settledRow = await txn.rawQuery('''
      SELECT COALESCE(SUM(amount_applied), 0) AS s
      FROM invoice_settlements
      WHERE invoice_id = ?
    ''', [invoiceId]);

    final settled = (settledRow.first['s'] as num?)?.toDouble() ?? 0.0;
    final outstanding = total - settled;
    if (outstanding <= 0) return 0.0;

    final applyNow = amountToApply <= outstanding ? amountToApply : outstanding;

    await txn.insert(
      'invoice_settlements',
      {
        'id': const Uuid().v4(),
        'supplier_id': supplierId,
        'invoice_id': invoiceId,
        'voucher_id': voucherId,
        'amount_applied': applyNow,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return applyNow;
  }

  // ---------------------------------------------------------------------------
  // DEBIT ACCOUNT LOGIC
  // ---------------------------------------------------------------------------
  static Future<int> _resolveDebitAccount({
    required Transaction txn,
    required VoucherPayment voucher,
    required String partyName,
  }) async {
    final type = voucher.partyType?.toUpperCase();

    if (type == "SUPPLIER" || type == "PURCHASE") {
      final id = int.tryParse(voucher.partyId ?? '');
      if (id == null) throw StateError("Invalid supplier id");

      final supplierRows = await txn.query(
        "suppliers",
        columns: ["id", "name"],
        where: "id = ?",
        whereArgs: [id],
        limit: 1,
      );

      if (supplierRows.isEmpty) {
        throw StateError("Supplier not found: $id");
      }

      // P0.005 — one supplier = one canonical AP account.
      final code = "2200.S${id.toString().padLeft(4, '0')}";
      final supplierName = supplierRows.first["name"]?.toString() ?? partyName;

      final existing = await txn.query(
        "accounts",
        columns: ["id"],
        where: "code = ?",
        whereArgs: [code],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final value = existing.first["id"];
        return value is int ? value : int.parse(value.toString());
      }

      return await txn.insert("accounts", {
        "code": code,
        "name": supplierName,
        "type": "LIABILITY",
        "normal_balance": "CREDIT",
        "created_at": DateTime.now().toIso8601String(),
      });
    }

    if (type == "EMPLOYEE") {
      final empId = voucher.partyId ?? "";
      final code = "1120.E$empId";

      final existing = await txn.query(
        "accounts",
        columns: ["id"],
        where: "code = ?",
        whereArgs: [code],
        limit: 1,
      );
      if (existing.isNotEmpty) return existing.first["id"] as int;

      return await txn.insert("accounts", {
        "code": code,
        "name": "سلفة موظف: $partyName",
        "type": "ASSET",
        "normal_balance": "DEBIT",
      });
    }

    if (type == "EXPENSE") {
      return _ensureOperatingExpenseAccount(txn);
    }

    final x = voucher.partyId ?? '';
    return await txn.insert("accounts", {
      "code": "5000.O$x",
      "name": "مصروف طرف: $partyName",
      "type": "EXPENSE",
      "normal_balance": "DEBIT",
    });
  }

  static Future<int> _ensureOperatingExpenseAccount(
      DatabaseExecutor txn) async {
    const code = "5000.OP";

    final r = await txn.query(
      "accounts",
      columns: ["id"],
      where: "code = ?",
      whereArgs: [code],
      limit: 1,
    );
    if (r.isNotEmpty) return r.first["id"] as int;

    return await txn.insert("accounts", {
      'code': code,
      'name': "مصاريف تشغيلية",
      'type': "EXPENSE",
      'normal_balance': "DEBIT",
    });
  }

  static Future<int?> _getAccountIdByCode(
      DatabaseExecutor txn, String code) async {
    final r = await txn.query(
      "accounts",
      columns: ["id"],
      where: "code = ?",
      whereArgs: [code],
      limit: 1,
    );
    if (r.isEmpty) return null;
    final v = r.first["id"];
    return v is int ? v : int.tryParse("$v");
  }
}
