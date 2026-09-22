import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

class InsuranceEndorsementCommand {
  const InsuranceEndorsementCommand({
    required this.operationId,
    required this.policyId,
    required this.endorsementType,
    required this.effectiveDate,
    this.deltaSale = 0,
    this.deltaCost = 0,
    this.deltaTax = 0,
    this.payload = const <String, Object?>{},
    this.createdBy,
  });

  final String operationId;
  final String policyId;
  final String endorsementType;
  final DateTime effectiveDate;
  final double deltaSale;
  final double deltaCost;
  final double deltaTax;
  final Map<String, Object?> payload;
  final String? createdBy;
}

class InsuranceEndorsementResult {
  const InsuranceEndorsementResult({
    required this.endorsementId,
    required this.policyId,
    required this.status,
    required this.versionNo,
    required this.netSaleAmount,
    required this.netInsurerPayable,
    required this.grossProfit,
    required this.wasExisting,
    this.glEntryId,
    this.reversalGlEntryId,
  });

  final String endorsementId;
  final String policyId;
  final String status;
  final int versionNo;
  final double netSaleAmount;
  final double netInsurerPayable;
  final double grossProfit;
  final bool wasExisting;
  final int? glEntryId;
  final int? reversalGlEntryId;
}

class InsuranceEndorsementService {
  InsuranceEndorsementService._();

  static double _n(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

  static String _cleanRequired(String value, String field) {
    final clean = value.trim();
    if (clean.isEmpty) throw ArgumentError('$field is required.');
    return clean;
  }

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static Future<int> _account(DatabaseExecutor db, String code) async {
    final rows = await db.query(
      'accounts',
      columns: const ['id', 'is_active', 'is_postable'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Missing account $code');
    final row = rows.single;
    if (((row['is_active'] as num?)?.toInt() ?? 1) != 1 ||
        ((row['is_postable'] as num?)?.toInt() ?? 1) != 1) {
      throw StateError('Account $code is not postable');
    }
    return (row['id'] as num).toInt();
  }

  static Future<void> _assertOpen(DatabaseExecutor db, DateTime date) async {
    final iso = date.toIso8601String();
    final rows = await db.rawQuery(
      "SELECT id FROM insurance_period_closes WHERE status='CLOSED' "
      "AND ? >= period_start AND ? <= period_end LIMIT 1",
      [iso, iso],
    );
    if (rows.isNotEmpty) {
      throw StateError('Insurance accounting period is closed.');
    }
  }

  static Map<String, Object?> _requestPayload(
    InsuranceEndorsementCommand command,
  ) {
    return <String, Object?>{
      'operation_id': command.operationId.trim(),
      'policy_id': command.policyId.trim(),
      'endorsement_type': command.endorsementType.trim().toUpperCase(),
      'effective_date': command.effectiveDate.toIso8601String(),
      'delta_sale': InsurancePricingEngine.money(command.deltaSale),
      'delta_cost': InsurancePricingEngine.money(command.deltaCost),
      'delta_tax': InsurancePricingEngine.money(command.deltaTax),
      'payload': command.payload,
    };
  }

  static bool _sameRequest(
    Map<String, Object?> stored,
    InsuranceEndorsementCommand command,
  ) {
    final payload = _requestPayload(command);
    Map<String, Object?> storedPayload = const {};
    final rawPayload = _clean(stored['payload_json']?.toString());
    if (rawPayload != null) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map) {
          storedPayload = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } on FormatException {
        return false;
      }
    }
    return stored['policy_id']?.toString() == payload['policy_id'] &&
        stored['endorsement_type']?.toString() == payload['endorsement_type'] &&
        stored['effective_date']?.toString() == payload['effective_date'] &&
        InsurancePricingEngine.money(_n(stored['delta_sale'])) ==
            payload['delta_sale'] &&
        InsurancePricingEngine.money(_n(stored['delta_cost'])) ==
            payload['delta_cost'] &&
        InsurancePricingEngine.money(_n(stored['delta_tax'])) ==
            payload['delta_tax'] &&
        jsonEncode(storedPayload) == jsonEncode(command.payload);
  }

  static InsuranceEndorsementResult _resultFromPolicy({
    required Map<String, Object?> endorsement,
    required Map<String, Object?> policy,
    required bool wasExisting,
  }) {
    return InsuranceEndorsementResult(
      endorsementId: endorsement['id'].toString(),
      policyId: policy['id'].toString(),
      status: (endorsement['status'] ?? '').toString(),
      versionNo: (policy['version_no'] as num?)?.toInt() ?? 1,
      netSaleAmount: _n(policy['net_sale_amount']),
      netInsurerPayable: _n(policy['net_insurer_payable']),
      grossProfit: _n(policy['gross_profit']),
      wasExisting: wasExisting,
      glEntryId: (endorsement['gl_entry_id'] as num?)?.toInt(),
      reversalGlEntryId: (endorsement['reversal_gl_entry_id'] as num?)?.toInt(),
    );
  }

  static Future<InsuranceEndorsementResult> postEndorsement(
    InsuranceEndorsementCommand command, {
    DatabaseExecutor? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insurancePolicyPost);
    final operationId = _cleanRequired(command.operationId, 'Operation id');
    final policyId = _cleanRequired(command.policyId, 'Policy id');
    final endorsementType =
        _cleanRequired(command.endorsementType, 'Endorsement type')
            .toUpperCase();
    for (final value in [
      command.deltaSale,
      command.deltaCost,
      command.deltaTax,
    ]) {
      if (!value.isFinite) {
        throw ArgumentError('Endorsement financial deltas must be finite.');
      }
    }
    final db = database ?? await DBService.database;
    final actor = command.createdBy?.trim().isNotEmpty == true
        ? command.createdBy!.trim()
        : (await CurrentUserContext.userId()) ?? 'OWNER_LOCAL';
    final endorsementId = 'END:$operationId';

    return SyncFoundationService.writeOn<InsuranceEndorsementResult>(db, (
      txn,
    ) async {
      final existing = await txn.query(
        'insurance_endorsements',
        where: 'id=?',
        whereArgs: [endorsementId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final endorsement = existing.single;
        if (!_sameRequest(endorsement, command)) {
          throw StateError(
              'Endorsement retry differs from original operation.');
        }
        final policies = await txn.query(
          'insurance_policies',
          where: 'id=?',
          whereArgs: [policyId],
          limit: 1,
        );
        if (policies.isEmpty) throw StateError('Insurance policy not found.');
        return _resultFromPolicy(
          endorsement: endorsement,
          policy: policies.single,
          wasExisting: true,
        );
      }

      await _assertOpen(txn, command.effectiveDate);
      final policies = await txn.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: [policyId],
        limit: 1,
      );
      if (policies.isEmpty) throw StateError('Insurance policy not found.');
      final policy = policies.single;
      if ((policy['status'] ?? '').toString().toUpperCase() != 'ACTIVE' ||
          (policy['posting_status'] ?? '').toString().toUpperCase() !=
              'POSTED') {
        throw StateError('Only an active posted policy can be endorsed.');
      }
      final start = DateTime.parse(policy['start_date'].toString());
      final end = DateTime.parse(policy['end_date'].toString());
      if (command.effectiveDate.isBefore(start) ||
          command.effectiveDate.isAfter(end)) {
        throw StateError('Endorsement effective date is outside policy term.');
      }

      final deltaSale = InsurancePricingEngine.money(command.deltaSale);
      final deltaCost = InsurancePricingEngine.money(command.deltaCost);
      final deltaTax = InsurancePricingEngine.money(command.deltaTax);
      final revenueDelta = InsurancePricingEngine.money(deltaSale - deltaTax);
      final currentSale = _n(policy['net_sale_amount']);
      final currentPayable = _n(policy['net_insurer_payable']);
      final currentSellPrice = _n(policy['sell_price']);
      final currentBuyPrice = _n(policy['buy_price']);
      final currentTax = _n(policy['tax']);
      final directCost = _n(policy['direct_cost']);
      final newSale = InsurancePricingEngine.money(currentSale + deltaSale);
      final newPayable =
          InsurancePricingEngine.money(currentPayable + deltaCost);
      final newTax = InsurancePricingEngine.money(currentTax + deltaTax);
      final newSellPrice = InsurancePricingEngine.money(
        currentSellPrice + revenueDelta,
      );
      final newBuyPrice = InsurancePricingEngine.money(
        currentBuyPrice + deltaCost,
      );
      if (newSale < -0.005 ||
          newPayable < -0.005 ||
          newTax < -0.005 ||
          newSellPrice < -0.005 ||
          newBuyPrice < -0.005) {
        throw StateError('Endorsement cannot make policy totals negative.');
      }
      final newGrossProfit = InsurancePricingEngine.money(
        newSale - (newBuyPrice + directCost),
      );
      final costBase = newBuyPrice + directCost;
      final newMarkup =
          costBase.abs() <= 0.005 ? 0.0 : newGrossProfit / costBase * 100;
      final newMargin =
          newSale.abs() <= 0.005 ? 0.0 : newGrossProfit / newSale * 100;

      final clientId = (policy['client_id'] as num?)?.toInt();
      final supplierId = (policy['insurer_supplier_id'] as num?)?.toInt();
      if (clientId == null || supplierId == null) {
        throw StateError(
            'Policy canonical customer/supplier links are missing.');
      }

      final arId = await _account(txn, '1200.C$clientId');
      final apId = await _account(
        txn,
        '2200.S${supplierId.toString().padLeft(4, '0')}',
      );
      final revenueId = await _account(txn, '4010');
      final costId = await _account(txn, '5010');
      final taxId = deltaTax.abs() > 0.005 ? await _account(txn, '2105') : null;
      final lines = <Map<String, Object?>>[];

      void addSigned({
        required int accountId,
        required double amount,
        required bool positiveIsDebit,
        String? partyType,
        String? partyId,
      }) {
        final rounded = InsurancePricingEngine.money(amount);
        if (rounded.abs() <= 0.005) return;
        final debit = positiveIsDebit
            ? (rounded > 0 ? rounded : 0.0)
            : (rounded < 0 ? -rounded : 0.0);
        final credit = positiveIsDebit
            ? (rounded < 0 ? -rounded : 0.0)
            : (rounded > 0 ? rounded : 0.0);
        lines.add({
          'account_id': accountId,
          'debit': debit,
          'credit': credit,
          if (partyType != null) 'party_type': partyType,
          if (partyId != null) 'party_id': partyId,
          'invoice_id': policyId,
        });
      }

      addSigned(
        accountId: arId,
        amount: deltaSale,
        positiveIsDebit: true,
        partyType: 'CLIENT',
        partyId: clientId.toString(),
      );
      addSigned(
        accountId: revenueId,
        amount: revenueDelta,
        positiveIsDebit: false,
      );
      if (taxId != null) {
        addSigned(
          accountId: taxId,
          amount: deltaTax,
          positiveIsDebit: false,
        );
      }
      addSigned(
        accountId: costId,
        amount: deltaCost,
        positiveIsDebit: true,
      );
      addSigned(
        accountId: apId,
        amount: deltaCost,
        positiveIsDebit: false,
        partyType: 'SUPPLIER',
        partyId: supplierId.toString(),
      );

      final now = DateTime.now().toIso8601String();
      int? glEntryId;
      if (lines.isNotEmpty) {
        glEntryId = await DBService.postEntryGLOn(
          ex: txn,
          date: command.effectiveDate,
          ref: endorsementId,
          source: 'INSURANCE_ENDORSEMENT',
          sourceId: endorsementId,
          sourceNumber: endorsementId,
          createdBy: actor,
          note: 'ملحق بوليصة تأمين — $endorsementType',
          lines: lines,
        );
      }

      await txn.insert(
          'insurance_endorsements',
          {
            'id': endorsementId,
            'policy_id': policyId,
            'endorsement_type': endorsementType,
            'effective_date': command.effectiveDate.toIso8601String(),
            'delta_sale': deltaSale,
            'delta_cost': deltaCost,
            'delta_tax': deltaTax,
            'gl_entry_id': glEntryId,
            'reversal_gl_entry_id': null,
            'status': 'POSTED',
            'payload_json': jsonEncode(command.payload),
            'created_by': actor,
            'created_at': now,
            'posted_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      final newVersion = ((policy['version_no'] as num?)?.toInt() ?? 1) + 1;
      final changes = <String, Object?>{
        'sell_price': newSellPrice,
        'buy_price': newBuyPrice,
        'tax': newTax,
        'net_sale_amount': newSale,
        'net_insurer_payable': newPayable,
        'gross_profit': newGrossProfit,
        'markup_percent': newMarkup,
        'margin_percent': newMargin,
        'version_no': newVersion,
        'updated_at': now,
        'updated_by': actor,
      };
      await txn.update(
        'insurance_policies',
        changes,
        where: 'id=?',
        whereArgs: [policyId],
      );
      final after = (await txn.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: [policyId],
        limit: 1,
      ))
          .single;
      await txn.insert(
          'insurance_policy_versions',
          {
            'id': 'PV:$policyId:$newVersion',
            'policy_id': policyId,
            'version_no': newVersion,
            'snapshot_json': jsonEncode(after),
            'reason': 'ENDORSEMENT:$endorsementType',
            'created_by': actor,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      await txn.insert(
          'insurance_financial_events',
          {
            'id': 'EVT:$endorsementId',
            'event_key': endorsementId,
            'event_type': 'ENDORSEMENT_POSTED',
            'source_type': 'INSURANCE_ENDORSEMENT',
            'source_id': endorsementId,
            'policy_id': policyId,
            'amount': deltaSale,
            'gl_entry_id': glEntryId,
            'reversal_of_event_id': null,
            'status': 'POSTED',
            'payload_json': jsonEncode(_requestPayload(command)),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      await AuditTrailService.log(
        executor: txn,
        actorUserId: actor,
        action: 'INSURANCE_ENDORSEMENT_POSTED',
        entityType: 'INSURANCE_ENDORSEMENT',
        entityId: endorsementId,
        before: policy,
        after: after,
        metadata: {
          'policy_id': policyId,
          'gl_entry_id': glEntryId,
          'delta_sale': deltaSale,
          'delta_cost': deltaCost,
          'delta_tax': deltaTax,
        },
      );

      final endorsement = (await txn.query(
        'insurance_endorsements',
        where: 'id=?',
        whereArgs: [endorsementId],
        limit: 1,
      ))
          .single;
      return _resultFromPolicy(
        endorsement: endorsement,
        policy: after,
        wasExisting: false,
      );
    });
  }

  static Future<InsuranceEndorsementResult> reverseEndorsement({
    required String endorsementId,
    required DateTime reversalDate,
    required String reason,
    String? createdBy,
    DatabaseExecutor? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insurancePolicyPost);
    final cleanId = _cleanRequired(endorsementId, 'Endorsement id');
    final cleanReason = _cleanRequired(reason, 'Reversal reason');
    final db = database ?? await DBService.database;
    final actor = createdBy?.trim().isNotEmpty == true
        ? createdBy!.trim()
        : (await CurrentUserContext.userId()) ?? 'OWNER_LOCAL';

    return SyncFoundationService.writeOn<InsuranceEndorsementResult>(db, (
      txn,
    ) async {
      await _assertOpen(txn, reversalDate);
      final endorsements = await txn.query(
        'insurance_endorsements',
        where: 'id=?',
        whereArgs: [cleanId],
        limit: 1,
      );
      if (endorsements.isEmpty) {
        throw StateError('Insurance endorsement not found.');
      }
      final endorsement = endorsements.single;
      final policyId = endorsement['policy_id'].toString();
      final policies = await txn.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: [policyId],
        limit: 1,
      );
      if (policies.isEmpty) throw StateError('Insurance policy not found.');
      final policy = policies.single;
      final status = (endorsement['status'] ?? '').toString().toUpperCase();
      if (status == 'REVERSED') {
        return _resultFromPolicy(
          endorsement: endorsement,
          policy: policy,
          wasExisting: true,
        );
      }
      if (status != 'POSTED') {
        throw StateError('Only a posted endorsement can be reversed.');
      }
      if ((policy['status'] ?? '').toString().toUpperCase() != 'ACTIVE' ||
          (policy['posting_status'] ?? '').toString().toUpperCase() !=
              'POSTED') {
        throw StateError('Endorsement policy is not active and posted.');
      }

      final deltaSale = _n(endorsement['delta_sale']);
      final deltaCost = _n(endorsement['delta_cost']);
      final deltaTax = _n(endorsement['delta_tax']);
      final revenueDelta = InsurancePricingEngine.money(deltaSale - deltaTax);
      final newSale = InsurancePricingEngine.money(
        _n(policy['net_sale_amount']) - deltaSale,
      );
      final newPayable = InsurancePricingEngine.money(
        _n(policy['net_insurer_payable']) - deltaCost,
      );
      final newSellPrice = InsurancePricingEngine.money(
        _n(policy['sell_price']) - revenueDelta,
      );
      final newBuyPrice = InsurancePricingEngine.money(
        _n(policy['buy_price']) - deltaCost,
      );
      final newTax = InsurancePricingEngine.money(
        _n(policy['tax']) - deltaTax,
      );
      if (newSale < -0.005 ||
          newPayable < -0.005 ||
          newSellPrice < -0.005 ||
          newBuyPrice < -0.005 ||
          newTax < -0.005) {
        throw StateError(
            'Endorsement reversal would make policy totals negative.');
      }
      final directCost = _n(policy['direct_cost']);
      final newGrossProfit = InsurancePricingEngine.money(
        newSale - (newBuyPrice + directCost),
      );
      final costBase = newBuyPrice + directCost;
      final newMarkup =
          costBase.abs() <= 0.005 ? 0.0 : newGrossProfit / costBase * 100;
      final newMargin =
          newSale.abs() <= 0.005 ? 0.0 : newGrossProfit / newSale * 100;

      final originalGl = (endorsement['gl_entry_id'] as num?)?.toInt();
      int? reversalGl;
      if (originalGl != null) {
        reversalGl = await DBService.reverseEntryGLOn(
          txn,
          originalGl,
          note: 'عكس ملحق بوليصة تأمين — $cleanReason',
        );
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'insurance_endorsements',
        {
          'status': 'REVERSED',
          'reversal_gl_entry_id': reversalGl,
        },
        where: 'id=? AND status=?',
        whereArgs: [cleanId, 'POSTED'],
      );

      final newVersion = ((policy['version_no'] as num?)?.toInt() ?? 1) + 1;
      await txn.update(
        'insurance_policies',
        {
          'sell_price': newSellPrice,
          'buy_price': newBuyPrice,
          'tax': newTax,
          'net_sale_amount': newSale,
          'net_insurer_payable': newPayable,
          'gross_profit': newGrossProfit,
          'markup_percent': newMarkup,
          'margin_percent': newMargin,
          'version_no': newVersion,
          'updated_at': now,
          'updated_by': actor,
        },
        where: 'id=?',
        whereArgs: [policyId],
      );
      final after = (await txn.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: [policyId],
        limit: 1,
      ))
          .single;
      await txn.insert(
          'insurance_policy_versions',
          {
            'id': 'PV:$policyId:$newVersion',
            'policy_id': policyId,
            'version_no': newVersion,
            'snapshot_json': jsonEncode(after),
            'reason': 'ENDORSEMENT_REVERSED:${endorsement['endorsement_type']}',
            'created_by': actor,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      await txn.insert(
          'insurance_financial_events',
          {
            'id': 'EVT:REV:$cleanId',
            'event_key': 'REV:$cleanId',
            'event_type': 'ENDORSEMENT_REVERSED',
            'source_type': 'INSURANCE_ENDORSEMENT',
            'source_id': cleanId,
            'policy_id': policyId,
            'amount': -deltaSale,
            'gl_entry_id': reversalGl,
            'reversal_of_event_id': 'EVT:$cleanId',
            'status': 'POSTED',
            'payload_json': jsonEncode({'reason': cleanReason}),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      await AuditTrailService.log(
        executor: txn,
        actorUserId: actor,
        action: 'INSURANCE_ENDORSEMENT_REVERSED',
        entityType: 'INSURANCE_ENDORSEMENT',
        entityId: cleanId,
        before: policy,
        after: after,
        reason: cleanReason,
        metadata: {
          'policy_id': policyId,
          'reversal_gl_entry_id': reversalGl,
        },
      );

      final updatedEndorsement = (await txn.query(
        'insurance_endorsements',
        where: 'id=?',
        whereArgs: [cleanId],
        limit: 1,
      ))
          .single;
      return _resultFromPolicy(
        endorsement: updatedEndorsement,
        policy: after,
        wasExisting: false,
      );
    });
  }

  static Future<List<Map<String, Object?>>> listForPolicy(
    String policyId, {
    DatabaseExecutor? executor,
  }) async {
    final cleanPolicy = _cleanRequired(policyId, 'Policy id');
    final db = executor ?? await DBService.database;
    final rows = await db.query(
      'insurance_endorsements',
      where: 'policy_id=?',
      whereArgs: [cleanPolicy],
      orderBy: 'effective_date DESC, created_at DESC',
    );
    return rows.map(Map<String, Object?>.from).toList(growable: false);
  }
}
