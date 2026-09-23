import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_period_close_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

class InsuranceSettlementRecord {
  const InsuranceSettlementRecord({
    required this.id,
    required this.companyId,
    required this.periodStart,
    required this.periodEnd,
    required this.grossPolicies,
    required this.cancellations,
    required this.commission,
    required this.previousPayments,
    required this.payable,
    required this.status,
    required this.createdAt,
    this.paymentVoucherId,
    this.postedAt,
  });

  final String id;
  final int companyId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double grossPolicies;
  final double cancellations;
  final double commission;
  final double previousPayments;
  final double payable;
  final String status;
  final String? paymentVoucherId;
  final DateTime createdAt;
  final DateTime? postedAt;

  static double _n(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  static DateTime? _date(Object? value) {
    final raw = value?.toString().trim() ?? '';
    return raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  factory InsuranceSettlementRecord.fromRow(Map<String, Object?> row) {
    return InsuranceSettlementRecord(
      id: row['id'].toString(),
      companyId: int.parse(row['company_id'].toString()),
      periodStart: DateTime.parse(row['period_start'].toString()),
      periodEnd: DateTime.parse(row['period_end'].toString()),
      grossPolicies: _n(row['gross_policies']),
      cancellations: _n(row['cancellations']),
      commission: _n(row['commission']),
      previousPayments: _n(row['previous_payments']),
      payable: _n(row['payable']),
      status: row['status'].toString(),
      paymentVoucherId: row['payment_voucher_id']?.toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      postedAt: _date(row['posted_at']),
    );
  }
}

class InsuranceSettlementItemRecord {
  const InsuranceSettlementItemRecord({
    required this.id,
    required this.settlementId,
    required this.policyId,
    required this.itemType,
    required this.amount,
    required this.createdAt,
    this.sourceId,
  });

  final String id;
  final String settlementId;
  final String policyId;
  final String itemType;
  final double amount;
  final String? sourceId;
  final DateTime createdAt;

  factory InsuranceSettlementItemRecord.fromRow(Map<String, Object?> row) {
    return InsuranceSettlementItemRecord(
      id: row['id'].toString(),
      settlementId: row['settlement_id'].toString(),
      policyId: row['policy_id'].toString(),
      itemType: row['item_type'].toString(),
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      sourceId: row['source_id']?.toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
    );
  }
}

class InsuranceSettlementService {
  InsuranceSettlementService._();

  static double _n(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  static double _money(double value) => (value * 100).round() / 100;
  static String _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day).toIso8601String();

  static Future<InsuranceSettlementRecord> buildSettlement({
    required String operationId,
    required int companyId,
    required DateTime periodStart,
    required DateTime periodEnd,
    DatabaseExecutor? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    if (operationId.trim().isEmpty || companyId <= 0) {
      throw ArgumentError('Settlement operation and company are required.');
    }
    final start = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final end = DateTime(
      periodEnd.year,
      periodEnd.month,
      periodEnd.day,
      23,
      59,
      59,
      999,
    );
    if (end.isBefore(start)) {
      throw ArgumentError('Settlement period is invalid.');
    }
    final db = database ?? await DBService.database;
    final id = 'SET:${operationId.trim()}';
    return SyncFoundationService.writeOn<InsuranceSettlementRecord>(
      db,
      (txn) async {
        final companies = await txn.query(
          'insurance_companies',
          columns: const ['id', 'supplier_id', 'name'],
          where: 'id=? AND is_active=1',
          whereArgs: [companyId],
          limit: 1,
        );
        if (companies.isEmpty) {
          throw StateError('Insurance company not found.');
        }
        final supplierId = (companies.single['supplier_id'] as num?)?.toInt();
        if (supplierId == null || supplierId <= 0) {
          throw StateError('Insurance company has no supplier link.');
        }

        final existing = await txn.query(
          'insurance_settlements',
          where: 'id=?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final row = existing.single;
          final same = int.parse(row['company_id'].toString()) == companyId &&
              row['period_start'].toString() == _dateOnly(start) &&
              row['period_end'].toString() == _dateOnly(end);
          if (!same) {
            throw StateError('Settlement retry differs from original request.');
          }
          return InsuranceSettlementRecord.fromRow(row);
        }

        final policies = await txn.rawQuery(
          '''SELECT p.id, p.net_insurer_payable, p.commission_amount
             FROM insurance_policies p
             JOIN gl_entries g ON g.id=p.gl_entry_id
             WHERE p.insurance_company_id=?
               AND p.posting_status='POSTED'
               AND p.reversed_at IS NULL
               AND g.date>=? AND g.date<=?
             ORDER BY p.id''',
          [
            companyId.toString(),
            start.toIso8601String(),
            end.toIso8601String(),
          ],
        );
        var gross = 0.0;
        var commission = 0.0;
        var previousPayments = 0.0;
        final outstandingByPolicy = <String, double>{};
        for (final policy in policies) {
          final policyId = policy['id'].toString();
          final payable = _n(policy['net_insurer_payable']);
          gross += payable;
          commission += _n(policy['commission_amount']);

          final paidRows = await txn.rawQuery(
            '''SELECT COALESCE(SUM(amount),0) paid
               FROM insurance_policy_payments
               WHERE policy_id=? AND direction='INSURER_PAYMENT'
                 AND status='POSTED' ''',
            [policyId],
          );
          final paid = _n(paidRows.single['paid']);
          previousPayments += paid;
          final outstanding = _money(payable - paid);
          if (outstanding > 0.005) {
            outstandingByPolicy[policyId] = outstanding;
          }
        }

        final policyIds = policies.map((row) => row['id'].toString()).toList();
        var cancellations = 0.0;
        if (policyIds.isNotEmpty) {
          final marks = List.filled(policyIds.length, '?').join(',');
          final rows = await txn.rawQuery(
            '''SELECT COALESCE(SUM(CASE WHEN delta_cost<0 THEN -delta_cost ELSE 0 END),0) n
               FROM insurance_endorsements
               WHERE status=? AND effective_date>=? AND effective_date<=?
               AND policy_id IN ($marks)''',
            [
              'POSTED',
              start.toIso8601String(),
              end.toIso8601String(),
              ...policyIds,
            ],
          );
          cancellations = _n(rows.single['n']);
        }

        gross = _money(gross);
        commission = _money(commission);
        previousPayments = _money(previousPayments);
        cancellations = _money(cancellations);
        final payable = _money(
          outstandingByPolicy.values.fold<double>(0, (sum, v) => sum + v),
        );
        final now = DateTime.now().toIso8601String();
        await txn.insert('insurance_settlements', {
          'id': id,
          'company_id': companyId,
          'period_start': _dateOnly(start),
          'period_end': _dateOnly(end),
          'gross_policies': gross,
          'cancellations': cancellations,
          'commission': commission,
          'previous_payments': previousPayments,
          'payable': payable,
          'status': 'DRAFT',
          'payment_voucher_id': null,
          'created_at': now,
          'posted_at': null,
        });

        for (final entry in outstandingByPolicy.entries) {
          await txn.insert('insurance_settlement_items', {
            'id': 'SI:$id:${entry.key}',
            'settlement_id': id,
            'policy_id': entry.key,
            'item_type': 'POLICY_OUTSTANDING',
            'amount': entry.value,
            'source_id': entry.key,
            'created_at': now,
          });
        }
        return InsuranceSettlementRecord.fromRow(
          (await txn.query(
            'insurance_settlements',
            where: 'id=?',
            whereArgs: [id],
            limit: 1,
          ))
              .single,
        );
      },
    );
  }

  static Future<InsuranceSettlementRecord> postSettlement(
    String settlementId, {
    DatabaseExecutor? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    final id = settlementId.trim();
    if (id.isEmpty) throw ArgumentError('Settlement id is required.');
    final db = database ?? await DBService.database;
    return SyncFoundationService.writeOn<InsuranceSettlementRecord>(
      db,
      (txn) async {
        final rows = await txn.query(
          'insurance_settlements',
          where: 'id=?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Insurance settlement not found.');
        final status = rows.single['status'].toString();
        if (status == 'POSTED' || status == 'PAID') {
          return InsuranceSettlementRecord.fromRow(rows.single);
        }
        if (status != 'DRAFT') {
          throw StateError('Only draft settlements can be posted.');
        }
        final now = DateTime.now().toIso8601String();
        final changed = await txn.update(
          'insurance_settlements',
          {'status': 'POSTED', 'posted_at': now},
          where: 'id=? AND status=?',
          whereArgs: [id, 'DRAFT'],
        );
        if (changed != 1) {
          throw StateError('Settlement posting was not atomic.');
        }
        return InsuranceSettlementRecord.fromRow(
          (await txn.query(
            'insurance_settlements',
            where: 'id=?',
            whereArgs: [id],
            limit: 1,
          ))
              .single,
        );
      },
    );
  }

  static Future<double> paidAmount(
    String settlementId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final row = (await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) n
         FROM insurance_policy_payments
         WHERE settlement_id=? AND direction='INSURER_PAYMENT'
           AND status='POSTED' ''',
      [settlementId.trim()],
    ))
        .single;
    return _money(_n(row['n']));
  }

  static Future<VoucherPayment> paySettlement({
    required String operationId,
    required String settlementId,
    required double amount,
    required DateTime date,
    required String method,
    String? notes,
    Map<String, dynamic>? chequeDraft,
    Database? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    if (operationId.trim().isEmpty ||
        settlementId.trim().isEmpty ||
        !amount.isFinite ||
        amount <= 0.005) {
      throw ArgumentError('Valid settlement payment is required.');
    }
    final db = database ?? await DBService.database;
    await InsurancePeriodCloseService.assertOpen(db, date);
    final rows = await db.rawQuery(
      '''SELECT s.*, c.supplier_id, c.name company_name
         FROM insurance_settlements s
         JOIN insurance_companies c ON c.id=s.company_id
         WHERE s.id=? LIMIT 1''',
      [settlementId.trim()],
    );
    if (rows.isEmpty) throw StateError('Insurance settlement not found.');
    final row = rows.single;
    final status = row['status'].toString();
    if (status != 'POSTED' && status != 'PAID') {
      throw StateError('Settlement must be posted before payment.');
    }
    final supplierId = (row['supplier_id'] as num?)?.toInt();
    if (supplierId == null || supplierId <= 0) {
      throw StateError('Settlement company has no supplier.');
    }

    final voucherId = 'INS-SET-PAY:${operationId.trim()}';
    final paidRows = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) paid
         FROM insurance_policy_payments
         WHERE settlement_id=? AND direction='INSURER_PAYMENT'
           AND status='POSTED'
           AND (voucher_id IS NULL OR voucher_id<>?)''',
      [settlementId.trim(), voucherId],
    );
    final paidExcludingRetry = _money(_n(paidRows.single['paid']));
    final remaining = _money(_n(row['payable']) - paidExcludingRetry);
    if (amount - remaining > 0.005) {
      throw StateError('Settlement payment exceeds remaining payable.');
    }

    final voucher = VoucherPayment(
      id: voucherId,
      voucherType: 'PAYMENT',
      partyType: 'SUPPLIER',
      partyId: supplierId.toString(),
      amount: _money(amount),
      currency: 'ILS',
      date: date,
      method: method.trim().toUpperCase(),
      reference: settlementId.trim(),
      source: 'INSURANCE_SETTLEMENT',
      sourceId: settlementId.trim(),
      notes: notes,
    );
    final posted = await VoucherPaymentService.insertAndPost(
      voucher: voucher,
      partyName: (row['company_name'] ?? 'Insurance company').toString(),
      chequeDraft: chequeDraft,
      database: db,
      insuranceSettlementId: settlementId.trim(),
    );

    final afterPaid = await paidAmount(settlementId, executor: db);
    await db.update(
      'insurance_settlements',
      {
        'payment_voucher_id': posted.id,
        'status':
            _money(_n(row['payable']) - afterPaid) <= 0.005 ? 'PAID' : 'POSTED',
      },
      where: 'id=?',
      whereArgs: [settlementId.trim()],
    );
    return posted;
  }

  static Future<void> reverseSettlementPayment({
    required String settlementId,
    required String voucherId,
    required String reason,
    Database? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceFinanceManage);
    final db = database ?? await DBService.database;
    await VoucherPaymentService.reverseVoucher(
      voucherId,
      reason: reason,
      database: db,
    );
    final rows = await db.query(
      'insurance_settlements',
      columns: const ['payable'],
      where: 'id=?',
      whereArgs: [settlementId.trim()],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Insurance settlement not found.');
    final paid = await paidAmount(settlementId, executor: db);
    await db.update(
      'insurance_settlements',
      {
        'status': _money(_n(rows.single['payable']) - paid) <= 0.005
            ? 'PAID'
            : 'POSTED',
      },
      where: 'id=?',
      whereArgs: [settlementId.trim()],
    );
  }

  static Future<List<InsuranceSettlementItemRecord>> items(
    String settlementId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.query(
      'insurance_settlement_items',
      where: 'settlement_id=?',
      whereArgs: [settlementId.trim()],
      orderBy: 'policy_id ASC, id ASC',
    );
    return rows
        .map(InsuranceSettlementItemRecord.fromRow)
        .toList(growable: false);
  }
}
