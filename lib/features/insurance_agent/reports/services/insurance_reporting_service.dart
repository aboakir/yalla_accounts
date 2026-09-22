import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

class InsuranceReportingSnapshot {
  const InsuranceReportingSnapshot({
    required this.postedPolicies,
    required this.activePolicies,
    required this.expiring30,
    required this.openClaims,
    required this.sales,
    required this.insurerPayable,
    required this.grossProfit,
    required this.commission,
    required this.customerReceipts,
    required this.refunds,
    required this.insurerPayments,
  });

  final int postedPolicies;
  final int activePolicies;
  final int expiring30;
  final int openClaims;
  final double sales;
  final double insurerPayable;
  final double grossProfit;
  final double commission;
  final double customerReceipts;
  final double refunds;
  final double insurerPayments;

  double get customerOutstanding =>
      InsurancePricingEngine.money(sales - customerReceipts + refunds);
  double get insurerOutstanding =>
      InsurancePricingEngine.money(insurerPayable - insurerPayments);
}

class InsuranceCompanyBalanceRow {
  const InsuranceCompanyBalanceRow({
    required this.companyId,
    required this.companyName,
    required this.policyCount,
    required this.sales,
    required this.payable,
    required this.profit,
    required this.customerReceipts,
    required this.customerRefunds,
    required this.insurerPayments,
  });

  final int companyId;
  final String companyName;
  final int policyCount;
  final double sales;
  final double payable;
  final double profit;
  final double customerReceipts;
  final double customerRefunds;
  final double insurerPayments;

  double get customerOutstanding => InsurancePricingEngine.money(
        sales - customerReceipts + customerRefunds,
      );
  double get insurerOutstanding =>
      InsurancePricingEngine.money(payable - insurerPayments);
}

class InsuranceReportingService {
  InsuranceReportingService._();

  static double _n(Object? value) =>
      InsurancePricingEngine.money((value as num?)?.toDouble() ?? 0);

  static int _i(Object? value) => (value as num?)?.toInt() ?? 0;

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static Future<InsuranceReportingSnapshot> snapshot({
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final now = asOf ?? DateTime.now();
    final nowIso = now.toIso8601String();
    final soonIso = now.add(const Duration(days: 30)).toIso8601String();
    final policyRows = await db.rawQuery('''
      SELECT COUNT(*) posted_count,
             COALESCE(SUM(net_sale_amount),0) sales,
             COALESCE(SUM(net_insurer_payable),0) payable,
             COALESCE(SUM(gross_profit),0) profit,
             COALESCE(SUM(commission_amount),0) commission,
             COALESCE(SUM(CASE WHEN start_date<=? AND end_date>=? THEN 1 ELSE 0 END),0) active_count,
             COALESCE(SUM(CASE WHEN end_date>=? AND end_date<=? THEN 1 ELSE 0 END),0) expiring_count
      FROM insurance_policies
      WHERE posting_status='POSTED' AND reversed_at IS NULL
    ''', [nowIso, nowIso, nowIso, soonIso]);
    final policy = policyRows.single;

    final paymentRows = await db.rawQuery('''
      SELECT direction, COALESCE(SUM(amount),0) total
      FROM insurance_policy_payments
      WHERE status='POSTED'
      GROUP BY direction
    ''');
    double receipts = 0;
    double refunds = 0;
    double insurerPayments = 0;
    for (final row in paymentRows) {
      final total = _n(row['total']);
      switch (row['direction']) {
        case 'CUSTOMER_RECEIPT':
          receipts += total;
        case 'REFUND':
          refunds += total;
        case 'INSURER_PAYMENT':
          insurerPayments += total;
      }
    }

    final claimRows = await db.rawQuery('''
      SELECT COUNT(*) total
      FROM insurance_claims
      WHERE status NOT IN ('CLOSED','REJECTED')
    ''');

    return InsuranceReportingSnapshot(
      postedPolicies: _i(policy['posted_count']),
      activePolicies: _i(policy['active_count']),
      expiring30: _i(policy['expiring_count']),
      openClaims: _i(claimRows.single['total']),
      sales: _n(policy['sales']),
      insurerPayable: _n(policy['payable']),
      grossProfit: _n(policy['profit']),
      commission: _n(policy['commission']),
      customerReceipts: InsurancePricingEngine.money(receipts),
      refunds: InsurancePricingEngine.money(refunds),
      insurerPayments: InsurancePricingEngine.money(insurerPayments),
    );
  }

  static Future<List<InsuranceCompanyBalanceRow>> companyBalances({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      SELECT c.id company_id,
             c.name company_name,
             COUNT(p.id) policy_count,
             COALESCE(SUM(p.net_sale_amount),0) sales,
             COALESCE(SUM(p.net_insurer_payable),0) payable,
             COALESCE(SUM(p.gross_profit),0) profit,
             COALESCE((SELECT SUM(pp.amount)
               FROM insurance_policy_payments pp
               JOIN insurance_policies px ON px.id=pp.policy_id
               WHERE px.insurance_company_id=c.id
                 AND pp.direction='CUSTOMER_RECEIPT'
                 AND pp.status='POSTED'),0) receipts,
             COALESCE((SELECT SUM(pp.amount)
               FROM insurance_policy_payments pp
               JOIN insurance_policies px ON px.id=pp.policy_id
               WHERE px.insurance_company_id=c.id
                 AND pp.direction='REFUND'
                 AND pp.status='POSTED'),0) refunds,
             COALESCE((SELECT SUM(pp.amount)
               FROM insurance_policy_payments pp
               JOIN insurance_policies px ON px.id=pp.policy_id
               WHERE px.insurance_company_id=c.id
                 AND pp.direction='INSURER_PAYMENT'
                 AND pp.status='POSTED'),0) insurer_payments
      FROM insurance_companies c
      LEFT JOIN insurance_policies p
        ON p.insurance_company_id=c.id
       AND p.posting_status='POSTED'
       AND p.reversed_at IS NULL
      GROUP BY c.id,c.name
      HAVING COUNT(p.id)>0
      ORDER BY payable DESC, company_name ASC
    ''');
    return rows
        .map(
          (row) => InsuranceCompanyBalanceRow(
            companyId: _i(row['company_id']),
            companyName: (row['company_name'] ?? '').toString(),
            policyCount: _i(row['policy_count']),
            sales: _n(row['sales']),
            payable: _n(row['payable']),
            profit: _n(row['profit']),
            customerReceipts: _n(row['receipts']),
            customerRefunds: _n(row['refunds']),
            insurerPayments: _n(row['insurer_payments']),
          ),
        )
        .toList(growable: false);
  }
}
