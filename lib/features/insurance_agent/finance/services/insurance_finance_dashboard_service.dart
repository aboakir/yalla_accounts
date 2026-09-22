import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

class InsuranceFinancePolicyRow {
  const InsuranceFinancePolicyRow({
    required this.policyId,
    required this.documentNumber,
    required this.policyNumber,
    required this.insuredName,
    required this.companyName,
    required this.sale,
    required this.customerReceipts,
    required this.customerRefunds,
    required this.insurerPayable,
    required this.insurerPayments,
  });

  final String policyId;
  final String documentNumber;
  final String policyNumber;
  final String insuredName;
  final String companyName;
  final double sale;
  final double customerReceipts;
  final double customerRefunds;
  final double insurerPayable;
  final double insurerPayments;

  double get customerOutstanding => InsurancePricingEngine.money(
        sale - customerReceipts + customerRefunds,
      );
  double get insurerOutstanding =>
      InsurancePricingEngine.money(insurerPayable - insurerPayments);
}

class InsuranceFinanceTransactionRow {
  const InsuranceFinanceTransactionRow({
    required this.id,
    required this.direction,
    required this.amount,
    required this.currency,
    required this.createdAt,
    required this.documentNumber,
    required this.policyNumber,
    required this.insuredName,
    required this.companyName,
    this.receiptNumber,
    this.voucherId,
  });

  final String id;
  final String direction;
  final double amount;
  final String currency;
  final DateTime createdAt;
  final String documentNumber;
  final String policyNumber;
  final String insuredName;
  final String companyName;
  final int? receiptNumber;
  final String? voucherId;
}

class InsuranceFinanceDashboardService {
  InsuranceFinanceDashboardService._();

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static double _money(Object? value) => InsurancePricingEngine.money(
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0,
      );

  static Future<List<InsuranceFinancePolicyRow>> policyBalances({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      SELECT p.id,
             COALESCE(NULLIF(TRIM(p.document_number),''),p.id) document_number,
             COALESCE(p.policy_number,'') policy_number,
             COALESCE(p.insured_name,'') insured_name,
             COALESCE(c.name,p.company_name,'') company_name,
             COALESCE(p.net_sale_amount,0) sale,
             COALESCE(p.net_insurer_payable,0) payable,
             COALESCE(SUM(CASE WHEN pp.status='POSTED' AND pp.direction='CUSTOMER_RECEIPT' THEN pp.amount ELSE 0 END),0) receipts,
             COALESCE(SUM(CASE WHEN pp.status='POSTED' AND pp.direction='REFUND' THEN pp.amount ELSE 0 END),0) refunds,
             COALESCE(SUM(CASE WHEN pp.status='POSTED' AND pp.direction='INSURER_PAYMENT' THEN pp.amount ELSE 0 END),0) insurer_payments
      FROM insurance_policies p
      LEFT JOIN insurance_companies c
        ON CAST(c.id AS TEXT)=CAST(p.insurance_company_id AS TEXT)
      LEFT JOIN insurance_policy_payments pp ON pp.policy_id=p.id
      WHERE p.posting_status='POSTED' AND p.reversed_at IS NULL
      GROUP BY p.id
      ORDER BY p.posted_at DESC,p.created_at DESC
    ''');
    return rows
        .map(
          (row) => InsuranceFinancePolicyRow(
            policyId: '${row['id']}',
            documentNumber: '${row['document_number']}',
            policyNumber: '${row['policy_number']}',
            insuredName: '${row['insured_name']}',
            companyName: '${row['company_name']}',
            sale: _money(row['sale']),
            customerReceipts: _money(row['receipts']),
            customerRefunds: _money(row['refunds']),
            insurerPayable: _money(row['payable']),
            insurerPayments: _money(row['insurer_payments']),
          ),
        )
        .toList(growable: false);
  }

  static Future<List<InsuranceFinanceTransactionRow>> recentTransactions({
    int limit = 50,
    DatabaseExecutor? executor,
  }) async {
    if (limit <= 0 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 500.');
    }
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      SELECT pp.id,pp.direction,pp.amount,pp.currency,pp.created_at,
             pp.receipt_number,pp.voucher_id,
             COALESCE(NULLIF(TRIM(p.document_number),''),p.id) document_number,
             COALESCE(p.policy_number,'') policy_number,
             COALESCE(p.insured_name,'') insured_name,
             COALESCE(c.name,p.company_name,'') company_name
      FROM insurance_policy_payments pp
      JOIN insurance_policies p ON p.id=pp.policy_id
      LEFT JOIN insurance_companies c
        ON CAST(c.id AS TEXT)=CAST(p.insurance_company_id AS TEXT)
      WHERE pp.status='POSTED'
      ORDER BY pp.created_at DESC,pp.id DESC
      LIMIT ?
    ''', [limit]);
    return rows
        .map(
          (row) => InsuranceFinanceTransactionRow(
            id: '${row['id']}',
            direction: '${row['direction']}',
            amount: _money(row['amount']),
            currency: '${row['currency']}',
            createdAt: DateTime.tryParse('${row['created_at']}') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            documentNumber: '${row['document_number']}',
            policyNumber: '${row['policy_number']}',
            insuredName: '${row['insured_name']}',
            companyName: '${row['company_name']}',
            receiptNumber: (row['receipt_number'] as num?)?.toInt(),
            voucherId: row['voucher_id']?.toString(),
          ),
        )
        .toList(growable: false);
  }
}
