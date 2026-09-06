import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/financial_models.dart';

class FinanceService {
  FinanceService._();

  // ---------- Helpers ----------
  static Future<Database> _db() async => DBService.database;

  static Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<double> _sum(Database db, String sql,
      [List<Object?> args = const []]) async {
    final r = await db.rawQuery(sql, args);
    return r.isNotEmpty
        ? (r.first.values.first as num?)?.toDouble() ?? 0.0
        : 0.0;
  }

  // ---------- KPI (اختياري مبسّط) ----------
  static Future<DashboardStats> getDashboardStats() async {
    final db = await _db();
    final hasInvoices = await _tableExists(db, 'invoices');
    final hasLedger = await _tableExists(db, 'ledger_entries');
    final hasGl = await _tableExists(db, 'gl_lines') &&
        await _tableExists(db, 'accounts');

    final totalRevenue = hasGl
        ? await _sum(db, '''
            SELECT COALESCE(SUM(l.credit-l.debit),0)
            FROM gl_lines l
            JOIN accounts a ON a.id=l.account_id
            WHERE a.code='4000'
          ''')
        : hasInvoices
            ? await _sum(db, 'SELECT IFNULL(SUM(total),0) FROM invoices')
            : 0.0;

    double totalExpenses = 0.0;
    if (hasLedger) {
      // بما إنه ما في debit/credit عمودين مستقلين: ما بنقدر نطلع صافي شامل هنا بدقة.
      // خليها 0 مؤقتًا (بدون بيانات وهمية).
      totalExpenses = 0.0;
    }

    return DashboardStats(
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      netIncome: totalRevenue - totalExpenses,
      totalAssets: 0.0,
      totalLiabilities: 0.0,
    );
  }

  // ---------- الميزانية ----------
  static Future<BalanceSheet> getBalanceSheet() async {
    return BalanceSheet(
      assets: const [],
      liabilities: const [],
      totalAssets: 0.0,
      totalLiabilities: 0.0,
      equity: 0.0,
    );
  }

  // ---------- قائمة الدخل ----------
  static Future<IncomeStatement> getIncomeStatement() async {
    final db = await _db();

    // أسماء حسابات المصروفات التاريخية الشائعة.
    const expenseAccounts = [
      'المصروفات',
      'مصروفات',
      'مصروف',
      'Expense',
      'Expenses',
      'COGS',
      'Cost of Goods Sold',
      'تكلفة المبيعات',
      'تكاليف',
    ];

    // ----- الإيرادات -----
    // P10 source of truth: recognized revenue comes from the immutable GL
    // revenue account. Invoices/repairs are compatibility fallbacks only for
    // legacy databases that have no GL yet.
    double totalRevenues = 0.0;

    if (await _tableExists(db, 'gl_lines') &&
        await _tableExists(db, 'gl_entries') &&
        await _tableExists(db, 'accounts')) {
      totalRevenues = await _sum(
        db,
        '''
        SELECT COALESCE(SUM(l.credit-l.debit),0) AS v
        FROM gl_lines l
        JOIN accounts a ON a.id=l.account_id
        WHERE a.code='4000'
        ''',
      );
    }

    if (totalRevenues.abs() <= 0.000001 && await _tableExists(db, 'invoices')) {
      totalRevenues =
          await _sum(db, 'SELECT IFNULL(SUM(total),0) FROM invoices');
    }

    if (totalRevenues.abs() <= 0.000001 && await _tableExists(db, 'repairs')) {
      totalRevenues =
          await _sum(db, 'SELECT IFNULL(SUM(fileValue),0) FROM repairs');
    }

    // ----- المصروفات -----
    double totalExpenses = 0.0;
    if (await _tableExists(db, 'ledger_entries')) {
      final placeholders = List.filled(expenseAccounts.length, '?').join(',');
      totalExpenses = await _sum(
        db,
        '''
        SELECT IFNULL(SUM(amount),0) AS v
        FROM ledger_entries
        WHERE debit_account IN ($placeholders)
        ''',
        expenseAccounts,
      );
    }

    final revenuesItems = <IncomeItem>[
      if (totalRevenues > 0)
        IncomeItem(name: 'إيرادات التشغيل', amount: totalRevenues),
    ];
    final expensesItems = <IncomeItem>[
      if (totalExpenses > 0) IncomeItem(name: 'مصروفات', amount: totalExpenses),
    ];

    return IncomeStatement(
      revenues: revenuesItems,
      expenses: expensesItems,
      totalRevenues: totalRevenues,
      totalExpenses: totalExpenses,
      netProfit: totalRevenues - totalExpenses,
    );
  }

  // ---------- قيود اليومية ----------
  static Future<List<JournalEntry>> getJournalEntries() async {
    final db = await _db();
    if (!await _tableExists(db, 'ledger_entries')) return [];

    final rows =
        await db.query('ledger_entries', orderBy: 'date DESC, id DESC');

    // ملاحظة: نموذج JournalEntry عندك يجب أن يدعم الحقول التالية
    // (عدّل التعيين إذا كان النموذج مختلفاً).
    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final date =
          DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now();
      final desc = (m['description'] ?? '').toString();
      final dAcc = (m['debit_account'] ?? '').toString();
      final cAcc = (m['credit_account'] ?? '').toString();
      final amt = (m['amount'] as num?)?.toDouble() ?? 0.0;

      return JournalEntry(
        id: id,
        date: date,
        description: desc,
        account: dAcc.isNotEmpty ? dAcc : cAcc,
        debit: dAcc.isNotEmpty ? amt : 0.0,
        credit: cAcc.isNotEmpty ? amt : 0.0,
      );
    }).toList();
  }

  // ---------- دفتر الأستاذ (اختياري مبسّط برصيد تراكمي لكل اسم حساب) ----------
  static Future<List<LedgerEntry>> getLedgerEntries() async {
    final db = await _db();
    if (!await _tableExists(db, 'ledger_entries')) return [];

    final rows = await db.query('ledger_entries', orderBy: 'date ASC, id ASC');

    final Map<String, double> running = {};
    final List<LedgerEntry> out = [];

    for (final m in rows) {
      final id = (m['id'] ?? '').toString();
      final date =
          DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now();
      final desc = (m['description'] ?? '').toString();
      final dAcc = (m['debit_account'] ?? '').toString();
      final cAcc = (m['credit_account'] ?? '').toString();
      final amt = (m['amount'] as num?)?.toDouble() ?? 0.0;

      // نختار اسم الحساب الأساسي لعرض الرصيد (حسب جهة القيد)
      final acct = dAcc.isNotEmpty ? dAcc : cAcc;
      final prev = running[acct] ?? 0.0;
      final bal = prev + (dAcc.isNotEmpty ? amt : -amt);
      running[acct] = bal;

      out.add(
        // ملاحظة: هذا الكلاس يختلف عن نموذج ledger_entries في DB؛ هذا هو
        // LedgerEntry من financial_models.dart (ليس موديل DB).
        LedgerEntry(
          id: id,
          date: date,
          account: acct,
          description: desc,
          debit: dAcc.isNotEmpty ? amt : 0.0,
          credit: cAcc.isNotEmpty ? amt : 0.0,
          balance: bal,
        ),
      );
    }

    return out;
  }

  // ---------- المدفوعات ----------
  static Future<List<PaymentEntry>> getPayments() async {
    final db = await _db();
    if (!await _tableExists(db, 'payments')) return [];

    final hasInvoices = await _tableExists(db, 'invoices');
    List<Map<String, Object?>> rows;

    if (hasInvoices) {
      rows = await db.rawQuery('''
        SELECT 
          p.id       AS id,
          p.date     AS date,
          p.amount   AS amount,
          p.method   AS method,
          i.party_id AS payee
        FROM payments p
        LEFT JOIN invoices i ON i.id = p.invoice_id
        ORDER BY p.date DESC, p.id DESC
      ''');
    } else {
      rows = await db.query('payments', orderBy: 'date DESC');
    }

    return rows.map((m) {
      final id = (m['id'] ?? '').toString();
      final date =
          DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now();
      final amt = (m['amount'] as num?)?.toDouble() ?? 0.0;
      final method = (m['method'] ?? '').toString();
      final payee = (m['payee'] ?? '').toString();

      return PaymentEntry(
        id: id,
        date: date,
        payee: payee,
        amount: amt,
        method: method.isEmpty ? '—' : method,
      );
    }).toList();
  }

  // ---------- الضرائب (مبسّط) ----------
  static Future<TaxReport> getTaxReport() async {
    final db = await _db();
    final taxableIncome = await _tableExists(db, 'invoices')
        ? await _sum(db, 'SELECT IFNULL(SUM(total),0) FROM invoices')
        : 0.0;

    const rate = 0.0; // لا يوجد إعداد ضريبة حالياً
    return TaxReport(
      taxableIncome: taxableIncome,
      taxRate: rate,
      taxDue: taxableIncome * rate,
    );
  }
}
