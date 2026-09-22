import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

double _amount(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

class InsuranceDashboardSummary {
  const InsuranceDashboardSummary({
    required this.activePolicies,
    required this.expiringSoon,
    required this.openClaims,
    required this.totalSales,
    required this.totalCost,
    required this.grossProfit,
    required this.customerReceivable,
    required this.insurerPayable,
  });
  final int activePolicies;
  final int expiringSoon;
  final int openClaims;
  final double totalSales;
  final double totalCost;
  final double grossProfit;
  final double customerReceivable;
  final double insurerPayable;
}

class InsurancePolicyOverview {
  const InsurancePolicyOverview({
    required this.id,
    required this.number,
    required this.insuredName,
    required this.vehicle,
    required this.company,
    required this.endDate,
    required this.sale,
    required this.status,
  });
  final String id;
  final String number;
  final String insuredName;
  final String vehicle;
  final String company;
  final DateTime endDate;
  final double sale;
  final String status;
}

class InsuranceCompanyBalance {
  const InsuranceCompanyBalance({
    required this.id,
    required this.name,
    required this.policyCount,
    required this.payable,
    required this.paid,
  });
  final int id;
  final String name;
  final int policyCount;
  final double payable;
  final double paid;
  double get outstanding => payable - paid;
}

class InsuranceProducerPortfolio {
  const InsuranceProducerPortfolio({
    required this.partyId,
    required this.name,
    required this.policyCount,
    required this.sales,
    required this.commission,
  });
  final String partyId;
  final String name;
  final int policyCount;
  final double sales;
  final double commission;
}

class InsuranceDashboardService {
  InsuranceDashboardService._();

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static Future<InsuranceDashboardSummary> summary({
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final day = (asOf ?? DateTime.now()).toIso8601String().substring(0, 10);
    final row = (await db.rawQuery('''
      SELECT
        SUM(CASE WHEN posting_status='POSTED'
                  AND UPPER(COALESCE(status,'ACTIVE')) NOT IN ('CANCELLED','REVERSED')
                  AND date(end_date) >= date(?) THEN 1 ELSE 0 END) active_policies,
        SUM(CASE WHEN posting_status='POSTED'
                  AND date(end_date) BETWEEN date(?) AND date(?, '+30 day')
                 THEN 1 ELSE 0 END) expiring_soon,
        COALESCE(SUM(CASE WHEN posting_status='POSTED'
                          THEN net_sale_amount ELSE 0 END),0) total_sales,
        COALESCE(SUM(CASE WHEN posting_status='POSTED'
                          THEN net_insurer_payable ELSE 0 END),0) total_cost,
        COALESCE(SUM(CASE WHEN posting_status='POSTED'
                          THEN gross_profit ELSE 0 END),0) gross_profit
      FROM insurance_policies
    ''', [day, day, day])).single;
    final payment = (await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN direction='CUSTOMER_RECEIPT' AND status='POSTED'
                          THEN amount ELSE 0 END),0) collected,
        COALESCE(SUM(CASE WHEN direction='INSURER_PAYMENT' AND status='POSTED'
                          THEN amount ELSE 0 END),0) paid
      FROM insurance_policy_payments
    ''')).single;
    final claims = (await db.rawQuery('''
      SELECT COUNT(*) count FROM insurance_claims
      WHERE UPPER(status) NOT IN ('CLOSED','REJECTED')
    ''')).single;
    final sales = _amount(row['total_sales']);
    final cost = _amount(row['total_cost']);
    return InsuranceDashboardSummary(
      activePolicies: _integer(row['active_policies']),
      expiringSoon: _integer(row['expiring_soon']),
      openClaims: _integer(claims['count']),
      totalSales: sales,
      totalCost: cost,
      grossProfit: _amount(row['gross_profit']),
      customerReceivable: sales - _amount(payment['collected']),
      insurerPayable: cost - _amount(payment['paid']),
    );
  }

  static Future<List<InsurancePolicyOverview>> policies({
    String query = '',
    int limit = 100,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final cleaned = query.trim();
    final where = cleaned.isEmpty
        ? ''
        : '''WHERE insured_name LIKE ? OR insured_phone LIKE ?
             OR vehicle_plate LIKE ? OR policy_number LIKE ?
             OR document_number LIKE ? OR company_name LIKE ?''';
    final args =
        cleaned.isEmpty ? <Object?>[] : List<Object?>.filled(6, '%$cleaned%');
    args.add(limit);
    final rows = await db.rawQuery('''
      SELECT id,COALESCE(NULLIF(TRIM(policy_number),''),
                         NULLIF(TRIM(document_number),''),id) number,
             insured_name,vehicle_plate,vehicle_make,company_name,end_date,
             net_sale_amount,sell_price,status,posting_status
      FROM insurance_policies
      $where
      ORDER BY date(end_date) ASC, updated_at DESC
      LIMIT ?
    ''', args);
    return rows.map((row) {
      final rawEnd = row['end_date']?.toString() ?? '';
      return InsurancePolicyOverview(
        id: row['id'].toString(),
        number: row['number'].toString(),
        insuredName: row['insured_name'].toString(),
        vehicle: [row['vehicle_plate'], row['vehicle_make']]
            .where((value) => value?.toString().trim().isNotEmpty == true)
            .join(' — '),
        company: row['company_name'].toString(),
        endDate: DateTime.tryParse(rawEnd) ?? DateTime(1970),
        sale: _amount(row['net_sale_amount']) != 0
            ? _amount(row['net_sale_amount'])
            : _amount(row['sell_price']),
        status: row['posting_status'].toString() == 'POSTED'
            ? row['status'].toString()
            : row['posting_status'].toString(),
      );
    }).toList(growable: false);
  }

  static Future<List<InsuranceCompanyBalance>> companyBalances({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      SELECT c.id,c.name,
             COUNT(DISTINCT CASE WHEN p.posting_status='POSTED' THEN p.id END) policy_count,
             COALESCE(SUM(CASE WHEN p.posting_status='POSTED'
                               THEN p.net_insurer_payable ELSE 0 END),0) payable,
             COALESCE((SELECT SUM(pp.amount)
                       FROM insurance_policy_payments pp
                       JOIN insurance_policies px ON px.id=pp.policy_id
                       WHERE px.insurance_company_id=CAST(c.id AS TEXT)
                         AND pp.direction='INSURER_PAYMENT'
                         AND pp.status='POSTED'),0) paid
      FROM insurance_companies c
      LEFT JOIN insurance_policies p ON p.insurance_company_id=CAST(c.id AS TEXT)
      GROUP BY c.id,c.name
      ORDER BY c.name
    ''');
    return rows
        .map((row) => InsuranceCompanyBalance(
              id: _integer(row['id']),
              name: row['name'].toString(),
              policyCount: _integer(row['policy_count']),
              payable: _amount(row['payable']),
              paid: _amount(row['paid']),
            ))
        .toList(growable: false);
  }

  static Future<List<InsuranceProducerPortfolio>> producerPortfolios({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      SELECT c.producer_party_id party_id,
             COALESCE(NULLIF(TRIM(p.display_name),''),'غير محدد') producer_name,
             COUNT(DISTINCT c.policy_id) policy_count,
             COALESCE(SUM(ip.net_sale_amount),0) sales,
             COALESCE(SUM(c.commission_amount),0) commission
      FROM insurance_commissions c
      LEFT JOIN parties p ON p.id=c.producer_party_id
      LEFT JOIN insurance_policies ip ON ip.id=c.policy_id
      WHERE c.status<>'REVERSED'
      GROUP BY c.producer_party_id,p.display_name
      ORDER BY sales DESC,producer_name
    ''');
    return rows
        .map((row) => InsuranceProducerPortfolio(
              partyId: row['party_id']?.toString() ?? '',
              name: row['producer_name'].toString(),
              policyCount: _integer(row['policy_count']),
              sales: _amount(row['sales']),
              commission: _amount(row['commission']),
            ))
        .toList(growable: false);
  }
}
