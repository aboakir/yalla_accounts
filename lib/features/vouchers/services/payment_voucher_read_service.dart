import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
import 'package:yalla_accounts/features/employees/services/payroll_database_service.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

class PaymentVoucherReadService {
  PaymentVoucherReadService._();

  static Future<List<Map<String, dynamic>>> activeEmployees({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery(r'''
      SELECT id, full_name AS name
      FROM employees
      WHERE LOWER(TRIM(COALESCE(status, 'active'))) IN ('active', 'نشط')
      ORDER BY full_name ASC
    ''');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<List<Map<String, dynamic>>> openInvoicesForSupplier(
    int supplierId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final paid = PurchaseBalanceSql.paid('pi.id');
    final rows = await db.rawQuery('''
      SELECT
        pi.id,
        pi.date,
        pi.amount_total,
        $paid AS paid_total,
        (pi.amount_total - $paid) AS remaining,
        pi.supplier_id,
        s.name AS supplier_name
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      WHERE pi.supplier_id = ?
        AND UPPER(COALESCE(pi.status, '')) NOT IN ('PAID','VOID','CANCELLED','REVERSED')
        AND (pi.amount_total - $paid) > 0.005
      ORDER BY pi.date DESC, pi.id DESC
    ''', [supplierId]);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<PartyBalanceSummary?> supplierBalance(
    int supplierId, {
    DatabaseExecutor? executor,
  }) async {
    final balances = await PartyFinancialService.balances(executor: executor);
    final id = supplierId.toString();
    for (final balance in balances) {
      if (balance.supplierLegacyId == id) return balance;
    }
    return null;
  }

  static Future<List<PayrollRun>> openPayrollForEmployee(
    String employeeId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.query(
      'payroll_runs',
      where:
          "employee_id=? AND UPPER(COALESCE(status,'ACCRUED')) <> 'REVERSED' AND amount_paid < net - 0.005",
      whereArgs: [employeeId],
      orderBy: 'period_start DESC, id DESC',
    );
    return rows.map(PayrollRun.fromMap).toList(growable: false);
  }
}
