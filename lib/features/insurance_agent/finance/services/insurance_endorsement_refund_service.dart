import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

class InsuranceEndorsementResult {
  const InsuranceEndorsementResult({
    required this.id,
    required this.glEntryId,
    required this.customerDelta,
    required this.insurerDelta,
    required this.wasExisting,
  });

  final String id;
  final int glEntryId;
  final double customerDelta;
  final double insurerDelta;
  final bool wasExisting;
}

class InsuranceEndorsementRefundService {
  InsuranceEndorsementRefundService._();

  static double _n(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _money(double value) => (value * 100).round() / 100;

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

  static Future<void> _assertOpen(
    DatabaseExecutor db,
    DateTime date,
  ) async {
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

  static Map<String, Object?> _signedLine({
    required int accountId,
    required double signedDebit,
    String? partyType,
    String? partyId,
    String? invoiceId,
  }) {
    final value = _money(signedDebit);
    return {
      'account_id': accountId,
      'debit': value > 0 ? value : 0.0,
      'credit': value < 0 ? -value : 0.0,
      'party_type': partyType,
      'party_id': partyId,
      'invoice_id': invoiceId,
    };
  }

  static Future<InsuranceEndorsementResult> postEndorsement({
    required String operationId,
    required String policyId,
    required String endorsementType,
    required DateTime effectiveDate,
    double deltaSale = 0,
    double deltaCost = 0,
    double deltaTax = 0,
    Map<String, Object?>? payload,
    String? createdBy,
    DatabaseExecutor? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    final op = operationId.trim();
    final pid = policyId.trim();
    final type = endorsementType.trim().toUpperCase();
    if (op.isEmpty || pid.isEmpty || type.isEmpty) {
      throw ArgumentError(
        'Endorsement operation, policy and type are required.',
      );
    }
    for (final value in [deltaSale, deltaCost, deltaTax]) {
      if (!value.isFinite) {
        throw ArgumentError('Endorsement amount is invalid.');
      }
    }
    if (deltaSale.abs() <= 0.005 &&
        deltaCost.abs() <= 0.005 &&
        deltaTax.abs() <= 0.005) {
      throw ArgumentError('Endorsement must have a financial effect.');
    }

    final db = database ?? await DBService.database;
    final id = 'END:$op';
    final customerDelta = _money(deltaSale + deltaTax);
    final insurerDelta = _money(deltaCost);
    return SyncFoundationService.writeOn<InsuranceEndorsementResult>(
      db,
      (txn) async {
        final existing = await txn.query(
          'insurance_endorsements',
          where: 'id=?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final row = existing.single;
          final same = row['policy_id']?.toString() == pid &&
              row['endorsement_type']?.toString() == type &&
              _money(_n(row['delta_sale'])) == _money(deltaSale) &&
              _money(_n(row['delta_cost'])) == _money(deltaCost) &&
              _money(_n(row['delta_tax'])) == _money(deltaTax);
          if (!same || row['status']?.toString() != 'POSTED') {
            throw StateError(
              'Endorsement retry differs from original operation.',
            );
          }
          final glId = (row['gl_entry_id'] as num?)?.toInt();
          if (glId == null) throw StateError('Endorsement has no GL entry.');
          return InsuranceEndorsementResult(
            id: id,
            glEntryId: glId,
            customerDelta: customerDelta,
            insurerDelta: insurerDelta,
            wasExisting: true,
          );
        }

        await _assertOpen(txn, effectiveDate);
        final policies = await txn.query(
          'insurance_policies',
          where: 'id=? AND posting_status=?',
          whereArgs: [pid, 'POSTED'],
          limit: 1,
        );
        if (policies.isEmpty) {
          throw StateError('Posted insurance policy not found.');
        }
        final policy = policies.single;
        final clientId = (policy['client_id'] as num?)?.toInt();
        final supplierId = (policy['insurer_supplier_id'] as num?)?.toInt();
        if (clientId == null ||
            clientId <= 0 ||
            supplierId == null ||
            supplierId <= 0) {
          throw StateError('Policy financial parties are incomplete.');
        }

        final oldNetSale = _n(policy['net_sale_amount']);
        final oldPayable = _n(policy['net_insurer_payable']);
        final oldTax = _n(policy['tax']);
        final oldSell = _n(policy['sell_price']);
        final oldBuy = _n(policy['buy_price']);
        final oldProfit = _n(policy['gross_profit']);
        final directCost = _n(policy['direct_cost']);

        final newNetSale = _money(oldNetSale + customerDelta);
        final newPayable = _money(oldPayable + insurerDelta);
        final newTax = _money(oldTax + deltaTax);
        final newSell = _money(oldSell + deltaSale);
        final newBuy = _money(oldBuy + deltaCost);
        final newProfit = _money(oldProfit + deltaSale - deltaCost);
        if (newNetSale < -0.005 ||
            newPayable < -0.005 ||
            newTax < -0.005 ||
            newSell < -0.005 ||
            newBuy < -0.005) {
          throw StateError('Endorsement would make policy totals negative.');
        }

        final arId =
            await AccountingTables.ensureClientAccountOn(txn, clientId);
        final apId = await AccountingTables.ensureSupplierAccountOn(
          txn,
          supplierId.toString(),
        );
        final revenueId = await _account(txn, '4010');
        final costId = await _account(txn, '5010');
        final taxId =
            deltaTax.abs() > 0.005 ? await _account(txn, '2105') : null;

        final lines = <Map<String, Object?>>[
          if (customerDelta.abs() > 0.005)
            _signedLine(
              accountId: arId,
              signedDebit: customerDelta,
              partyType: 'CLIENT',
              partyId: clientId.toString(),
              invoiceId: pid,
            ),
          if (deltaSale.abs() > 0.005)
            _signedLine(
              accountId: revenueId,
              signedDebit: -deltaSale,
              invoiceId: pid,
            ),
          if (deltaTax.abs() > 0.005)
            _signedLine(
              accountId: taxId!,
              signedDebit: -deltaTax,
              invoiceId: pid,
            ),
          if (deltaCost.abs() > 0.005)
            _signedLine(
              accountId: costId,
              signedDebit: deltaCost,
              invoiceId: pid,
            ),
          if (deltaCost.abs() > 0.005)
            _signedLine(
              accountId: apId,
              signedDebit: -deltaCost,
              partyType: 'SUPPLIER',
              partyId: supplierId.toString(),
              invoiceId: pid,
            ),
        ];

        final actor = createdBy?.trim().isNotEmpty == true
            ? createdBy!.trim()
            : (policy['updated_by'] ?? policy['created_by'] ?? 'OWNER_LOCAL')
                .toString();
        final policyNumber = (policy['policy_number'] ?? pid).toString();
        final glId = await DBService.postEntryGLOn(
          ex: txn,
          date: effectiveDate,
          ref: id,
          source: 'INSURANCE_ENDORSEMENT',
          sourceId: id,
          sourceNumber: id,
          createdBy: actor,
          note: 'Insurance endorsement $type — $policyNumber',
          lines: lines,
        );
        final newNetRevenue = _money(newNetSale - newTax);
        final costBase = _money(newBuy + directCost);
        final markup =
            costBase.abs() <= 0.005 ? 0.0 : (newProfit / costBase) * 100;
        final margin = newNetRevenue.abs() <= 0.005
            ? 0.0
            : (newProfit / newNetRevenue) * 100;
        final now = DateTime.now().toIso8601String();
        final version = ((policy['version_no'] as num?)?.toInt() ?? 1) + 1;

        await txn.update(
          'insurance_policies',
          {
            'sell_price': newSell,
            'buy_price': newBuy,
            'tax': newTax,
            'net_sale_amount': newNetSale,
            'net_insurer_payable': newPayable,
            'gross_profit': newProfit,
            'markup_percent': markup,
            'margin_percent': margin,
            'version_no': version,
            'updated_at': now,
            'updated_by': actor,
          },
          where: 'id=?',
          whereArgs: [pid],
        );

        await txn.insert('insurance_endorsements', {
          'id': id,
          'policy_id': pid,
          'endorsement_type': type,
          'effective_date': effectiveDate.toIso8601String(),
          'delta_sale': _money(deltaSale),
          'delta_cost': _money(deltaCost),
          'delta_tax': _money(deltaTax),
          'gl_entry_id': glId,
          'reversal_gl_entry_id': null,
          'status': 'POSTED',
          'payload_json': payload == null ? null : jsonEncode(payload),
          'created_by': actor,
          'created_at': now,
          'posted_at': now,
        });

        final afterPolicy = (await txn.query(
          'insurance_policies',
          where: 'id=?',
          whereArgs: [pid],
          limit: 1,
        ))
            .single;
        await txn.insert('insurance_policy_versions', {
          'id': 'PV:$pid:$version',
          'policy_id': pid,
          'version_no': version,
          'snapshot_json': jsonEncode(afterPolicy),
          'reason': 'ENDORSEMENT:$type',
          'created_by': actor,
          'created_at': now,
        });

        await txn.insert('insurance_financial_events', {
          'id': const Uuid().v4(),
          'event_key': 'ENDORSEMENT:$op',
          'event_type': 'ENDORSEMENT',
          'source_type': 'INSURANCE_ENDORSEMENT',
          'source_id': id,
          'policy_id': pid,
          'amount': customerDelta,
          'gl_entry_id': glId,
          'status': 'POSTED',
          'payload_json': payload == null ? null : jsonEncode(payload),
          'created_at': now,
        });

        return InsuranceEndorsementResult(
          id: id,
          glEntryId: glId,
          customerDelta: customerDelta,
          insurerDelta: insurerDelta,
          wasExisting: false,
        );
      },
    );
  }

  static Future<int> reverseEndorsement({
    required String endorsementId,
    required String reason,
    DatabaseExecutor? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    final id = endorsementId.trim();
    final cleanReason = reason.trim();
    if (id.isEmpty || cleanReason.isEmpty) {
      throw ArgumentError(
        'Endorsement and reversal reason are required.',
      );
    }
    final db = database ?? await DBService.database;
    return SyncFoundationService.writeOn<int>(db, (txn) async {
      final rows = await txn.query(
        'insurance_endorsements',
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Insurance endorsement not found.');
      }
      final row = rows.single;
      if (row['status']?.toString() == 'REVERSED') {
        final existing = (row['reversal_gl_entry_id'] as num?)?.toInt();
        if (existing == null) {
          throw StateError('Reversed endorsement has no GL.');
        }
        return existing;
      }
      if (row['status']?.toString() != 'POSTED') {
        throw StateError('Only posted endorsements can be reversed.');
      }

      final pid = row['policy_id'].toString();
      final policies = await txn.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: [pid],
        limit: 1,
      );
      if (policies.isEmpty) {
        throw StateError('Insurance policy not found.');
      }
      final policy = policies.single;
      final deltaSale = _n(row['delta_sale']);
      final deltaCost = _n(row['delta_cost']);
      final deltaTax = _n(row['delta_tax']);
      final customerDelta = _money(deltaSale + deltaTax);
      final oldNetSale = _n(policy['net_sale_amount']);
      final oldPayable = _n(policy['net_insurer_payable']);
      final oldTax = _n(policy['tax']);
      final oldSell = _n(policy['sell_price']);
      final oldBuy = _n(policy['buy_price']);
      final oldProfit = _n(policy['gross_profit']);
      final directCost = _n(policy['direct_cost']);

      final newNetSale = _money(oldNetSale - customerDelta);
      final newPayable = _money(oldPayable - deltaCost);
      final newTax = _money(oldTax - deltaTax);
      final newSell = _money(oldSell - deltaSale);
      final newBuy = _money(oldBuy - deltaCost);
      final newProfit = _money(oldProfit - deltaSale + deltaCost);
      if ([newNetSale, newPayable, newTax, newSell, newBuy]
          .any((value) => value < -0.005)) {
        throw StateError(
          'Endorsement reversal would make policy totals negative.',
        );
      }

      final glId = (row['gl_entry_id'] as num?)?.toInt();
      if (glId == null) {
        throw StateError('Endorsement has no GL entry.');
      }
      final reversalGl = await DBService.reverseEntryGLOn(
        txn,
        glId,
        note: 'Insurance endorsement reversal: $cleanReason',
      );
      final now = DateTime.now().toIso8601String();
      final newNetRevenue = _money(newNetSale - newTax);
      final costBase = _money(newBuy + directCost);
      final markup =
          costBase.abs() <= 0.005 ? 0.0 : (newProfit / costBase) * 100;
      final margin = newNetRevenue.abs() <= 0.005
          ? 0.0
          : (newProfit / newNetRevenue) * 100;

      await txn.update(
        'insurance_policies',
        {
          'sell_price': newSell,
          'buy_price': newBuy,
          'tax': newTax,
          'net_sale_amount': newNetSale,
          'net_insurer_payable': newPayable,
          'gross_profit': newProfit,
          'markup_percent': markup,
          'margin_percent': margin,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [pid],
      );
      await txn.update(
        'insurance_endorsements',
        {
          'status': 'REVERSED',
          'reversal_gl_entry_id': reversalGl,
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.update(
        'insurance_financial_events',
        {'status': 'REVERSED'},
        where: 'source_type=? AND source_id=? AND status=?',
        whereArgs: ['INSURANCE_ENDORSEMENT', id, 'POSTED'],
      );
      await txn.insert('insurance_financial_events', {
        'id': const Uuid().v4(),
        'event_key': 'ENDORSEMENT_REVERSAL:$id',
        'event_type': 'ENDORSEMENT_REVERSAL',
        'source_type': 'INSURANCE_ENDORSEMENT',
        'source_id': id,
        'policy_id': pid,
        'amount': -customerDelta,
        'gl_entry_id': reversalGl,
        'status': 'POSTED',
        'payload_json': jsonEncode({'reason': cleanReason}),
        'created_at': now,
      });
      return reversalGl;
    });
  }

  static Future<VoucherPayment> refundCustomer({
    required String operationId,
    required String policyId,
    required double amount,
    required DateTime date,
    required String method,
    String? notes,
    Map<String, dynamic>? chequeDraft,
    Database? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    final op = operationId.trim();
    final pid = policyId.trim();
    if (op.isEmpty || pid.isEmpty || !amount.isFinite || amount <= 0.005) {
      throw ArgumentError(
        'Valid refund operation, policy and amount are required.',
      );
    }
    final db = database ?? await DBService.database;
    await _assertOpen(db, date);
    final policies = await db.query(
      'insurance_policies',
      columns: const ['client_id', 'insured_name', 'currency'],
      where: 'id=? AND posting_status=?',
      whereArgs: [pid, 'POSTED'],
      limit: 1,
    );
    if (policies.isEmpty) {
      throw StateError('Posted insurance policy not found.');
    }
    final row = policies.single;
    final clientId = (row['client_id'] as num?)?.toInt();
    if (clientId == null || clientId <= 0) {
      throw StateError('Policy has no customer link.');
    }

    final voucher = VoucherPayment(
      id: 'INS-REFUND:$op',
      voucherType: 'PAYMENT',
      partyType: 'CLIENT',
      partyId: clientId.toString(),
      amount: _money(amount),
      currency: (row['currency'] ?? MoneyFormatter.currencyCode).toString(),
      date: date,
      method: method.trim().toUpperCase(),
      reference: pid,
      source: 'INSURANCE_REFUND',
      sourceId: pid,
      notes: notes,
    );

    return VoucherPaymentService.insertAndPost(
      voucher: voucher,
      partyName: (row['insured_name'] ?? 'Insurance customer').toString(),
      chequeDraft: chequeDraft,
      database: db,
      insurancePolicyId: pid,
      insuranceDirection: 'REFUND',
    );
  }

  static Future<void> reverseRefund({
    required String voucherId,
    required String reason,
    Database? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    return VoucherPaymentService.reverseVoucher(
      voucherId,
      reason: reason,
      database: database,
    );
  }
}
