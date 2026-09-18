import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
import 'package:yalla_accounts/features/finance/services/financial_void_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';
// 📁 lib/features/finance/invoices/services/invoice_service.dart
//
// FINAL STABLE VERSION — v38
// ------------------------------------------------------------
// مواصفات النسخة:
// • GL idempotent بالكامل
// • متوافقة مع DBService v38 (postInvoiceGL / postInvoiceGLOnTransaction)
// • متوافقة مع InvoiceDatabaseService الجديد
// • بدون أي تعارضات مع الشاشات / providers
// • بدون أي دوال ناقصة
// • بنية ثابتة كما هي بدون تغيير

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';

class InvoiceService {
  InvoiceService._();
  static final InvoiceService instance = InvoiceService._();
  static final InvoiceService I = instance;

  static const String _table = 'invoices';

  // ============================================================
  // 1) Schema
  // ============================================================
  static Future<void> _ensureSchema([DatabaseExecutor? exec]) async {
    final db = exec ?? await DBService.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table(
        id TEXT PRIMARY KEY,
        repair_id TEXT,
        date TEXT NOT NULL,
        subtotal REAL,
        vat REAL,
        total REAL NOT NULL DEFAULT 0,
        paid REAL NOT NULL DEFAULT 0,
        status TEXT,
        notes TEXT,
        note TEXT,
        method TEXT,
        gl_entry_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        client_id INTEGER
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_repair ON $_table(repair_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_client ON $_table(client_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_gl ON $_table(gl_entry_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoice_date ON $_table(date)');
  }

  // ============================================================
  // 2) Basic Reads
  // ============================================================
  Future<Map<String, Object?>?> getById(String id) async {
    final db = await DBService.database;
    await _ensureSchema(db);

    final rows =
        await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);

    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> getByRepairId(String repairId) async {
    final db = await DBService.database;
    await _ensureSchema(db);

    final rows = await db.query(
      _table,
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  // ============================================================
  // 3) Dashboard Count
  // ============================================================
  Future<int> getInvoicesCountForMonth(DateTime month) async {
    final db = await DBService.database;
    await _ensureSchema(db);

    final start = DateTime(month.year, month.month, 1).toIso8601String();
    final end = DateTime(month.year, month.month + 1, 1).toIso8601String();

    final res = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE date >= ? AND date < ?',
      [start, end],
    );

    final v = res.isNotEmpty ? res.first['c'] : 0;

    if (v is int) return v;
    if (v is num) return v.toInt();

    return int.tryParse(v.toString()) ?? 0;
  }

  // ============================================================
  // 4) Create or Return Existing
  // ============================================================
  Future<String> createOrGetByRepair({
    required String repairId,
    required DateTime date,
    double total = 0.0,
    double? subtotal,
    double? vat,
    String status = 'unpaid',
    String? notes,
    String? method,
    String? note,
    int? clientId,
  }) async {
    final db = await DBService.database;
    await _ensureSchema(db);

    // هل موجودة؟
    final existing = await getByRepairId(repairId);
    if (existing != null) return existing['id'].toString();

    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.invoiceCreate);
    // إنشاء جديدة
    final id = const Uuid().v4();
    final nowIso = DateTime.now().toIso8601String();

    final vatValue = _to2(vat);
    final sub = subtotal ?? _to2(total - vatValue);
    final tot = _to2(sub + vatValue);

    final resolvedClient = clientId ?? await _clientIdByRepair(repairId);
    await SyncFoundationService.transaction(db, (txn) async {
      await txn.insert(
        _table,
        {
          'id': id,
          'repair_id': repairId,
          'date': date.toIso8601String(),
          'subtotal': sub,
          'vat': vatValue,
          'total': tot,
          'paid': 0.0,
          'status': status,
          'notes': notes,
          'note': note,
          'method': method,
          'created_at': nowIso,
          'updated_at': nowIso,
          'client_id': resolvedClient,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await AuditTrailService.log(
        executor: txn,
        actorUserId: p16Actor?.id,
        actorRole: p16Actor?.role,
        action: 'INVOICE_CREATED',
        entityType: 'invoice',
        entityId: id,
        after: {
          'repair_id': repairId,
          'client_id': clientId,
          'subtotal': sub,
          'vat': vatValue,
          'total': tot,
          'status': status,
        },
        reason: note ?? notes,
      );
    });
    return id;
  }

  // ============================================================
  // 5) Create or Update + GL Posting
  // ============================================================
  Future<String> createInvoice({
    String? id,
    required String repairId,
    required DateTime date,
    required double total,
    double? subtotal,
    double vatAmount = 0.0,
    String status = 'unpaid',
    String? notes,
    String? note,
    String? method,
    int? clientId,
    bool postToGL = true,
  }) async {
    await AuthorizationGuard.require(
      postToGL ? PermissionKeys.invoicePost : PermissionKeys.invoiceCreate,
    );
    // P0.006 — invoice creation + posting is one atomic transaction.
    final invoiceId = await DBService.inTx((txn) async {
      return createInvoiceOnTransaction(
        txn: txn,
        id: id,
        repairId: repairId,
        date: date,
        total: total,
        subtotal: subtotal,
        vatAmount: vatAmount,
        status: status,
        notes: notes,
        note: note,
        method: method,
        clientId: clientId,
        postToGL: postToGL,
      );
    });
    return invoiceId;
  }

  // ============================================================
  // 6) On Transaction
  // ============================================================
  Future<String> createInvoiceOnTransaction({
    required DatabaseExecutor txn,
    String? id,
    required String repairId,
    required DateTime date,
    required double total,
    double? subtotal,
    double vatAmount = 0.0,
    String status = 'unpaid',
    String? notes,
    String? note,
    String? method,
    int? clientId,
    bool postToGL = true,
  }) async {
    await _ensureSchema(txn);

    final vat = _to2(vatAmount);
    final sub = subtotal ?? _to2((total - vat).clamp(0, double.infinity));
    final tot = _to2(sub + vat);

    if (tot <= 0) {
      throw StateError('Cannot create/post invoice with total <= 0');
    }

    final resolvedClientId =
        clientId ?? await _clientIdByRepairOnTransaction(txn, repairId);

    if (resolvedClientId == null || resolvedClientId <= 0) {
      throw StateError(
        'Cannot create/post invoice for repair $repairId without client_id',
      );
    }

    final existing = await txn.query(
      _table,
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final existingId = row['id'].toString();

      final glRows = await txn.query(
        'gl_entries',
        columns: ['id'],
        where: 'source = ? AND source_id = ?',
        whereArgs: ['INVOICE', existingId],
        limit: 1,
      );

      if (glRows.isNotEmpty) {
        final storedTotal = _asD(row['total']) ?? 0.0;
        final storedVat = _asD(row['vat_amount']) ?? _asD(row['vat']) ?? 0.0;
        final storedClient = row['client_id'] is int
            ? row['client_id'] as int
            : int.tryParse('${row['client_id']}');

        if ((storedTotal - tot).abs() > 0.01 ||
            (storedVat - vat).abs() > 0.01 ||
            (storedClient != null && storedClient != resolvedClientId)) {
          throw StateError(
            'Posted invoice $existingId is immutable. '
            'Use a formal credit/debit note or reversal/reissue workflow.',
          );
        }

        final rawGlId = glRows.first['id'];
        final glId = rawGlId is int ? rawGlId : int.parse(rawGlId.toString());

        await txn.update(
          _table,
          {
            'gl_entry_id': glId,
            'post_to_gl': 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );

        await txn.update(
          'repairs',
          {'invoice_id': existingId},
          where: 'id = ?',
          whereArgs: [repairId],
        );

        return existingId;
      }

      // Unposted invoice may still be edited before the accounting event.
      await txn.update(
        _table,
        {
          'subtotal': sub,
          'vat': vat,
          'vat_amount': vat,
          'total': tot,
          if (notes != null) 'notes': notes,
          if (note != null) 'note': note,
          if (method != null) 'method': method,
          'client_id': resolvedClientId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );

      if (postToGL) {
        final glId = await _postInvoiceGLAndLinkOnTransaction(
          txn: txn,
          invoiceId: existingId,
          repairId: repairId,
          date: date,
          total: tot,
          vatAmount: vat,
          note: notes ?? note,
          clientId: resolvedClientId,
        );

        if (glId == null) {
          throw StateError('Invoice GL posting failed for $existingId');
        }

        await txn.update(
          _table,
          {
            'gl_entry_id': glId,
            'post_to_gl': 1,
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );
      }

      await txn.update(
        'repairs',
        {'invoice_id': existingId},
        where: 'id = ?',
        whereArgs: [repairId],
      );

      return existingId;
    }

    final invId = id?.isNotEmpty == true ? id! : const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    await txn.insert(
      _table,
      {
        'id': invId,
        'repair_id': repairId,
        'date': date.toIso8601String(),
        'subtotal': sub,
        'vat': vat,
        'vat_amount': vat,
        'total': tot,
        'paid': 0.0,
        'status': status,
        'notes': notes,
        'note': note,
        'method': method,
        'created_at': now,
        'updated_at': now,
        'client_id': resolvedClientId,
        'post_to_gl': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    if (postToGL) {
      final glId = await _postInvoiceGLAndLinkOnTransaction(
        txn: txn,
        invoiceId: invId,
        repairId: repairId,
        date: date,
        total: tot,
        vatAmount: vat,
        note: notes ?? note,
        clientId: resolvedClientId,
      );

      if (glId == null) {
        throw StateError('Invoice GL posting failed for $invId');
      }

      await txn.update(
        _table,
        {
          'gl_entry_id': glId,
          'post_to_gl': 1,
        },
        where: 'id = ?',
        whereArgs: [invId],
      );
    }

    await txn.update(
      'repairs',
      {'invoice_id': invId},
      where: 'id = ?',
      whereArgs: [repairId],
    );

    await AuditTrailService.log(
        executor: txn,
        action: existing.isEmpty ? 'INVOICE_CREATED' : 'INVOICE_UPDATED',
        entityType: 'invoice',
        entityId: invId,
        before: existing.isEmpty ? null : existing.first,
        after:
            (await txn.query(_table, where: 'id=?', whereArgs: [invId])).single,
        reason: note ?? notes);
    return invId;
  }

  Future<void> _assertInvoiceMutable(
    DatabaseExecutor db,
    String id,
  ) async {
    final invoiceRows = await db.query(
      _table,
      columns: const ['gl_entry_id', 'post_to_gl'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (invoiceRows.isEmpty) return;

    final row = invoiceRows.first;
    final rawGlId = row['gl_entry_id'];
    final hasStoredGlId = rawGlId != null &&
        rawGlId.toString().trim().isNotEmpty &&
        rawGlId.toString() != '0';
    final markedPosted = (row['post_to_gl'] as num?)?.toInt() == 1;

    final postedRows = await db.query(
      'gl_entries',
      columns: const ['id'],
      where: 'source = ? AND source_id = ?',
      whereArgs: ['INVOICE', id],
      limit: 1,
    );

    if (hasStoredGlId || markedPosted || postedRows.isNotEmpty) {
      throw StateError(
        'Posted invoice $id is immutable. '
        'Use a formal credit/debit note or reversal/reissue workflow.',
      );
    }
  }

  // ============================================================
  // 7) Update Invoice
  // ============================================================
  Future<int> updateInvoice({
    required String id,
    DateTime? date,
    double? subtotal,
    double? vat,
    double? total,
    String? status,
    String? notes,
    String? method,
    String? note,
    String? glEntryId,
    int? clientId,
  }) async {
    return DBService.inTx((txn) async {
      await _ensureSchema(txn);
      await _assertInvoiceMutable(txn, id);
      final before = await txn.query(_table, where: 'id=?', whereArgs: [id]);

      double? totOut = total;

      if (subtotal != null || vat != null) {
        final currentRows = await txn.query(
          _table,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final cur = currentRows.isEmpty ? null : currentRows.first;
        final sub = subtotal ?? _asD(cur?['subtotal']) ?? 0.0;
        final v = vat ?? _asD(cur?['vat']) ?? 0.0;
        totOut = _to2(sub + v);
      }

      final data = <String, Object?>{
        if (date != null) 'date': date.toIso8601String(),
        if (subtotal != null) 'subtotal': _to2(subtotal),
        if (vat != null) 'vat': _to2(vat),
        if (totOut != null) 'total': _to2(totOut),
        if (status != null) 'status': status,
        if (notes != null) 'notes': notes,
        if (method != null) 'method': method,
        if (note != null) 'note': note,
        if (clientId != null) 'client_id': clientId,
        if (glEntryId != null) 'gl_entry_id': glEntryId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      data.removeWhere((k, v) => v == null);
      if (data.length == 1) return 0;

      final count = await txn.update(
        _table,
        data,
        where: 'id=?',
        whereArgs: [id],
      );
      if (count > 0) {
        await AuditTrailService.log(
            executor: txn,
            action: 'INVOICE_UPDATED',
            entityType: 'invoice',
            entityId: id,
            before: before.single,
            after: (await txn.query(_table, where: 'id=?', whereArgs: [id]))
                .single,
            reason: note ?? notes);
      }
      return count;
    });
  }

  // ============================================================
  // 8) Delete Invoice
  // ============================================================
  Future<int> deleteInvoice(String id,
      {String reason = 'Invoice cancelled'}) async {
    final db = await DBService.database;
    final rows = await db.query(_table, where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return 0;
    final repairId = rows.single['repair_id']?.toString() ?? '';
    if (repairId.isNotEmpty) {
      await RepairAutoAccountingService.deleteRepair(repairId, reason: reason);
      return 1;
    }
    return FinancialVoidService.voidInvoice(id,
        purchase: false, reason: reason);
  }

  // ============================================================
  // 9) Recompute paid from payments
  // ============================================================
  Future<void> recomputePaidFromPayments(String invoiceId) async {
    final db = await DBService.database;
    await _ensureSchema(db);

    await SyncFoundationService.transaction(db, (txn) async {
      final inv = await txn.query(
        _table,
        columns: ['total', 'repair_id', 'status'],
        where: 'id=?',
        whereArgs: [invoiceId],
        limit: 1,
      );

      if (inv.isEmpty) {
        throw StateError('invoice $invoiceId not found');
      }

      if (['VOID', 'CANCELLED']
          .contains('${inv.first['status']}'.toUpperCase())) {
        return;
      }
      final total = _asD(inv.first['total']) ?? 0.0;

      final repairId = inv.first['repair_id']?.toString() ?? '';
      final paid = repairId.isNotEmpty
          ? await RepairFinancialTruthService.paidForRepair(repairId,
              executor: txn)
          : ((await txn.rawQuery('''
              SELECT COALESCE(SUM(l.credit-l.debit),0) AS paid
              FROM gl_lines l JOIN gl_entries e ON e.id=l.entry_id
              JOIN accounts a ON a.id=l.account_id
              LEFT JOIN gl_entries original ON original.id=e.reversal_of
              WHERE l.invoice_id=? AND (a.code='1200' OR a.code LIKE '1200.%')
                AND UPPER(COALESCE(original.source,e.source)) IN ('PAYMENT','CREDIT_ALLOCATION','CHEQUE_STATUS')
            ''', [invoiceId])).single['paid'] as num).toDouble();

      String status;

      if (paid <= 0.0000001) {
        status = 'unpaid';
      } else if ((total - paid).abs() <= 0.0000001 || paid > total) {
        status = 'paid';
      } else {
        status = 'partial';
      }

      await txn.update(
        _table,
        {
          'paid': _to2(paid),
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [invoiceId],
      );
    });
  }

  // ============================================================
  // 10) Recompute by repair_id
  // ============================================================
  Future<void> recomputeForRepair(String repairId) async {
    final inv = await getByRepairId(repairId);
    if (inv == null) return;

    await recomputePaidFromPayments(inv['id'].toString());
  }

  // ============================================================
  // 11) Private GL Posting (Idempotent)
  // ============================================================
  Future<String?> _postInvoiceGLAndLinkOnTransaction({
    required DatabaseExecutor txn,
    required String invoiceId,
    required String repairId,
    required DateTime date,
    required double total,
    required double vatAmount,
    required int clientId,
    String? note,
  }) async {
    if (clientId == 0) return null;

    final glId = await DBService.postInvoiceGLOnTransaction(
      txn: txn,
      invoiceId: invoiceId,
      date: date,
      clientId: clientId,
      total: total,
      vatAmount: vatAmount,
      repairId: repairId,
      ref: invoiceId,
      note: note,
    );

    return glId.toString();
  }

  // ============================================================
  // INTERNAL HELPERS
  // ============================================================
  static double _to2(double? v) {
    if (v == null) return 0.0;
    return double.parse(v.toStringAsFixed(2));
  }

  static double? _asD(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<int?> _clientIdByRepair(String repairId) async {
    final db = await DBService.database;

    final r = await db.rawQuery(
      'SELECT client_id FROM repairs WHERE id=? LIMIT 1',
      [repairId],
    );

    if (r.isEmpty) return null;

    final v = r.first['client_id'];

    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  Future<int?> _clientIdByRepairOnTransaction(
      DatabaseExecutor txn, String repairId) async {
    final r = await txn.rawQuery(
      'SELECT client_id FROM repairs WHERE id=? LIMIT 1',
      [repairId],
    );

    if (r.isEmpty) return null;

    final v = r.first['client_id'];

    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }
}
