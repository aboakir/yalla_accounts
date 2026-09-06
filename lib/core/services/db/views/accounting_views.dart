import 'package:sqflite/sqflite.dart';

class AccountingViews {
  // Legacy views remain for backward compatibility only. P10 canonical reads
  // below no longer depend on invoice-minus-payments balance math.
  static Future<void> createAllViews(DatabaseExecutor db) async {
    await _createClientARViews(db);
  }

  static Future<void> _createClientARViews(DatabaseExecutor db) async {
    await db.execute('DROP VIEW IF EXISTS v_client_ar;');
    await db.execute('DROP VIEW IF EXISTS v_client_payments_total_unified;');
    await db.execute('DROP VIEW IF EXISTS v_client_invoices_total;');

    await db.execute('''
      CREATE VIEW v_client_invoices_total AS
      SELECT client_id, IFNULL(SUM(total),0) AS invoices_total
      FROM invoices
      GROUP BY client_id;
    ''');

    await db.execute('''
      CREATE VIEW v_client_payments_total_unified AS
      SELECT client_id, IFNULL(SUM(amount),0) AS payments_total
      FROM payments
      WHERE client_id IS NOT NULL
      GROUP BY client_id;
    ''');

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

  /// P10 canonical customer AR. balance_due comes from GL. The invoice/payment
  /// totals are compatibility information for the current UI and are not used
  /// to calculate the balance.
  static Future<List<Map<String, dynamic>>> getClientAR(
      DatabaseExecutor db) async {
    return db.rawQuery('''
      WITH gl_ar AS (
        SELECT client_id, COALESCE(SUM(delta),0) AS balance_due
        FROM (
          SELECT
            COALESCE(
              CASE
                WHEN UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
                THEN CAST(l.party_id AS INTEGER)
              END,
              c.id
            ) AS client_id,
            (l.debit-l.credit) AS delta
          FROM gl_lines l
          LEFT JOIN accounts a ON a.id=l.account_id
          LEFT JOIN clients c ON c.account_id=l.account_id
          WHERE
            a.code LIKE '1200.C%'
            OR c.id IS NOT NULL
            OR UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
        ) x
        WHERE client_id IS NOT NULL
        GROUP BY client_id
      ),
      inv AS (
        SELECT client_id, COALESCE(SUM(total),0) AS invoices_total
        FROM invoices
        WHERE client_id IS NOT NULL
        GROUP BY client_id
      ),
      pay AS (
        SELECT client_id, COALESCE(SUM(amount),0) AS payments_total
        FROM payments
        WHERE client_id IS NOT NULL AND COALESCE(isIncome,1)=1
        GROUP BY client_id
      )
      SELECT
        c.id AS client_id,
        c.name AS client_name,
        COALESCE(inv.invoices_total,0) AS invoices_total,
        COALESCE(pay.payments_total,0) AS payments_total,
        COALESCE(gl_ar.balance_due,0) AS balance_due
      FROM clients c
      LEFT JOIN inv ON inv.client_id=c.id
      LEFT JOIN pay ON pay.client_id=c.id
      LEFT JOIN gl_ar ON gl_ar.client_id=c.id
      ORDER BY balance_due DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getAgingReport(
      DatabaseExecutor db) async {
    return db.rawQuery('''
      WITH ar AS (
        SELECT
          COALESCE(
            CASE
              WHEN UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
              THEN CAST(l.party_id AS INTEGER)
            END,
            c.id
          ) AS client_id,
          e.date AS date,
          (l.debit-l.credit) AS delta
        FROM gl_lines l
        JOIN gl_entries e ON e.id=l.entry_id
        LEFT JOIN clients c ON c.account_id=l.account_id
        LEFT JOIN accounts a ON a.id=l.account_id
        WHERE
          a.code LIKE '1200.C%'
          OR c.id IS NOT NULL
          OR UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
      )
      SELECT
        c.id,
        c.name,
        COALESCE(SUM(ar.delta),0) AS balance,
        MAX(ar.date) AS latest_invoice_date
      FROM clients c
      LEFT JOIN ar ON ar.client_id=c.id
      GROUP BY c.id, c.name
      HAVING balance > 0.005
      ORDER BY balance DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getTrialBalance(
      DatabaseExecutor db, DateTime date) async {
    return db.rawQuery('''
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
