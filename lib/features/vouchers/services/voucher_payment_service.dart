import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import '../../finance/purchases/services/purchase_balance_sql.dart';
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
import '../../auth/services/audit_trail_service.dart';
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

    await _ensureVoucherColumn(db, 'source', 'TEXT');
    await _ensureVoucherColumn(db, 'source_id', 'TEXT');
    await _ensureVoucherColumn(db, 'status', "TEXT NOT NULL DEFAULT 'DRAFT'");
    await _ensureVoucherColumn(db, 'reversal_gl_entry_id', 'INTEGER');
    await _ensureVoucherColumn(db, 'reversed_at', 'TEXT');
    await _ensureVoucherColumn(db, 'reversal_reason', 'TEXT');

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
    Database? database,
  }) async {
    if (!voucher.amount.isFinite || voucher.amount <= 0) {
      throw ArgumentError('Amount must be > 0');
    }

    final db = database ?? await DBService.database;
    final id = voucher.id.isEmpty ? const Uuid().v4() : voucher.id;

    await SyncFoundationService.transaction(db, (txn) async {
      await ensureSchema(txn);
      await _validateVoucherOnTxn(
        txn: txn,
        voucher: voucher,
      );

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
        if (['VOID', 'REVERSED']
            .contains('${existingRows.first['status']}'.toUpperCase())) {
          throw StateError('Cancelled voucher cannot be reposted');
        }
        postingVoucher = VoucherPayment.fromMap(existingRows.first);
        voucherNumber = postingVoucher.voucherNumber ?? '';

        bool sameText(String? a, String? b) =>
            (a ?? '').trim() == (b ?? '').trim();

        final sameMaterialDocument = postingVoucher.voucherType.toUpperCase() ==
                voucher.voucherType.toUpperCase() &&
            postingVoucher.partyType?.toUpperCase() ==
                voucher.partyType?.toUpperCase() &&
            sameText(postingVoucher.partyId, voucher.partyId) &&
            (postingVoucher.amount * 100).round() ==
                (voucher.amount * 100).round() &&
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
            'status': 'POSTED',
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
            // Operating expenses have an expense account, not a counterparty.
            'party_type':
                postingVoucher.partyType?.toUpperCase() == 'EXPENSE' &&
                        (postingVoucher.partyId?.trim().isEmpty ?? true)
                    ? null
                    : postingVoucher.partyType,
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
          'status': 'POSTED',
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

      if ((postingVoucher.source ?? '').trim().toUpperCase() ==
              'PAYROLL_ENTITLEMENT' &&
          (postingVoucher.sourceId ?? '').trim().isNotEmpty) {
        await _syncPayrollRunFromVouchers(txn, postingVoucher.sourceId!.trim());
      }

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
      await AuditTrailService.log(
        executor: txn,
        action: 'PAYMENT_VOUCHER_POSTED',
        entityType: 'voucher',
        entityId: id,
        before: existingRows.isEmpty ? null : existingRows.first,
        after: (await txn.query(table, where: 'id=?', whereArgs: [id])).single,
      );
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
      await txn.insert(
          "payments",
          {
            "id": "VOUCHER_LOG:${voucher.id}",
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
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }

    if (type == "EXPENSE") {
      await txn.insert(
          "payments",
          {
            "id": "VOUCHER_LOG:${voucher.id}",
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
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
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

    final settledRow = await txn.rawQuery(
      "SELECT ${PurchaseBalanceSql.paid('?', excludingVoucher: '?')} AS s",
      [invoiceId, voucherId],
    );

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
      final isPayroll =
          (voucher.source ?? '').trim().toUpperCase() == 'PAYROLL_ENTITLEMENT';
      var isBonus = (voucher.source ?? '').toUpperCase() == 'EMPLOYEE_BONUS';
      if ((voucher.source ?? '').toUpperCase() == 'EMP_ADV' &&
          voucher.sourceId != null) {
        final legacy = await txn.query('employee_advances',
            columns: ['type'],
            where: 'id=?',
            whereArgs: [voucher.sourceId],
            limit: 1);
        isBonus = legacy.isNotEmpty && legacy.first['type'] == 'bonus';
      }
      final code = isPayroll
          ? "2140.E$empId"
          : isBonus
              ? '5100'
              : "1120.E$empId";

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
        "name": isPayroll
            ? "مستحقات رواتب - $partyName"
            : isBonus
                ? 'مصروف رواتب ومكافآت'
                : "سلفة موظف: $partyName",
        "type": isPayroll
            ? "LIABILITY"
            : isBonus
                ? 'EXPENSE'
                : "ASSET",
        "normal_balance": isPayroll ? "CREDIT" : "DEBIT",
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

  static Future<void> _ensureSalaryPeriodsSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salary_periods(
        month TEXT PRIMARY KEY,
        is_locked INTEGER NOT NULL DEFAULT 0,
        locked_at TEXT,
        note TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_salary_periods_locked '
      'ON salary_periods(is_locked)',
    );
  }

  static Future<void> _ensureVoucherColumn(
    DatabaseExecutor db,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info(vouchers)');
    if (!info.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE vouchers ADD COLUMN $column $type');
    }
  }

  static Future<void> _validateVoucherOnTxn({
    required Transaction txn,
    required VoucherPayment voucher,
  }) async {
    final partyType = (voucher.partyType ?? '').trim().toUpperCase();
    final partyId = (voucher.partyId ?? '').trim();
    final method = voucher.method.trim().toUpperCase();

    const allowedMethods = {'CASH', 'BANK', 'TRANSFER', 'CHEQUE'};
    if (!allowedMethods.contains(method)) {
      throw StateError('Unsupported payment method: ${voucher.method}');
    }

    if (partyType == 'SUPPLIER') {
      final supplierId = int.tryParse(partyId);
      if (supplierId == null || supplierId <= 0) {
        throw StateError('Supplier payment voucher requires a valid supplier.');
      }
      final suppliers = await txn.query(
        'suppliers',
        columns: const ['id'],
        where: 'id=?',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (suppliers.isEmpty) {
        throw StateError('Supplier does not exist.');
      }

      final reference = (voucher.reference ?? '').trim();
      if (reference.isNotEmpty) {
        final invoices = await txn.query(
          'purchase_invoices',
          columns: const ['id', 'supplier_id', 'amount_total', 'status'],
          where: 'id=? AND supplier_id=?',
          whereArgs: [reference, supplierId],
          limit: 1,
        );
        if (invoices.isEmpty) {
          throw StateError(
            'Referenced purchase invoice does not belong to this supplier.',
          );
        }

        if (['VOID', 'CANCELLED', 'REVERSED']
            .contains('${invoices.first['status']}'.toUpperCase())) {
          throw StateError('Cannot pay a cancelled invoice');
        }
        final settledRows = await txn.rawQuery(
          "SELECT ${PurchaseBalanceSql.paid('?', excludingVoucher: '?')} AS s",
          [reference, voucher.id],
        );
        final settled = (settledRows.first['s'] as num?)?.toDouble() ?? 0.0;
        final total =
            (invoices.first['amount_total'] as num?)?.toDouble() ?? 0.0;
        final remaining = total - settled;
        if (voucher.amount - remaining > 0.01) {
          throw StateError(
            'Supplier payment exceeds the referenced invoice remaining amount.',
          );
        }
      }
    } else if (partyType == 'EMPLOYEE') {
      if (partyId.isEmpty) {
        throw StateError('Employee payment voucher requires an employee.');
      }
      final employees = await txn.query(
        'employees',
        columns: const ['id'],
        where: 'id=?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (employees.isEmpty) {
        throw StateError('Employee does not exist.');
      }

      if ((voucher.source ?? '').trim().toUpperCase() ==
          'PAYROLL_ENTITLEMENT') {
        final runId = (voucher.sourceId ?? '').trim();
        if (runId.isEmpty || (voucher.reference ?? '').trim() != runId) {
          throw StateError(
            'Salary payment voucher must reference its payroll entitlement.',
          );
        }
        final runs = await txn.query(
          'payroll_runs',
          columns: const ['id', 'employee_id', 'net', 'status', 'period_start'],
          where: 'id=?',
          whereArgs: [runId],
          limit: 1,
        );
        if (runs.isEmpty) {
          throw StateError('Payroll entitlement does not exist.');
        }
        final run = runs.first;
        final month = (run['period_start'] ?? '').toString().substring(0, 7);
        await _ensureSalaryPeriodsSchema(txn);
        final locked = await txn.query('salary_periods',
            columns: ['is_locked'],
            where: 'month=? AND is_locked=1',
            whereArgs: [month],
            limit: 1);
        if (locked.isNotEmpty) {
          throw StateError('فترة الرواتب مقفلة؛ افتحها قبل الصرف.');
        }
        if ((run['employee_id'] ?? '').toString() != partyId) {
          throw StateError(
            'Payroll entitlement belongs to a different employee.',
          );
        }
        if ((run['status'] ?? '').toString().toUpperCase() == 'REVERSED') {
          throw StateError('Cannot pay a reversed payroll entitlement.');
        }
        final paidRows = await txn.rawQuery('''
          SELECT COALESCE(SUM(amount),0) AS paid
          FROM vouchers
          WHERE source='PAYROLL_ENTITLEMENT'
            AND source_id=?
            AND id<>?
            AND UPPER(COALESCE(status,'POSTED')) <> 'REVERSED'
            AND gl_entry_id IS NOT NULL
        ''', [runId, voucher.id]);
        final paid = (paidRows.first['paid'] as num?)?.toDouble() ?? 0.0;
        final net = (run['net'] as num?)?.toDouble() ?? 0.0;
        final remaining = net - paid;
        if (remaining <= 0.01) {
          throw StateError('Payroll entitlement is already fully paid.');
        }
        if (voucher.amount - remaining > 0.01) {
          throw StateError(
            'Salary payment exceeds payroll entitlement remaining amount.',
          );
        }
      }
    } else if (partyType == 'CLIENT') {
      final clientId = int.tryParse(partyId);
      if (clientId == null || clientId <= 0) {
        throw StateError('Client-linked voucher requires a valid client.');
      }
      final clients = await txn.query(
        'clients',
        columns: const ['id'],
        where: 'id=?',
        whereArgs: [clientId],
        limit: 1,
      );
      if (clients.isEmpty) {
        throw StateError('Client does not exist.');
      }
    } else if (partyType.isEmpty && (voucher.source ?? '').trim().isNotEmpty) {
      throw StateError(
        'Referenced payment voucher requires an explicit party.',
      );
    }
  }

  static Future<void> _syncPayrollRunFromVouchers(
    DatabaseExecutor db,
    String runId,
  ) async {
    final runRows = await db.query(
      'payroll_runs',
      columns: const ['net'],
      where: 'id=?',
      whereArgs: [runId],
      limit: 1,
    );
    if (runRows.isEmpty) return;
    final net = (runRows.first['net'] as num?)?.toDouble() ?? 0.0;
    final sums = await db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) AS paid
      FROM vouchers
      WHERE source='PAYROLL_ENTITLEMENT'
        AND source_id=?
        AND UPPER(COALESCE(status,'POSTED')) <> 'REVERSED'
        AND gl_entry_id IS NOT NULL
    ''', [runId]);
    final paid = (sums.first['paid'] as num?)?.toDouble() ?? 0.0;
    await db.update(
      'payroll_runs',
      {
        'amount_paid': double.parse(paid.toStringAsFixed(2)),
        'status': paid + 0.01 >= net ? 'PAID' : 'ACCRUED',
      },
      where: 'id=?',
      whereArgs: [runId],
    );
  }

  /// Formal cancellation for a posted payment voucher.
  /// The original document remains archived. Cash/bank is reversed in GL;
  /// cheque vouchers use the cheque lifecycle cancellation exactly once.
  static Future<void> reverseVoucher(
    String voucherId, {
    required String reason,
    Database? database,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('A reversal reason is required.');
    }

    final db = database ?? await DBService.database;
    await SyncFoundationService.transaction(db, (txn) async {
      await ensureSchema(txn);

      final rows = await txn.query(
        table,
        where: 'id=?',
        whereArgs: [voucherId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Voucher not found.');

      final row = Map<String, Object?>.from(rows.first);
      final status = (row['status'] ?? '').toString().toUpperCase();
      if (status == 'REVERSED' || status == 'VOID') {
        throw StateError('Voucher is already reversed.');
      }

      int? glId = row['gl_entry_id'] is num
          ? (row['gl_entry_id'] as num).toInt()
          : int.tryParse('${row['gl_entry_id'] ?? ''}');
      if (glId == null) {
        final actualGl = await txn.query(
          'gl_entries',
          columns: const ['id'],
          where: 'source=? AND source_id=?',
          whereArgs: ['VOUCHER', voucherId],
          orderBy: 'id ASC',
          limit: 1,
        );
        if (actualGl.isNotEmpty) {
          final raw = actualGl.first['id'];
          glId = raw is num ? raw.toInt() : int.tryParse('$raw');
        }
      }

      if (glId == null) {
        final changes = <String, Object?>{
          'status': 'VOID',
          'reversal_reason': trimmedReason,
          'reversed_at': DateTime.now().toUtc().toIso8601String(),
        };
        await txn.update(table, changes, where: 'id=?', whereArgs: [voucherId]);
        await AuditTrailService.log(
            executor: txn,
            action: 'PAYMENT_VOUCHER_VOIDED',
            entityType: 'voucher',
            entityId: voucherId,
            before: row,
            after: {...row, ...changes},
            reason: trimmedReason);
        return;
      }

      int? reversalGlId;
      final method = (row['method'] ?? '').toString().trim().toUpperCase();
      if (method == 'CHEQUE') {
        final chequeId = int.tryParse('${row['cheque_id'] ?? ''}');
        if (chequeId == null) {
          throw StateError('Posted cheque voucher has no valid cheque link.');
        }
        await ChequeAccountingService.transitionStatusOnTxn(
          txn: txn,
          chequeId: chequeId,
          newStatus: ChequeStatus.cancelled,
          reason: trimmedReason,
        );
        final events = await txn.query(
          'cheque_events',
          columns: const ['gl_entry_id'],
          where: 'cheque_id=? AND event_type=?',
          whereArgs: [chequeId, 'status:cancelled'],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (events.isNotEmpty) {
          final raw = events.first['gl_entry_id'];
          reversalGlId = raw is num ? raw.toInt() : int.tryParse('$raw');
        }
      } else {
        reversalGlId = await DBService.reverseEntryGLOn(
          txn,
          glId,
          note: 'Payment voucher reversal: $trimmedReason',
        );
      }

      final originalSettlements = await txn.query('invoice_settlements',
          where: 'voucher_id=?', whereArgs: [voucherId]);
      await txn.delete(
        'invoice_settlements',
        where: 'voucher_id=?',
        whereArgs: [voucherId],
      );

      final now = DateTime.now().toIso8601String();
      await txn.update(
        table,
        {
          'status': 'REVERSED',
          'reversal_gl_entry_id': reversalGlId,
          'reversed_at': now,
          'reversal_reason': trimmedReason,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [voucherId],
      );

      if ((row['source'] ?? '').toString().trim().toUpperCase() ==
              'PAYROLL_ENTITLEMENT' &&
          (row['source_id'] ?? '').toString().trim().isNotEmpty) {
        await _syncPayrollRunFromVouchers(
          txn,
          (row['source_id'] ?? '').toString().trim(),
        );
      }

      await AuditTrailService.log(
        executor: txn,
        action: 'PAYMENT_VOUCHER_REVERSED',
        entityType: 'voucher',
        entityId: voucherId,
        before: row,
        after: {
          ...row,
          'status': 'REVERSED',
          'reversal_gl_entry_id': reversalGlId,
          'reversed_at': now,
        },
        reason: trimmedReason,
        metadata: {
          'original_gl_entry_id': glId,
          'reversed_settlements': originalSettlements,
          'method': method,
        },
      );
    });
  }
}
