import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/insurance_agent/alerts/services/insurance_alert_center_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/renewals/services/insurance_renewal_service.dart';

import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Database db;
  late dynamic session;
  late int clientId;
  late int supplierId;
  late String clientPartyId;
  late String supplierPartyId;
  late String companyId;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('insurance_renewal_');
    db = await DatabaseMigration.initDatabase(
      pathOverride: '${temp.path}/test.db',
    );
    session = await startAccountingSession(db, 'insurance-renewal-owner');

    clientId = await db.insert('clients', {
      'name': 'Renewal Customer',
      'type': 'individual',
      'phone': '0599222222',
    });
    clientPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['CUSTOMER', clientId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    await db.insert('party_roles', {
      'party_id': clientPartyId,
      'role': 'INSURED',
      'legacy_id': clientId.toString(),
      'created_at': DateTime.now().toIso8601String(),
    });

    supplierId = await db.insert('suppliers', {
      'name': 'Renewal Insurance Company',
      'pid': 'S-REN-INS',
    });
    supplierPartyId = (await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['SUPPLIER', supplierId.toString()],
      limit: 1,
    ))
        .single['party_id']
        .toString();
    final now = DateTime.now().toIso8601String();
    companyId = (await db.insert('insurance_companies', {
      'party_id': supplierPartyId,
      'supplier_id': supplierId,
      'code': 'REN-INS',
      'name': 'Renewal Insurance Company',
      'default_commission_rate': 0.0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    }))
        .toString();
    await db.insert('party_roles', {
      'party_id': supplierPartyId,
      'role': 'INSURANCE_COMPANY',
      'legacy_id': companyId,
      'created_at': now,
    });
  });

  tearDown(() async {
    await session.endEphemeralPreviewSession();
    if (db.isOpen) await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<InsurancePolicyPostingResult> issue({
    required String operationId,
    required String policyNumber,
    required DateTime startDate,
    required DateTime endDate,
    String? previousPolicyId,
  }) {
    return InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: operationId,
        policyNumber: policyNumber,
        previousPolicyId: previousPolicyId,
        clientId: clientId,
        insuredPartyId: clientPartyId,
        companyId: companyId,
        insurerPartyId: supplierPartyId,
        insurerSupplierId: supplierId,
        startDate: startDate,
        endDate: endDate,
        postingDate: startDate,
        purchasePrice: 2000,
        salePrice: 2400,
        createdBy: 'insurance-renewal-owner',
      ),
      database: db,
    );
  }

  test('policy creates renewal candidate and exact expiry alert schedule',
      () async {
    final endDate = DateTime(2027, 9, 21);
    final posted = await issue(
      operationId: 'REN-OLD',
      policyNumber: 'REN-OLD-001',
      startDate: DateTime(2026, 9, 22),
      endDate: endDate,
    );

    final candidates = await InsuranceRenewalService.listCandidates(
      asOf: DateTime(2027, 9, 1),
      executor: db,
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.policyId, posted.policyId);
    expect(candidates.single.daysRemaining, 20);
    expect(candidates.single.status, 'PENDING');

    final alerts = await db.query(
      'insurance_alerts',
      where: 'policy_id=? AND alert_type=?',
      whereArgs: [posted.policyId, 'POLICY_EXPIRY'],
      orderBy: 'due_at ASC',
    );
    expect(alerts, hasLength(7));
    final dates =
        alerts.map((row) => DateTime.parse(row['due_at'].toString())).toSet();
    for (final days in const [60, 30, 14, 7, 3, 1, 0]) {
      expect(dates, contains(endDate.subtract(Duration(days: days))));
    }
  });

  test('follow-up states persist and expired state is derived', () async {
    final old = await issue(
      operationId: 'REN-FOLLOWUP',
      policyNumber: 'REN-FOLLOWUP-001',
      startDate: DateTime(2025, 1, 1),
      endDate: DateTime(2026, 1, 1),
    );
    final contactedAt = DateTime(2025, 12, 1, 10);
    final nextAt = DateTime(2025, 12, 8, 10);
    await InsuranceRenewalService.updateFollowUp(
      policyId: old.policyId,
      status: 'WHATSAPP_SENT',
      lastContactAt: contactedAt,
      nextContactAt: nextAt,
      outcome: 'Quote requested',
      database: db,
    );

    final candidate = (await InsuranceRenewalService.listCandidates(
      asOf: DateTime(2026, 1, 2),
      executor: db,
    ))
        .single;
    expect(candidate.status, 'WHATSAPP_SENT');
    expect(candidate.lastContactAt, contactedAt);
    expect(candidate.nextContactAt, nextAt);
    expect(candidate.outcome, 'Quote requested');
    expect(candidate.isExpired, isTrue);

    final followUpAlerts = await InsuranceAlertCenterService.listAlerts(
      asOf: DateTime(2025, 12, 1),
      window: InsuranceAlertWindow.next14,
      executor: db,
    );
    final renewalFollowUps = followUpAlerts
        .where(
          (alert) =>
              alert.type == 'RENEWAL_FOLLOW_UP' &&
              alert.policyId == old.policyId,
        )
        .toList();
    expect(renewalFollowUps, hasLength(1));
    expect(renewalFollowUps.single.dueAt, nextAt);
  });

  test('renewal links old and new policy atomically through previousPolicyId',
      () async {
    final old = await issue(
      operationId: 'REN-LINK-OLD',
      policyNumber: 'REN-LINK-OLD-001',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
    );
    await InsuranceRenewalService.updateFollowUp(
      policyId: old.policyId,
      status: 'CONTACTED',
      lastContactAt: DateTime(2026, 12, 10),
      nextContactAt: DateTime(2026, 12, 15),
      outcome: 'Renewal confirmed',
      database: db,
    );

    final renewed = await issue(
      operationId: 'REN-LINK-NEW',
      policyNumber: 'REN-LINK-NEW-001',
      startDate: DateTime(2027, 1, 1),
      endDate: DateTime(2027, 12, 31),
      previousPolicyId: old.policyId,
    );

    final newPolicy = (await db.query(
      'insurance_policies',
      columns: const ['previous_policy_id'],
      where: 'id=?',
      whereArgs: [renewed.policyId],
    ))
        .single;
    expect(newPolicy['previous_policy_id'], old.policyId);

    final oldCandidate = (await db.query(
      'insurance_renewals',
      where: 'policy_id=?',
      whereArgs: [old.policyId],
    ))
        .single;
    expect(oldCandidate['status'], 'RENEWED');
    expect(oldCandidate['outcome'], 'RENEWED');
    expect(oldCandidate['new_policy_id'], renewed.policyId);

    final oldAlerts = await db.query(
      'insurance_alerts',
      columns: const ['status'],
      where: 'policy_id=? AND alert_type=?',
      whereArgs: [old.policyId, 'POLICY_EXPIRY'],
    );
    expect(oldAlerts, hasLength(7));
    expect(
      oldAlerts.every((row) => row['status'] == 'RESOLVED'),
      isTrue,
    );
    final visibleAfterRenewal = await InsuranceAlertCenterService.listAlerts(
      asOf: DateTime(2026, 12, 15),
      window: InsuranceAlertWindow.all,
      executor: db,
    );
    expect(
      visibleAfterRenewal.where(
        (alert) =>
            alert.type == 'RENEWAL_FOLLOW_UP' && alert.policyId == old.policyId,
      ),
      isEmpty,
    );

    final newCandidate = (await db.query(
      'insurance_renewals',
      where: 'policy_id=?',
      whereArgs: [renewed.policyId],
    ))
        .single;
    expect(newCandidate['previous_policy_id'], old.policyId);
  });
}
