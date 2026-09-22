import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/insurance_agent/claims/services/insurance_claim_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_finance_dashboard_service.dart';
import 'package:yalla_accounts/features/insurance_agent/renewals/services/insurance_renewal_service.dart';
import 'package:yalla_accounts/features/insurance_agent/reports/services/insurance_reporting_service.dart';

class InsuranceHomeDashboardSnapshot {
  const InsuranceHomeDashboardSnapshot({
    required this.reporting,
    required this.policies,
    required this.renewals,
    required this.claims,
    required this.companies,
  });

  final InsuranceReportingSnapshot reporting;
  final List<InsuranceFinancePolicyRow> policies;
  final List<InsuranceRenewalCandidate> renewals;
  final List<InsuranceClaimRecord> claims;
  final List<InsuranceCompanyBalanceRow> companies;

  List<InsuranceRenewalCandidate> get pendingRenewals => renewals
      .where((row) => row.status != 'RENEWED' && row.status != 'CANCELLED')
      .toList(growable: false);
  List<InsuranceClaimRecord> get openClaims => claims
      .where((row) => row.status != 'CLOSED' && row.status != 'REJECTED')
      .toList(growable: false);
}

class InsuranceHomeDashboardService {
  InsuranceHomeDashboardService._();

  static Future<InsuranceHomeDashboardSnapshot> load({
    DateTime? asOf,
    DatabaseExecutor? executor,
  }) async {
    final reporting = await InsuranceReportingService.snapshot(
      asOf: asOf,
      executor: executor,
    );
    final policies = await InsuranceFinanceDashboardService.policyBalances(
      executor: executor,
    );
    final renewals = await InsuranceRenewalService.listCandidates(
      asOf: asOf,
      executor: executor,
    );
    final claims = await InsuranceClaimService.listClaims(executor: executor);
    final companies = await InsuranceReportingService.companyBalances(
      executor: executor,
    );

    return InsuranceHomeDashboardSnapshot(
      reporting: reporting,
      policies: List.unmodifiable(policies),
      renewals: List.unmodifiable(renewals),
      claims: List.unmodifiable(claims),
      companies: List.unmodifiable(companies),
    );
  }
}
