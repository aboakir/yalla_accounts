import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/accounting_integrity_service.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class FinancialOverviewAccountActivity {
  const FinancialOverviewAccountActivity({
    required this.code,
    required this.name,
    required this.debit,
    required this.credit,
  });

  final String code;
  final String name;
  final double debit;
  final double credit;

  double get movement => debit + credit;
}

class FinancialOverviewEntry {
  const FinancialOverviewEntry({
    required this.date,
    required this.source,
    required this.sourceNumber,
    required this.description,
    required this.amount,
  });

  final DateTime date;
  final String source;
  final String sourceNumber;
  final String description;
  final double amount;
}

class FinancialOverviewSnapshot {
  const FinancialOverviewSnapshot({
    this.receipts = 0,
    this.payments = 0,
    this.salaryExpenses = 0,
    this.purchaseExpenses = 0,
    required this.from,
    required this.to,
    required this.cashBalance,
    required this.bankBalance,
    required this.customerReceivables,
    required this.customerCredits,
    required this.supplierPayables,
    required this.supplierAdvances,
    required this.payrollPayables,
    required this.revenue,
    required this.expenses,
    required this.collections,
    required this.supplierPayments,
    required this.payrollPayments,
    required this.periodDebit,
    required this.periodCredit,
    required this.integrityIssueCount,
    required this.topAccounts,
    required this.recentEntries,
  });

  final DateTime? from;
  final DateTime to;

  // As-of balances.
  final double cashBalance;
  final double bankBalance;
  final double customerReceivables;
  final double customerCredits;
  final double supplierPayables;
  final double supplierAdvances;
  final double payrollPayables;

  final double receipts, payments, salaryExpenses, purchaseExpenses;

  // Period activity.
  final double revenue;
  final double expenses;
  final double collections;
  final double supplierPayments;
  final double payrollPayments;
  final double periodDebit;
  final double periodCredit;

  final int? integrityIssueCount;
  final List<FinancialOverviewAccountActivity> topAccounts;
  final List<FinancialOverviewEntry> recentEntries;

  double get netProfit => revenue - expenses;
  double get liquidFunds => cashBalance + bankBalance;
  double get trialBalanceDifference => periodDebit - periodCredit;
  bool get periodBalanced => trialBalanceDifference.abs() < 0.005;
  bool? get accountingHealthy =>
      integrityIssueCount == null ? null : integrityIssueCount == 0;
}

class FinancialOverviewService {
  FinancialOverviewService._();

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double _money(double value) => double.parse(value.toStringAsFixed(2));

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _dayEnd(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  static String _periodWhere(
    List<Object?> args, {
    required DateTime? from,
    required DateTime to,
    String alias = 'e',
  }) {
    final where = <String>[];
    if (from != null) {
      where.add('substr($alias.date,1,10) >= substr(?,1,10)');
      args.add(_dayStart(from).toIso8601String());
    }
    where.add('substr($alias.date,1,10) <= substr(?,1,10)');
    args.add(_dayEnd(to).toIso8601String());
    return where.join(' AND ');
  }

  static Future<FinancialOverviewSnapshot> load({
    DateTime? from,
    DateTime? to,
    String query = '',
  }) async {
    final db = await DBService.database;
    return db
        .transaction((txn) => loadOn(txn, from: from, to: to, query: query));
  }

  static Future<FinancialOverviewSnapshot> loadOn(
    DatabaseExecutor db, {
    DateTime? from,
    DateTime? to,
    String query = '',
  }) async {
    final asOf = _dayEnd(to ?? DateTime.now());
    if (from != null && _dayStart(from).isAfter(asOf)) {
      throw ArgumentError('بداية الفترة بعد نهايتها');
    }

    final cashBalance = await _accountBalanceAsOf(
      db,
      codes: const ['1000'],
      asOf: asOf,
      creditNormal: false,
    );
    final bankBalance = await _accountBalanceAsOf(
      db,
      codes: const ['1010'],
      asOf: asOf,
      creditNormal: false,
    );
    final payrollPayables = await _payrollBalanceAsOf(db, asOf);

    final partyBalances = await _partyBalancesAsOf(db, asOf);
    final period = await _periodTotals(db, from: from, to: asOf);
    final moneyFlows = await _periodMoneyFlows(db, from: from, to: asOf);
    final cashFlows = await cashFlowsOn(db, from: from, to: asOf);
    final expenseRows = await accountTotalsOn(db, from: from, to: asOf);
    double expenseFor(String code) => expenseRows
        .where((r) =>
            r['code'] == code || r['code'].toString().startsWith('$code.'))
        .fold(0.0, (n, r) => n + _d(r['debit']) - _d(r['credit']));
    final topAccounts = await _topAccounts(
      db,
      from: from,
      to: asOf,
      query: query,
    );
    final recentEntries = await _recentEntries(
      db,
      from: from,
      to: asOf,
      query: query,
    );

    int? integrityIssueCount;
    try {
      final health = await AccountingIntegrityService.healthReportOn(db);
      final raw = health['issue_count'];
      if (raw is num) integrityIssueCount = raw.toInt();
    } catch (_) {
      // The overview itself remains available even if the diagnostic layer
      // cannot run against a legacy/incomplete database. Stage 1 databases
      // have this layer installed.
      integrityIssueCount = null;
    }

    return FinancialOverviewSnapshot(
      receipts: cashFlows.$1,
      payments: cashFlows.$2,
      salaryExpenses: expenseFor('5100'),
      purchaseExpenses: expenseFor('5005'),
      from: from == null ? null : _dayStart(from),
      to: asOf,
      cashBalance: _money(cashBalance),
      bankBalance: _money(bankBalance),
      customerReceivables: _money(partyBalances.customerReceivables),
      customerCredits: _money(partyBalances.customerCredits),
      supplierPayables: _money(partyBalances.supplierPayables),
      supplierAdvances: _money(partyBalances.supplierAdvances),
      payrollPayables: _money(payrollPayables),
      revenue: _money(period.revenue),
      expenses: _money(period.expenses),
      collections: _money(moneyFlows.collections),
      supplierPayments: _money(moneyFlows.supplierPayments),
      payrollPayments: _money(moneyFlows.payrollPayments),
      periodDebit: _money(period.debit),
      periodCredit: _money(period.credit),
      integrityIssueCount: integrityIssueCount,
      topAccounts: topAccounts,
      recentEntries: recentEntries,
    );
  }

  /// Common trial balance source. LEFT JOIN never sums out-of-period lines.
  static Future<List<Map<String, Object?>>> accountTotalsOn(DatabaseExecutor db,
      {DateTime? from, DateTime? to}) async {
    if (from != null &&
        _dayStart(from).isAfter(_dayStart(to ?? DateTime.now()))) {
      throw ArgumentError('بداية الفترة بعد نهايتها');
    }
    final args = <Object?>[];
    final where = _periodWhere(args, from: from, to: to ?? DateTime.now());
    return db.rawQuery("""
      SELECT a.id,a.code,a.name,a.type,
        COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.debit ELSE 0 END),0) debit,
        COALESCE(SUM(CASE WHEN e.id IS NOT NULL THEN l.credit ELSE 0 END),0) credit
      FROM accounts a LEFT JOIN gl_lines l ON l.account_id=a.id
      LEFT JOIN gl_entries e ON e.id=l.entry_id AND $where
      GROUP BY a.id,a.code,a.name,a.type ORDER BY a.code
    """, args);
  }

  /// Cash/bank flows are separate from revenue. Reversals reduce their original
  /// direction; opening balances and transfers within liquidity are excluded.
  static Future<(double, double)> cashFlowsOn(DatabaseExecutor db,
      {DateTime? from, DateTime? to, String? liquidityCode}) async {
    if (from != null &&
        _dayStart(from).isAfter(_dayStart(to ?? DateTime.now()))) {
      throw ArgumentError('بداية الفترة بعد نهايتها');
    }
    if (liquidityCode != null &&
        !const ['1000', '1010'].contains(liquidityCode)) {
      throw ArgumentError('حساب النقدية غير صالح');
    }
    String accountFilter(String alias) => liquidityCode == null
        ? "($alias.code IN ('1000','1010') OR $alias.code LIKE '1000.%' OR $alias.code LIKE '1010.%')"
        : "($alias.code='$liquidityCode' OR $alias.code LIKE '$liquidityCode.%')";
    final args = <Object?>[];
    final where = _periodWhere(args, from: from, to: to ?? DateTime.now());
    final rows = await db.rawQuery("""
      SELECT e.id, COALESCE(o.source,e.source) source,
        SUM(CASE WHEN ${accountFilter('a')} THEN l.debit-l.credit ELSE 0 END) net,
        (SELECT SUM(ol.debit-ol.credit) FROM gl_lines ol JOIN accounts oa ON oa.id=ol.account_id
          WHERE ol.entry_id=e.reversal_of AND ${accountFilter('oa')}) original_net
      FROM gl_entries e JOIN gl_lines l ON l.entry_id=e.id JOIN accounts a ON a.id=l.account_id
      LEFT JOIN gl_entries o ON o.id=e.reversal_of WHERE $where GROUP BY e.id
    """, args);
    double receipts = 0, payments = 0;
    for (final r in rows) {
      if (r['source'].toString().toUpperCase().startsWith('OPENING')) continue;
      final net = _d(r['net']), direction = _d(r['original_net'] ?? r['net']);
      if (direction > 0) {
        receipts += net;
      } else if (direction < 0) {
        payments -= net;
      }
    }
    return (_money(receipts), _money(payments));
  }

  static Future<double> _accountBalanceAsOf(
    DatabaseExecutor db, {
    required List<String> codes,
    required DateTime asOf,
    required bool creditNormal,
  }) async {
    final placeholders = List.filled(codes.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(l.debit),0) AS debit,
        COALESCE(SUM(l.credit),0) AS credit
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE (a.code IN ($placeholders) ${codes.map((_) => 'OR a.code LIKE ?').join(' ')})
        AND substr(e.date,1,10) <= substr(?,1,10)
    ''', <Object?>[
      ...codes,
      ...codes.map((c) => '$c.%'),
      asOf.toIso8601String()
    ]);
    if (rows.isEmpty) return 0.0;
    final debit = _d(rows.first['debit']);
    final credit = _d(rows.first['credit']);
    return creditNormal ? credit - debit : debit - credit;
  }

  static Future<double> _payrollBalanceAsOf(
    DatabaseExecutor db,
    DateTime asOf,
  ) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(l.credit-l.debit),0) AS balance
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE (a.code='2140' OR a.code LIKE '2140.%')
        AND substr(e.date,1,10) <= substr(?,1,10)
    ''', [asOf.toIso8601String()]);
    return rows.isEmpty ? 0.0 : _d(rows.first['balance']);
  }

  static Future<_PartyTotals> _partyBalancesAsOf(
    DatabaseExecutor db,
    DateTime asOf,
  ) async {
    final rows = await db.rawQuery('''
      SELECT
        v.party_role,
        v.canonical_party_id,
        CASE
          WHEN v.party_role='CUSTOMER' THEN SUM(v.debit-v.credit)
          WHEN v.party_role='SUPPLIER' THEN SUM(v.credit-v.debit)
          ELSE 0
        END AS balance
      FROM v_party_gl_lines v
      JOIN gl_entries e ON e.id=v.entry_id
      WHERE v.party_role IN ('CUSTOMER','SUPPLIER')
        AND v.canonical_party_id IS NOT NULL
        AND substr(e.date,1,10) <= substr(?,1,10)
      GROUP BY v.party_role, v.canonical_party_id
    ''', [asOf.toIso8601String()]);

    var customerReceivables = 0.0;
    var customerCredits = 0.0;
    var supplierPayables = 0.0;
    var supplierAdvances = 0.0;

    for (final row in rows) {
      final role = (row['party_role'] ?? '').toString();
      final balance = _d(row['balance']);
      if (role == 'CUSTOMER') {
        if (balance >= 0) {
          customerReceivables += balance;
        } else {
          customerCredits += -balance;
        }
      } else if (role == 'SUPPLIER') {
        if (balance >= 0) {
          supplierPayables += balance;
        } else {
          supplierAdvances += -balance;
        }
      }
    }

    return _PartyTotals(
      customerReceivables: customerReceivables,
      customerCredits: customerCredits,
      supplierPayables: supplierPayables,
      supplierAdvances: supplierAdvances,
    );
  }

  static Future<_PeriodTotals> _periodTotals(
    DatabaseExecutor db, {
    required DateTime? from,
    required DateTime to,
  }) async {
    final args = <Object?>[];
    final where = _periodWhere(args, from: from, to: to);
    final rows = await db.rawQuery('''
      SELECT
        a.type,
        a.code,
        COALESCE(SUM(l.debit),0) AS debit,
        COALESCE(SUM(l.credit),0) AS credit
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      JOIN accounts a ON a.id=l.account_id
      WHERE $where
      GROUP BY a.id, a.type, a.code
    ''', args);

    var debit = 0.0;
    var credit = 0.0;
    var revenue = 0.0;
    var expenses = 0.0;

    for (final row in rows) {
      final type = (row['type'] ?? '').toString().toUpperCase();
      final code = (row['code'] ?? '').toString();
      final d = _d(row['debit']);
      final c = _d(row['credit']);
      debit += d;
      credit += c;
      if (type == 'REVENUE' || code.startsWith('4')) {
        revenue += c - d;
      } else if (type == 'EXPENSE' || code.startsWith('5')) {
        expenses += d - c;
      }
    }

    return _PeriodTotals(
      debit: debit,
      credit: credit,
      revenue: revenue,
      expenses: expenses,
    );
  }

  static double _pairedMovement(double channel, double obligationRelief) {
    if (channel >= 0 && obligationRelief >= 0) {
      return math.min(channel, obligationRelief);
    }
    if (channel <= 0 && obligationRelief <= 0) {
      return -math.min(channel.abs(), obligationRelief.abs());
    }
    return 0.0;
  }

  static Future<_MoneyFlows> _periodMoneyFlows(
    DatabaseExecutor db, {
    required DateTime? from,
    required DateTime to,
  }) async {
    final args = <Object?>[];
    final where = _periodWhere(args, from: from, to: to);
    final rows = await db.rawQuery('''
      SELECT
        e.id,
        COALESCE(SUM(CASE
          WHEN a.code IN ('1000','1010','1020')
          THEN l.debit-l.credit ELSE 0 END),0) AS incoming_channel,
        COALESCE(SUM(CASE
          WHEN a.code IN ('1000','1010','1030')
          THEN l.credit-l.debit ELSE 0 END),0) AS outgoing_channel,
        COALESCE(SUM(CASE
          WHEN v.party_role='CUSTOMER'
          THEN v.credit-v.debit ELSE 0 END),0) AS customer_relief,
        COALESCE(SUM(CASE
          WHEN v.party_role='SUPPLIER'
          THEN v.debit-v.credit ELSE 0 END),0) AS supplier_relief,
        COALESCE(SUM(CASE
          WHEN (a.code='2140' OR a.code LIKE '2140.%')
               AND UPPER(COALESCE(l.party_type,''))='EMPLOYEE'
          THEN l.debit-l.credit ELSE 0 END),0) AS payroll_relief
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      JOIN accounts a ON a.id=l.account_id
      LEFT JOIN v_party_gl_lines v ON v.gl_line_id=l.id
      WHERE $where
      GROUP BY e.id
    ''', args);

    var collections = 0.0;
    var supplierPayments = 0.0;
    var payrollPayments = 0.0;
    for (final row in rows) {
      final incoming = _d(row['incoming_channel']);
      final outgoing = _d(row['outgoing_channel']);
      collections += _pairedMovement(incoming, _d(row['customer_relief']));
      supplierPayments += _pairedMovement(outgoing, _d(row['supplier_relief']));
      payrollPayments += _pairedMovement(outgoing, _d(row['payroll_relief']));
    }

    return _MoneyFlows(
      collections: collections,
      supplierPayments: supplierPayments,
      payrollPayments: payrollPayments,
    );
  }

  static Future<List<FinancialOverviewAccountActivity>> _topAccounts(
    DatabaseExecutor db, {
    required DateTime? from,
    required DateTime to,
    required String query,
  }) async {
    final args = <Object?>[];
    var where = _periodWhere(args, from: from, to: to);
    final q = query.trim();
    if (q.isNotEmpty) {
      where += ' AND (LOWER(a.name) LIKE LOWER(?) OR a.code LIKE ?)';
      args.addAll(['%$q%', '%$q%']);
    }
    final rows = await db.rawQuery('''
      SELECT
        a.code,
        a.name,
        COALESCE(SUM(l.debit),0) AS debit,
        COALESCE(SUM(l.credit),0) AS credit
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      JOIN accounts a ON a.id=l.account_id
      WHERE $where
      GROUP BY a.id, a.code, a.name
      ORDER BY SUM(l.debit+l.credit) DESC, a.code ASC
      LIMIT 8
    ''', args);

    return rows
        .map(
          (row) => FinancialOverviewAccountActivity(
            code: (row['code'] ?? '').toString(),
            name: (row['name'] ?? '').toString(),
            debit: _money(_d(row['debit'])),
            credit: _money(_d(row['credit'])),
          ),
        )
        .toList(growable: false);
  }

  static Future<List<FinancialOverviewEntry>> _recentEntries(
    DatabaseExecutor db, {
    required DateTime? from,
    required DateTime to,
    required String query,
  }) async {
    final args = <Object?>[];
    var where = _periodWhere(args, from: from, to: to);
    final q = query.trim();
    if (q.isNotEmpty) {
      where += ''' AND (
        LOWER(COALESCE(e.note,'')) LIKE LOWER(?)
        OR LOWER(COALESCE(e.source,'')) LIKE LOWER(?)
        OR LOWER(COALESCE(e.source_number,'')) LIKE LOWER(?)
        OR EXISTS(
          SELECT 1
          FROM gl_lines ql
          JOIN accounts qa ON qa.id=ql.account_id
          WHERE ql.entry_id=e.id
            AND (LOWER(qa.name) LIKE LOWER(?) OR qa.code LIKE ?)
        )
      )''';
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
    }

    final rows = await db.rawQuery('''
      SELECT
        e.date,
        e.source,
        e.source_number,
        e.note,
        COALESCE(SUM(l.debit),0) AS amount
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id=e.id
      WHERE $where
      GROUP BY e.id, e.date, e.source, e.source_number, e.note
      ORDER BY e.date DESC, e.id DESC
      LIMIT 20
    ''', args);

    return rows
        .map(
          (row) => FinancialOverviewEntry(
            date: DateTime.tryParse(row['date']?.toString() ?? '') ??
                DateTime(1970, 1, 1),
            source: (row['source'] ?? '').toString(),
            sourceNumber: (row['source_number'] ?? '').toString().trim(),
            description: (row['note'] ?? '').toString().trim(),
            amount: _money(_d(row['amount'])),
          ),
        )
        .toList(growable: false);
  }
}

class _PartyTotals {
  const _PartyTotals({
    required this.customerReceivables,
    required this.customerCredits,
    required this.supplierPayables,
    required this.supplierAdvances,
  });

  final double customerReceivables;
  final double customerCredits;
  final double supplierPayables;
  final double supplierAdvances;
}

class _PeriodTotals {
  const _PeriodTotals({
    required this.debit,
    required this.credit,
    required this.revenue,
    required this.expenses,
  });

  final double debit;
  final double credit;
  final double revenue;
  final double expenses;
}

class _MoneyFlows {
  const _MoneyFlows({
    required this.collections,
    required this.supplierPayments,
    required this.payrollPayments,
  });

  final double collections;
  final double supplierPayments;
  final double payrollPayments;
}
