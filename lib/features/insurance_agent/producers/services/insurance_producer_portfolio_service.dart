import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

class InsuranceProducerPortfolioRow {
  const InsuranceProducerPortfolioRow({
    required this.partyId,
    required this.producerName,
    required this.policyCount,
    required this.sales,
    required this.commission,
    required this.customerReceipts,
    required this.customerRefunds,
  });

  final String partyId;
  final String producerName;
  final int policyCount;
  final double sales;
  final double commission;
  final double customerReceipts;
  final double customerRefunds;

  double get customerOutstanding => InsurancePricingEngine.money(
        sales - customerReceipts + customerRefunds,
      );
}

class InsuranceProducerCandidate {
  const InsuranceProducerCandidate({
    required this.partyId,
    required this.name,
    required this.employeeId,
  });

  final String partyId;
  final String name;
  final String employeeId;
}

class InsuranceUnassignedPolicyRow {
  const InsuranceUnassignedPolicyRow({
    required this.policyId,
    required this.policyNumber,
    required this.documentNumber,
    required this.insuredName,
    required this.companyName,
    required this.sale,
    required this.commission,
  });

  final String policyId;
  final String policyNumber;
  final String documentNumber;
  final String insuredName;
  final String companyName;
  final double sale;
  final double commission;
}

class InsuranceProducerPortfolioSnapshot {
  const InsuranceProducerPortfolioSnapshot({
    required this.portfolios,
    required this.unassignedPolicies,
    required this.eligibleEmployees,
  });

  final List<InsuranceProducerPortfolioRow> portfolios;
  final List<InsuranceUnassignedPolicyRow> unassignedPolicies;
  final List<InsuranceProducerCandidate> eligibleEmployees;

  int get producerCount => portfolios.length;
  int get assignedPolicyCount =>
      portfolios.fold(0, (sum, row) => sum + row.policyCount);
  double get totalSales => InsurancePricingEngine.money(
        portfolios.fold(0.0, (sum, row) => sum + row.sales),
      );
  double get totalCommission => InsurancePricingEngine.money(
        portfolios.fold(0.0, (sum, row) => sum + row.commission),
      );
}

class InsuranceProducerPortfolioService {
  InsuranceProducerPortfolioService._();

  static double _n(Object? value) =>
      InsurancePricingEngine.money((value as num?)?.toDouble() ?? 0);

  static int _i(Object? value) => (value as num?)?.toInt() ?? 0;

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static Future<InsuranceProducerPortfolioSnapshot> load({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final values = await Future.wait([
      portfolios(executor: db),
      unassignedPolicies(executor: db),
      eligibleEmployees(executor: db),
    ]);
    return InsuranceProducerPortfolioSnapshot(
      portfolios: values[0] as List<InsuranceProducerPortfolioRow>,
      unassignedPolicies: values[1] as List<InsuranceUnassignedPolicyRow>,
      eligibleEmployees: values[2] as List<InsuranceProducerCandidate>,
    );
  }

  static Future<List<InsuranceProducerPortfolioRow>> portfolios({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      WITH assigned AS (
        SELECT c.policy_id,
               c.producer_party_id,
               MAX(p.net_sale_amount) sale,
               SUM(c.commission_amount) commission
        FROM insurance_commissions c
        JOIN insurance_policies p ON p.id=c.policy_id
        WHERE c.producer_party_id IS NOT NULL
          AND c.status NOT IN ('REVERSED','CANCELLED')
          AND p.posting_status='POSTED'
          AND p.reversed_at IS NULL
        GROUP BY c.policy_id,c.producer_party_id
      ), payments AS (
        SELECT policy_id,
               SUM(CASE WHEN direction='CUSTOMER_RECEIPT' AND status='POSTED'
                        THEN amount ELSE 0 END) receipts,
               SUM(CASE WHEN direction='REFUND' AND status='POSTED'
                        THEN amount ELSE 0 END) refunds
        FROM insurance_policy_payments
        GROUP BY policy_id
      )
      SELECT pr.party_id,
             p.display_name producer_name,
             COUNT(a.policy_id) policy_count,
             COALESCE(SUM(a.sale),0) sales,
             COALESCE(SUM(a.commission),0) commission,
             COALESCE(SUM(pay.receipts),0) receipts,
             COALESCE(SUM(pay.refunds),0) refunds
      FROM party_roles pr
      JOIN parties p ON p.id=pr.party_id
      LEFT JOIN assigned a ON a.producer_party_id=pr.party_id
      LEFT JOIN payments pay ON pay.policy_id=a.policy_id
      WHERE pr.role='PRODUCER' AND p.is_active=1
      GROUP BY pr.party_id,p.display_name
      ORDER BY sales DESC,producer_name ASC
    ''');
    return rows
        .map(
          (row) => InsuranceProducerPortfolioRow(
            partyId: (row['party_id'] ?? '').toString(),
            producerName: (row['producer_name'] ?? '').toString(),
            policyCount: _i(row['policy_count']),
            sales: _n(row['sales']),
            commission: _n(row['commission']),
            customerReceipts: _n(row['receipts']),
            customerRefunds: _n(row['refunds']),
          ),
        )
        .toList(growable: false);
  }

  static Future<List<InsuranceProducerCandidate>> eligibleEmployees({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      SELECT p.id party_id,
             p.display_name,
             er.legacy_id employee_id
      FROM party_roles er
      JOIN parties p ON p.id=er.party_id
      JOIN employees e ON e.id=er.legacy_id
      LEFT JOIN party_roles producer
        ON producer.party_id=p.id AND producer.role='PRODUCER'
      WHERE er.role='EMPLOYEE'
        AND p.is_active=1
        AND LOWER(COALESCE(e.status,'active'))='active'
        AND producer.party_id IS NULL
      ORDER BY p.display_name ASC
    ''');
    return rows
        .map(
          (row) => InsuranceProducerCandidate(
            partyId: (row['party_id'] ?? '').toString(),
            name: (row['display_name'] ?? '').toString(),
            employeeId: (row['employee_id'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }

  static Future<List<InsuranceUnassignedPolicyRow>> unassignedPolicies({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      WITH assignments AS (
        SELECT policy_id,MAX(producer_party_id) producer_party_id
        FROM insurance_commissions
        WHERE status NOT IN ('REVERSED','CANCELLED')
        GROUP BY policy_id
      )
      SELECT p.id policy_id,
             p.policy_number,
             p.document_number,
             insured.display_name insured_name,
             company.name company_name,
             p.net_sale_amount sale,
             p.commission_amount commission
      FROM insurance_policies p
      LEFT JOIN assignments a ON a.policy_id=p.id
      LEFT JOIN parties insured ON insured.id=p.insured_party_id
      LEFT JOIN insurance_companies company
        ON CAST(company.id AS TEXT)=CAST(p.insurance_company_id AS TEXT)
      WHERE p.posting_status='POSTED'
        AND p.reversed_at IS NULL
        AND NULLIF(TRIM(COALESCE(a.producer_party_id,'')),'') IS NULL
      ORDER BY p.created_at DESC,p.document_number DESC
    ''');
    return rows
        .map(
          (row) => InsuranceUnassignedPolicyRow(
            policyId: (row['policy_id'] ?? '').toString(),
            policyNumber: (row['policy_number'] ?? '').toString(),
            documentNumber: (row['document_number'] ?? '').toString(),
            insuredName: (row['insured_name'] ?? '').toString(),
            companyName: (row['company_name'] ?? '').toString(),
            sale: _n(row['sale']),
            commission: _n(row['commission']),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> registerEmployeeAsProducer({
    required String partyId,
    Database? database,
  }) async {
    final cleanPartyId = partyId.trim();
    if (cleanPartyId.isEmpty) {
      throw ArgumentError('Producer Party is required.');
    }
    final db = database ?? await DBService.database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT p.id party_id,er.legacy_id employee_id
        FROM parties p
        JOIN party_roles er ON er.party_id=p.id AND er.role='EMPLOYEE'
        JOIN employees e ON e.id=er.legacy_id
        WHERE p.id=?
          AND p.is_active=1
          AND LOWER(COALESCE(e.status,'active'))='active'
        LIMIT 1
      ''', [cleanPartyId]);
      if (rows.isEmpty) {
        throw StateError('Producer must be an active employee Party.');
      }
      final existing = await txn.query(
        'party_roles',
        columns: const ['legacy_id'],
        where: 'party_id=? AND role=?',
        whereArgs: [cleanPartyId, 'PRODUCER'],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('party_roles', {
          'party_id': cleanPartyId,
          'role': 'PRODUCER',
          'legacy_id': rows.single['employee_id'].toString(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      final roles = await txn.query(
        'party_roles',
        columns: const ['role'],
        where: 'party_id=?',
        whereArgs: [cleanPartyId],
        orderBy: 'role ASC',
      );
      await txn.update(
        'parties',
        {
          'role_codes': jsonEncode(
            roles.map((row) => row['role'].toString()).toList(growable: false),
          ),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [cleanPartyId],
      );
    });
  }

  static Future<void> assignPolicyToProducer({
    required String policyId,
    required String producerPartyId,
    Database? database,
  }) async {
    final cleanPolicyId = policyId.trim();
    final cleanProducerId = producerPartyId.trim();
    if (cleanPolicyId.isEmpty || cleanProducerId.isEmpty) {
      throw ArgumentError('Policy and producer are required.');
    }
    final db = database ?? await DBService.database;
    await db.transaction((txn) async {
      final producers = await txn.rawQuery('''
        SELECT p.id
        FROM parties p
        JOIN party_roles r ON r.party_id=p.id AND r.role='PRODUCER'
        WHERE p.id=? AND p.is_active=1
        LIMIT 1
      ''', [cleanProducerId]);
      if (producers.isEmpty) {
        throw StateError('Selected Party is not an active insurance producer.');
      }
      final policies = await txn.query(
        'insurance_policies',
        columns: const [
          'id',
          'insurance_company_id',
          'commission_rate',
          'commission_amount',
        ],
        where: "id=? AND posting_status='POSTED' AND reversed_at IS NULL",
        whereArgs: [cleanPolicyId],
        limit: 1,
      );
      if (policies.isEmpty) {
        throw StateError('Only a posted active policy can be assigned.');
      }
      final policy = policies.single;
      final current = await txn.query(
        'insurance_commissions',
        columns: const ['id'],
        where: "policy_id=? AND status NOT IN ('REVERSED','CANCELLED')",
        whereArgs: [cleanPolicyId],
      );
      final now = DateTime.now().toIso8601String();
      if (current.isEmpty) {
        final companyId = int.tryParse(
          (policy['insurance_company_id'] ?? '').toString(),
        );
        await txn.insert('insurance_commissions', {
          'id': 'COM:PRODUCER:${const Uuid().v4()}',
          'policy_id': cleanPolicyId,
          'company_id': companyId,
          'producer_party_id': cleanProducerId,
          'commission_rate': _n(policy['commission_rate']),
          'commission_amount': _n(policy['commission_amount']),
          'status': 'ACCRUED',
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await txn.update(
          'insurance_commissions',
          {
            'producer_party_id': cleanProducerId,
            'updated_at': now,
          },
          where: "policy_id=? AND status NOT IN ('REVERSED','CANCELLED')",
          whereArgs: [cleanPolicyId],
        );
      }
    });
  }
}
