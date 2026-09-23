import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

class InsuranceSalesIntelligenceCompanyRow {
  const InsuranceSalesIntelligenceCompanyRow({
    required this.companyId,
    required this.companyName,
    required this.policyCount,
    required this.sales,
    required this.grossProfit,
  });

  final int companyId;
  final String companyName;
  final int policyCount;
  final double sales;
  final double grossProfit;
}

class InsuranceSalesIntelligenceProducerRow {
  const InsuranceSalesIntelligenceProducerRow({
    required this.partyId,
    required this.producerName,
    required this.policyCount,
    required this.sales,
    required this.commission,
  });

  final String partyId;
  final String producerName;
  final int policyCount;
  final double sales;
  final double commission;
}

class InsuranceSalesIntelligenceSnapshot {
  const InsuranceSalesIntelligenceSnapshot({
    required this.totalQuotes,
    required this.issuedQuotes,
    required this.activeProspects,
    required this.followUpsDue,
    required this.postedPolicies,
    required this.unassignedPolicies,
    required this.expiring30,
    required this.sales,
    required this.grossProfit,
    required this.topCompanies,
    required this.topProducers,
  });

  final int totalQuotes;
  final int issuedQuotes;
  final int activeProspects;
  final int followUpsDue;
  final int postedPolicies;
  final int unassignedPolicies;
  final int expiring30;
  final double sales;
  final double grossProfit;
  final List<InsuranceSalesIntelligenceCompanyRow> topCompanies;
  final List<InsuranceSalesIntelligenceProducerRow> topProducers;

  double get quoteConversionPercent => totalQuotes == 0
      ? 0
      : InsurancePricingEngine.money((issuedQuotes / totalQuotes) * 100);

  double get grossMarginPercent => sales == 0
      ? 0
      : InsurancePricingEngine.money((grossProfit / sales) * 100);
}

class InsuranceSalesIntelligenceService {
  InsuranceSalesIntelligenceService._();

  static double _n(Object? value) =>
      InsurancePricingEngine.money((value as num?)?.toDouble() ?? 0);

  static int _i(Object? value) => (value as num?)?.toInt() ?? 0;

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static Future<InsuranceSalesIntelligenceSnapshot> snapshot({
    DateTime? asOf,
    DatabaseExecutor? executor,
    int leaderboardLimit = 5,
  }) async {
    if (leaderboardLimit < 1 || leaderboardLimit > 25) {
      throw ArgumentError.value(
        leaderboardLimit,
        'leaderboardLimit',
        'must be between 1 and 25',
      );
    }
    final db = await _db(executor);
    final now = asOf ?? DateTime.now();
    final nowIso = now.toIso8601String();
    final soonIso = now.add(const Duration(days: 30)).toIso8601String();

    final quote = (await db.rawQuery('''
      SELECT COUNT(*) total_quotes,
             COALESCE(SUM(CASE
               WHEN issued_policy_id IS NOT NULL
                    AND TRIM(issued_policy_id)<>'' THEN 1 ELSE 0 END),0)
               issued_quotes
      FROM insurance_quotes
    ''')).single;

    final prospect = (await db.rawQuery('''
      SELECT COALESCE(SUM(CASE
               WHEN status NOT IN ('CONVERTED','ARCHIVED') THEN 1 ELSE 0 END),0)
               active_prospects,
             COALESCE(SUM(CASE
               WHEN status NOT IN ('CONVERTED','ARCHIVED')
                    AND next_contact_at IS NOT NULL
                    AND TRIM(next_contact_at)<>''
                    AND next_contact_at<=? THEN 1 ELSE 0 END),0)
               followups_due
      FROM insurance_prospects
    ''', [nowIso])).single;

    final policy = (await db.rawQuery('''
      SELECT COUNT(*) posted_policies,
             COALESCE(SUM(net_sale_amount),0) sales,
             COALESCE(SUM(gross_profit),0) gross_profit,
             COALESCE(SUM(CASE
               WHEN end_date>=? AND end_date<=? THEN 1 ELSE 0 END),0)
               expiring_30
      FROM insurance_policies
      WHERE posting_status='POSTED' AND reversed_at IS NULL
    ''', [nowIso, soonIso])).single;

    final unassigned = (await db.rawQuery('''
      WITH assignment AS (
        SELECT policy_id,
               MAX(NULLIF(TRIM(COALESCE(producer_party_id,'')),'')) producer_party_id
        FROM insurance_commissions
        WHERE status NOT IN ('REVERSED','CANCELLED')
        GROUP BY policy_id
      )
      SELECT COUNT(*) total
      FROM insurance_policies p
      LEFT JOIN assignment a ON a.policy_id=p.id
      WHERE p.posting_status='POSTED'
        AND p.reversed_at IS NULL
        AND a.producer_party_id IS NULL
    ''')).single;

    final companyRows = await db.rawQuery('''
      SELECT c.id company_id,
             c.name company_name,
             COUNT(p.id) policy_count,
             COALESCE(SUM(p.net_sale_amount),0) sales,
             COALESCE(SUM(p.gross_profit),0) gross_profit
      FROM insurance_policies p
      JOIN insurance_companies c
        ON CAST(c.id AS TEXT)=CAST(p.insurance_company_id AS TEXT)
      WHERE p.posting_status='POSTED' AND p.reversed_at IS NULL
      GROUP BY c.id,c.name
      ORDER BY sales DESC,gross_profit DESC,company_name ASC
      LIMIT ?
    ''', [leaderboardLimit]);

    final producerRows = await db.rawQuery('''
      WITH assigned AS (
        SELECT c.policy_id,
               c.producer_party_id,
               MAX(p.net_sale_amount) sales,
               SUM(c.commission_amount) commission
        FROM insurance_commissions c
        JOIN insurance_policies p ON p.id=c.policy_id
        WHERE c.producer_party_id IS NOT NULL
          AND TRIM(c.producer_party_id)<>''
          AND c.status NOT IN ('REVERSED','CANCELLED')
          AND p.posting_status='POSTED'
          AND p.reversed_at IS NULL
        GROUP BY c.policy_id,c.producer_party_id
      )
      SELECT a.producer_party_id party_id,
             party.display_name producer_name,
             COUNT(a.policy_id) policy_count,
             COALESCE(SUM(a.sales),0) sales,
             COALESCE(SUM(a.commission),0) commission
      FROM assigned a
      JOIN parties party ON party.id=a.producer_party_id
      WHERE party.is_active=1
      GROUP BY a.producer_party_id,party.display_name
      ORDER BY sales DESC,commission DESC,producer_name ASC
      LIMIT ?
    ''', [leaderboardLimit]);

    return InsuranceSalesIntelligenceSnapshot(
      totalQuotes: _i(quote['total_quotes']),
      issuedQuotes: _i(quote['issued_quotes']),
      activeProspects: _i(prospect['active_prospects']),
      followUpsDue: _i(prospect['followups_due']),
      postedPolicies: _i(policy['posted_policies']),
      unassignedPolicies: _i(unassigned['total']),
      expiring30: _i(policy['expiring_30']),
      sales: _n(policy['sales']),
      grossProfit: _n(policy['gross_profit']),
      topCompanies: companyRows
          .map(
            (row) => InsuranceSalesIntelligenceCompanyRow(
              companyId: _i(row['company_id']),
              companyName: (row['company_name'] ?? '').toString(),
              policyCount: _i(row['policy_count']),
              sales: _n(row['sales']),
              grossProfit: _n(row['gross_profit']),
            ),
          )
          .toList(growable: false),
      topProducers: producerRows
          .map(
            (row) => InsuranceSalesIntelligenceProducerRow(
              partyId: (row['party_id'] ?? '').toString(),
              producerName: (row['producer_name'] ?? '').toString(),
              policyCount: _i(row['policy_count']),
              sales: _n(row['sales']),
              commission: _n(row['commission']),
            ),
          )
          .toList(growable: false),
    );
  }
}
