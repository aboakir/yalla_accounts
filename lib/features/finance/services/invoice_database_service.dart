import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
// 📁 lib/features/finance/services/invoice_database_service.dart
//
// FINAL — الإصدار المستقر بالكامل
// • متوافق مع DBService v38
// • متوافق مع AccountingTables v38
// • بدون أي missing methods
// • بدون أي تعارض مع InvoiceService القديم
// • تصميم مستقل (namespace) للمنظومة الجديدة
// • لا يعتمد على createOrGetByRepairTx (غير موجود عندك)
// • لا يعتمد على updatePaidAmountTx (غير موجود عندك)

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/invoice.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';

class InvoiceDatabaseService {
  InvoiceDatabaseService._();
  static final InvoiceDatabaseService instance = InvoiceDatabaseService._();

  static const _table = 'invoices';
  static final _uuid = const Uuid();

  // ================================================================
  // 1) Schema
  // ================================================================
  Future<void> _ensureTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id TEXT PRIMARY KEY,
        repair_id TEXT,
        date TEXT NOT NULL,
        total REAL NOT NULL DEFAULT 0,
        paid REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        notes TEXT,
        created_at TEXT,
        updated_at TEXT,
        client_id INTEGER
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_date ON $_table(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_client_id ON $_table(client_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_repair_id ON $_table(repair_id)');

    await AccountingTables.ensureColumnOn(
      db: db,
      table: _table,
      column: 'subtotal',
      type: 'REAL',
    );

    await AccountingTables.ensureColumnOn(
      db: db,
      table: _table,
      column: 'vat',
      type: 'REAL',
    );

    await AccountingTables.ensureColumnOn(
      db: db,
      table: _table,
      column: 'method',
      type: 'TEXT',
    );

    await AccountingTables.ensureColumnOn(
      db: db,
      table: _table,
      column: 'note',
      type: 'TEXT',
    );

    await AccountingTables.ensureColumnOn(
      db: db,
      table: _table,
      column: 'gl_entry_id',
      type: 'INTEGER',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoices_gl ON $_table(gl_entry_id)',
    );
  }

  // ================================================================
  // 2) Helpers
  // ================================================================
  String _computeStatus(double total, double paid) {
    if (paid <= 0) return 'unpaid';
    if (paid + 0.00001 >= total) return 'paid';
    return 'partial';
  }

  double _round(num v) => double.parse(v.toDouble().toStringAsFixed(2));

  Future<double> _ensureTotalFromRepair(
      DatabaseExecutor db, String repairId, double currentTotal) async {
    if (currentTotal > 0) return _round(currentTotal);

    final r = await db.query(
      'repairs',
      columns: ['fileValue'],
      where: 'id=?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (r.isEmpty) return 0.0;

    final v = r.first['fileValue'];
    final d = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

    return _round(d);
  }

  Future<int?> _getClientIdFromRepair(
      DatabaseExecutor db, String repairId) async {
    final r = await db.query(
      'repairs',
      columns: ['client_id'],
      where: 'id=?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (r.isEmpty) return null;

    final v = r.first['client_id'];
    if (v == null) return null;
    if (v is int) return v;

    return int.tryParse(v.toString());
  }

  //   // 3) Create or Get  — TX-SAFE
  // ================================================================
  Future<Invoice> createOrGetByRepair({
    required String repairId,
    required DateTime date,
    required double total,
    required double paid,
    String? notes,
    required DatabaseExecutor txn,
  }) async {
    // P0.004 — invoice row + INVOICE GL must succeed atomically in the
    // same transaction. Never swallow a posting failure.
    await _ensureTable(txn);

    late Invoice inv;

    final current = await txn.query(
      _table,
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (current.isNotEmpty) {
      inv = Invoice.fromMap(current.first);
    } else {
      final clientId = await _getClientIdFromRepair(txn, repairId);

      if (clientId == null || clientId <= 0) {
        throw StateError(
          'Cannot create/post invoice for repair $repairId without client_id',
        );
      }

      final ensuredTotal = await _ensureTotalFromRepair(txn, repairId, total);

      if (ensuredTotal <= 0) {
        throw StateError(
          'Cannot create/post invoice for repair $repairId with total <= 0',
        );
      }

      final id = _uuid.v4();
      final row = <String, Object?>{
        'id': id,
        'repair_id': repairId,
        'date': date.toIso8601String(),
        'total': ensuredTotal,
        'paid': _round(paid),
        'status': _computeStatus(ensuredTotal, _round(paid)),
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'client_id': clientId,
      };

      await txn.insert(_table, row);
      inv = Invoice.fromMap(row);
    }

    final clientId =
        inv.clientId ?? await _getClientIdFromRepair(txn, repairId);

    if (clientId == null || clientId <= 0) {
      throw StateError('Cannot post invoice ${inv.id} without client_id');
    }

    final existingGl = await txn.query(
      'gl_entries',
      columns: ['id'],
      where: 'source = ? AND source_id = ?',
      whereArgs: ['INVOICE', inv.id],
      orderBy: 'id DESC',
      limit: 1,
    );

    int glId;

    if (existingGl.isNotEmpty) {
      final raw = existingGl.first['id'];
      glId = raw is int ? raw : int.parse(raw.toString());
    } else {
      glId = await DBService.postInvoiceGLOnTransaction(
        txn: txn,
        invoiceId: inv.id,
        date: inv.date,
        clientId: clientId,
        total: inv.total,
        vatAmount: inv.vat ?? 0.0,
        repairId: inv.repairId,
        note: inv.notes ?? inv.note,
      );
    }

    await txn.update(
      _table,
      {
        'gl_entry_id': glId,
        'post_to_gl': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [inv.id],
    );

    final refreshed = await txn.query(
      _table,
      where: 'id = ?',
      whereArgs: [inv.id],
      limit: 1,
    );

    if (refreshed.isEmpty) {
      throw StateError('Invoice ${inv.id} disappeared after posting');
    }

    return Invoice.fromMap(refreshed.first);
  }

  //   // ================================================================
  // 4) Update Paid Amount — TX-SAFE
  // ================================================================
  Future<void> updatePaidAmount({
    required String repairId,
    required double newPaid,
    required DatabaseExecutor txn,
  }) async {
    await _ensureTable(txn);

    final cur = await txn.query(
      _table,
      where: 'repair_id=?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (cur.isEmpty) {
      throw StateError(
        'Cannot update invoice payment for repair $repairId: no invoice exists',
      );
    }

    // P0.006 — invoice total is commercial/accounting history.
    // Payment updates may change paid/status only.
    final total = (cur.first['total'] as num?)?.toDouble() ?? 0.0;

    await txn.update(
      _table,
      {
        'paid': _round(newPaid),
        'status': _computeStatus(total, newPaid),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'repair_id=?',
      whereArgs: [repairId],
    );
  }

  //   // ================================================================
  // 5) Recompute Whole Invoice  — TX-Version
  // ================================================================
  Future<void> recomputeForRepair({
    required String repairId,
    required DatabaseExecutor txn,
  }) async {
    await _ensureTable(txn);

    final paid = await RepairFinancialTruthService.paidForRepair(repairId,
        executor: txn);

    final cur = await txn.query(
      _table,
      where: 'repair_id=?',
      whereArgs: [repairId],
      limit: 1,
    );

    // Repair/payment maintenance must not invent an invoice.
    if (cur.isEmpty) return;

    final total = (cur.first['total'] as num?)?.toDouble() ?? 0.0;

    await txn.update(
      _table,
      {
        'paid': paid,
        'status': _computeStatus(total, paid),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'repair_id=?',
      whereArgs: [repairId],
    );
  }

  //   // ================================================================
  // 6) Reads — SAFE READ-ONLY OPERATIONS
  // ================================================================
  Future<Invoice?> getById(String id) async {
    final db = await DBService.database;
    await _ensureTable(db);

    final rows = await db.query(
      _table,
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return Invoice.fromMap(rows.first);
  }

  Future<Invoice?> getByRepairId(String repairId) async {
    final db = await DBService.database;
    await _ensureTable(db);

    final rows = await db.query(
      _table,
      where: 'repair_id=?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return Invoice.fromMap(rows.first);
  }

  Future<List<Invoice>> listAll({int? limit}) async {
    final db = await DBService.database;
    await _ensureTable(db);

    final rows = await db.query(
      _table,
      orderBy: 'date DESC',
      limit: limit,
    );

    return rows.map(Invoice.fromMap).toList();
  }

  Future<void> upsert(Invoice inv) async {
    final db = await DBService.database;
    await _ensureTable(db);

    await db.insert(
      _table,
      inv.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
