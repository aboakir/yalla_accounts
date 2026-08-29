// 📁 lib/core/services/db/views/accounting_views.dart
import 'package:sqflite/sqflite.dart';

class AccountingViews {
  // 👀 إنشاء المشاهد المحاسبية
  static Future<void> createAllViews(DatabaseExecutor db) async {
    await _createClientARViews(db);
  }

  // 👥 مشاهد حسابات العملاء
  static Future<void> _createClientARViews(DatabaseExecutor db) async {
    await db.execute('DROP VIEW IF EXISTS v_client_ar;');
    await db.execute('DROP VIEW IF EXISTS v_client_payments_total_unified;');
    await db.execute('DROP VIEW IF EXISTS v_client_invoices_total;');

    // إجمالي الفواتير لكل عميل
    await db.execute('''
      CREATE VIEW v_client_invoices_total AS
      SELECT client_id, IFNULL(SUM(total),0) AS invoices_total
      FROM invoices
      GROUP BY client_id;
    ''');

    // إجمالي المدفوعات لكل عميل
    await db.execute('''
      CREATE VIEW v_client_payments_total_unified AS
      SELECT client_id, IFNULL(SUM(amount),0) AS payments_total
      FROM payments
      WHERE client_id IS NOT NULL
      GROUP BY client_id;
    ''');

    // رصيد حسابات العملاء
    await db.execute('''
      CREATE VIEW v_client_ar AS
      SELECT
        c.id AS client_id,
        c.name AS client_name,
        IFNULL(i.invoices_total,0) AS invoices_total,
        IFNULL(p.payments_total,0) AS payments_total,
        (IFNULL(i.invoices_total,0) - IFNULL(p.payments_total,0)) AS balance_due
      FROM clients c
      LEFT JOIN v_client_invoices_total i ON i.client_id = c.id
      LEFT JOIN v_client_payments_total_unified p ON p.client_id = c.id;
    ''');
  }

  // 🎯 استخدام المشاهد
  static Future<List<Map<String, dynamic>>> getClientAR(
      DatabaseExecutor db) async {
    return await db.rawQuery('''
      SELECT * FROM v_client_ar 
      WHERE balance_due > 0 
      ORDER BY balance_due DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getAgingReport(
      DatabaseExecutor db) async {
    return await db.rawQuery('''
      SELECT 
        c.id,
        c.name,
        i.invoices_total,
        p.payments_total,
        (i.invoices_total - p.payments_total) as balance,
        MAX(i.latest_invoice_date) as latest_invoice_date
      FROM clients c
      LEFT JOIN (
        SELECT client_id, SUM(total) as invoices_total, MAX(date) as latest_invoice_date
        FROM invoices 
        GROUP BY client_id
      ) i ON i.client_id = c.id
      LEFT JOIN (
        SELECT client_id, SUM(amount) as payments_total
        FROM payments 
        GROUP BY client_id
      ) p ON p.client_id = c.id
      WHERE (i.invoices_total - p.payments_total) > 0
      ORDER BY balance DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getTrialBalance(
      DatabaseExecutor db, DateTime date) async {
    return await db.rawQuery('''
      SELECT 
        a.id,
        a.code,
        a.name,
        a.type,
        COALESCE(SUM(gl.debit), 0) as total_debit,
        COALESCE(SUM(gl.credit), 0) as total_credit,
        CASE 
          WHEN a.normal_balance = 'DEBIT' THEN COALESCE(SUM(gl.debit), 0) - COALESCE(SUM(gl.credit), 0)
          ELSE COALESCE(SUM(gl.credit), 0) - COALESCE(SUM(gl.debit), 0)
        END as balance
      FROM accounts a
      LEFT JOIN gl_lines gl ON gl.account_id = a.id
      LEFT JOIN gl_entries ge ON ge.id = gl.entry_id
      WHERE ge.date <= ?
      GROUP BY a.id, a.code, a.name, a.type, a.normal_balance
      HAVING balance != 0
      ORDER BY a.code
    ''', [date.toIso8601String()]);
  }
}
