// 📁 lib/core/services/accounting_gl.dart
//
// GL Facade (v29) — طبقة نحيفة فوق DBService.
// يوفر نشر القيود + استعلامات Ledger:
//
// ensureCoreAccounts()
// ensureClientAccount(clientId, clientName)
// ensureSupplierAccount(supplierId, name)
// accountIdForClient / accountIdForSupplier
// idByCode('1000')
// post(...), reverse(...), inTx(...)
//
// 🧮 استعلامات:
// getAccountMeta(accountId)
// accountBalance(accountId, {from,to,withOpening})
// accountStatement(accountId, {from,to}) → rows + runningBalance
// accountStatementByCode(code, {from,to})
// partyBalance(partyType, partyId, {from,to})
// sumByAccount({from,to}) → لكل حساب: debit, credit, net
// trialBalance({from,to})
// fetchEntry(entryId), fetchBySource(source, sourceId)
// fetchRepairGL(repairId), fetchInvoiceGL(invoiceId)  ← متوافقة مع نشر REPAIR
//
// ملاحظة: لا أي بيانات وهمية.

import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class GL {
  // أكواد أساسية
  static const cash = '1000';
  static const bank = '1010';
  static const receivedCheques = '1020';
  static const issuedCheques = '1030';
  static const empAdvances = '1120';
  static const arMaster = '1200';
  static const inventoryOrPurchases = '1400';
  static const partsInventory = '1410';
  static const generalAp = '2100';
  static const vatPayable = '2105';
  static const payrollPayable = '2140';
  static const withholdingsPayable = '2145';
  static const apMaster = '2200';
  static const openingEquity = '3100';
  static const revenue = '4000';
  static const purchasesExpense = '5005';
  static const salariesExpense = '5100';
  static const rawMaterialsExpense = '5310';
  static const toolsExpense = '5350';
  static const otherExpense = '5900';

  // ===== واجهة نشر القيود =====

  static Future<void> ensureCoreAccounts() async {
    await DBService.ensureDefaultAccountsExist();
  }

  static Future<int> ensureClientAccount(int clientId, String clientName) {
    return DBService.ensureClientAccount(clientId);
  }

  static Future<int> ensureSupplierAccount(String supplierId, String name) {
    return DBService.ensureSupplierAccount(supplierId);
  }

  static Future<int?> accountIdForClient(int clientId) =>
      DBService.accountIdForClient(clientId);

  static Future<int?> accountIdForSupplier(String supplierId) =>
      DBService.accountIdForSupplier(supplierId);

  static Future<int> idByCode(String code) async {
    final id = await DBService.getAccountIdByCode(code);
    if (id == null) throw StateError('Account code $code not found');
    return id;
  }

  static Future<int> post({
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? note,
    required List<Map<String, Object?>> lines,
  }) {
    return DBService.postEntryGL(
      date: date,
      ref: ref,
      source: source,
      sourceId: sourceId,
      note: note,
      lines: lines,
    );
  }

  static Future<int> reverse(int entryId, {String? note}) =>
      DBService.reverseEntryGL(entryId, note: note);

  static Future<int> ensureNamedAccount({
    required String code,
    required String name,
    required String type, // ASSET/LIABILITY/EQUITY/REVENUE/EXPENSE
    required String normal, // DEBIT/CREDIT
  }) {
    return DBService.ensureAccount(
      code: code,
      name: name,
      type: type,
      normalBalance: normal,
    );
  }

  static Future<T> inTx<T>(Future<T> Function(DatabaseExecutor db) action) =>
      DBService.inTx(action);

  // ===== Helpers داخلية =====

  static Future<Database> get _db async => DBService.database;

  /// يجلب ميتاداتا الحساب من جدول accounts.
  static Future<Map<String, Object?>> getAccountMeta(int accountId) async {
    final db = await _db;
    final r = await db.query('accounts',
        where: 'id=?', whereArgs: [accountId], limit: 1);
    if (r.isEmpty) {
      throw StateError('account $accountId not found');
    }
    return r.first;
  }

  // ===== أرصدة وكشوف =====

  /// مجموع مدين/دائن وصافي خلال فترة. withOpening يضيف رصيد افتتاحي قبل from.
  static Future<Map<String, double>> accountBalance(
    int accountId, {
    DateTime? from,
    DateTime? to,
    bool withOpening = false,
  }) async {
    final db = await _db;
    final where = <String>['l.account_id=?'];
    final args = <Object?>[accountId];

    if (from != null) {
      where.add('e.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('e.date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT IFNULL(SUM(l.debit),0) AS d, IFNULL(SUM(l.credit),0) AS c
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE ${where.join(' AND ')}
    ''', args);

    final d = (rows.first['d'] as num).toDouble();
    final c = (rows.first['c'] as num).toDouble();
    double opening = 0.0;

    if (withOpening && from != null) {
      final o = await db.rawQuery('''
        SELECT IFNULL(SUM(l.debit),0) AS d, IFNULL(SUM(l.credit),0) AS c
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        WHERE l.account_id=? AND e.date < ?
      ''', [accountId, from.toIso8601String()]);
      final od = (o.first['d'] as num).toDouble();
      final oc = (o.first['c'] as num).toDouble();
      opening = od - oc;
    }

    return {
      'debit': d,
      'credit': c,
      'net': opening + d - c,
      'opening': opening,
    };
  }

  /// كشف حساب بفترة مع رصيد جاري (running = opening + debit - credit).
  static Future<Map<String, Object>> accountStatement(
    int accountId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db;

    // opening
    double opening = 0.0;
    if (from != null) {
      final o = await db.rawQuery('''
        SELECT IFNULL(SUM(l.debit),0) AS d, IFNULL(SUM(l.credit),0) AS c
        FROM gl_lines l
        JOIN gl_entries e ON e.id = l.entry_id
        WHERE l.account_id=? AND e.date < ?
      ''', [accountId, from.toIso8601String()]);
      opening =
          (o.first['d'] as num).toDouble() - (o.first['c'] as num).toDouble();
    }

    final where = <String>['l.account_id=?'];
    final args = <Object?>[accountId];
    if (from != null) {
      where.add('e.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('e.date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT
        e.id AS entry_id, e.date, e.ref, e.source, e.source_id, e.note,
        l.debit, l.credit,
        l.party_type, l.party_id,
        l.invoice_id, l.repair_id
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE ${where.join(' AND ')}
      ORDER BY e.date ASC, e.id ASC, l.id ASC
    ''', args);

    final lines = <Map<String, Object?>>[];
    double running = opening;
    for (final r in rows) {
      final d = (r['debit'] as num).toDouble();
      final c = (r['credit'] as num).toDouble();
      running += d - c;
      lines.add({
        ...r,
        'running': running,
      });
    }

    return {
      'opening': opening,
      'rows': lines,
      'closing': running,
    };
  }

  /// كشف حساب عبر كود الحساب مباشرة.
  static Future<Map<String, Object>> accountStatementByCode(
    String accountCode, {
    DateTime? from,
    DateTime? to,
  }) async {
    final id = await idByCode(accountCode);
    return accountStatement(id, from: from, to: to);
  }

  /// رصيد طرف party عبر gl_lines.party خلال فترة.
  static Future<Map<String, double>> partyBalance({
    required String partyType, // 'CUSTOMER' | 'SUPPLIER' | 'EMPLOYEE'
    required String partyId,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db;
    final where = <String>[
      'l.party_type=?',
      'l.party_id=?',
    ];
    final args = <Object?>[partyType, partyId];

    if (from != null) {
      where.add('e.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('e.date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT IFNULL(SUM(l.debit),0) AS d, IFNULL(SUM(l.credit),0) AS c
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      WHERE ${where.join(' AND ')}
    ''', args);

    final d = (rows.first['d'] as num).toDouble();
    final c = (rows.first['c'] as num).toDouble();
    return {'debit': d, 'credit': c, 'net': d - c};
  }

  /// تلخيص حسب الحساب بالفترة.
  static Future<List<Map<String, Object?>>> sumByAccount({
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _db;
    final where = <String>['1=1'];
    final args = <Object?>[];

    if (from != null) {
      where.add('e.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('e.date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT
        a.id AS account_id,
        a.code, a.name, a.type, a.normal_balance,
        IFNULL(SUM(l.debit),0) AS debit,
        IFNULL(SUM(l.credit),0) AS credit
      FROM gl_lines l
      JOIN gl_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE ${where.join(' AND ')}
      GROUP BY a.id, a.code, a.name, a.type, a.normal_balance
      ORDER BY a.code
    ''', args);

    return rows.map((r) {
      final d = (r['debit'] as num).toDouble();
      final c = (r['credit'] as num).toDouble();
      return {
        ...r,
        'net': d - c,
      };
    }).toList();
  }

  /// ميزان مراجعة.
  static Future<Map<String, Object>> trialBalance({
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await sumByAccount(from: from, to: to);
    double totalDebit = 0, totalCredit = 0;
    for (final r in rows) {
      totalDebit += (r['debit'] as num).toDouble();
      totalCredit += (r['credit'] as num).toDouble();
    }
    return {
      'total_debit': totalDebit,
      'total_credit': totalCredit,
      'balanced': (totalDebit - totalCredit).abs() < 0.005,
      'rows': rows,
    };
  }

  // ===== جلب قيود =====

  /// إدخال GL شامل سطور + بيانات الحسابات.
  static Future<Map<String, Object?>> fetchEntry(int entryId) async {
    final db = await _db;
    final head = await db.query('gl_entries',
        where: 'id=?', whereArgs: [entryId], limit: 1);
    if (head.isEmpty) throw StateError('gl entry not found');

    final lines = await db.rawQuery('''
      SELECT
        l.*,
        a.code, a.name, a.type, a.normal_balance
      FROM gl_lines l
      JOIN accounts a ON a.id = l.account_id
      WHERE l.entry_id=?
      ORDER BY l.id ASC
    ''', [entryId]);

    return {
      'entry': head.first,
      'lines': lines,
    };
  }

  /// قيد بحسب المصدر.
  static Future<Map<String, Object?>> fetchBySource(
      String source, String sourceId) async {
    final db = await _db;
    final e = await db.query('gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: [source, sourceId],
        limit: 1);
    if (e.isEmpty) {
      throw StateError('gl entry not found for $source:$sourceId');
    }
    final id = e.first['id'] as int;
    return fetchEntry(id);
  }

  /// قيد فاتورة إصلاح (نشرناها كمصدر REPAIR).
  static Future<Map<String, Object?>> fetchRepairGL(String repairId) =>
      fetchBySource('REPAIR', repairId);

  /// قيد فاتورة بالمعرف — يحاول REPAIR ثم INVOICE لمرونة أكبر.
  static Future<Map<String, Object?>> fetchInvoiceGL(String invoiceId) async {
    try {
      return await fetchBySource('REPAIR', invoiceId);
    } catch (_) {
      return fetchBySource('INVOICE', invoiceId);
    }
  }

  /// قيد دفعة.
  static Future<Map<String, Object?>> fetchPaymentGL(String paymentId) =>
      fetchBySource('PAYMENT', paymentId);
}
