import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

class InsuranceSettlementItem {
  const InsuranceSettlementItem({
    required this.type,
    required this.sourceId,
    required this.policyId,
    required this.label,
    required this.amount,
  });

  final String type;
  final String sourceId;
  final String? policyId;
  final String label;
  final double amount;
}

class InsuranceCompanySettlementSnapshot {
  const InsuranceCompanySettlementSnapshot({
    required this.companyId,
    required this.companyName,
    required this.periodStart,
    required this.periodEnd,
    required this.grossPolicies,
    required this.cancellations,
    required this.commission,
    required this.previousPayments,
    required this.payable,
    required this.settlementPayments,
    required this.items,
    this.settlementId,
    this.status = 'PREVIEW',
  });

  final String? settlementId;
  final int companyId;
  final String companyName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double grossPolicies;
  final double cancellations;
  final double commission;
  final double previousPayments;
  final double payable;
  final double settlementPayments;
  final String status;
  final List<InsuranceSettlementItem> items;

  double get outstanding => InsurancePricingEngine.money(
        payable - settlementPayments,
      );

  List<InsuranceSettlementItem> itemsOf(String type) =>
      items.where((item) => item.type == type).toList(growable: false);
}

class InsuranceSettlementCompany {
  const InsuranceSettlementCompany({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

class _PreviewBuild {
  const _PreviewBuild({
    required this.items,
    required this.commission,
  });

  final List<InsuranceSettlementItem> items;
  final double commission;
}

class InsuranceCompanySettlementService {
  InsuranceCompanySettlementService._();

  static double _n(Object? value) => InsurancePricingEngine.money(
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0,
      );

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _dayEnd(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999, 999);

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static String _settlementId(int companyId, DateTime start, DateTime end) =>
      'SET:$companyId:${_dateKey(start)}:${_dateKey(end)}';

  static String _label(Map<String, Object?> row, String fallback) {
    final document = (row['document_number'] ?? '').toString().trim();
    final policy = (row['policy_number'] ?? '').toString().trim();
    if (document.isNotEmpty && policy.isNotEmpty) return '$document — $policy';
    if (document.isNotEmpty) return document;
    if (policy.isNotEmpty) return policy;
    return fallback;
  }

  static double _payloadNumber(Object? raw, String key) {
    if (raw == null) return 0;
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is Map && decoded[key] != null) {
        return _n(decoded[key]);
      }
    } on FormatException {
      return 0;
    }
    return 0;
  }

  static Future<Map<String, Object?>> _company(
    DatabaseExecutor db,
    int companyId,
  ) async {
    final rows = await db.query(
      'insurance_companies',
      columns: const ['id', 'name', 'party_id', 'supplier_id', 'is_active'],
      where: 'id=?',
      whereArgs: [companyId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Insurance company not found.');
    final row = rows.single;
    final supplierId = (row['supplier_id'] as num?)?.toInt();
    final partyId = (row['party_id'] ?? '').toString().trim();
    if (supplierId == null || supplierId <= 0 || partyId.isEmpty) {
      throw StateError(
          'Insurance company has no canonical Supplier/Party link.');
    }
    return row;
  }

  static Future<List<InsuranceSettlementCompany>> companies({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'insurance_companies',
      columns: const ['id', 'name'],
      where: 'is_active=1 AND party_id IS NOT NULL AND supplier_id IS NOT NULL',
      orderBy: 'name ASC',
    );
    return rows
        .map(
          (row) => InsuranceSettlementCompany(
            id: (row['id'] as num).toInt(),
            name: row['name'].toString(),
          ),
        )
        .toList(growable: false);
  }

  static Future<_PreviewBuild> _buildItems(
    DatabaseExecutor db,
    int companyId,
    DateTime start,
    DateTime end,
  ) async {
    final from = _dayStart(start).toIso8601String();
    final to = _dayEnd(end).toIso8601String();
    final items = <InsuranceSettlementItem>[];
    var commission = 0.0;

    final issues = await db.rawQuery('''
      SELECT e.id event_id,e.policy_id,e.payload_json,
             p.document_number,p.policy_number,
             COALESCE((SELECT ic.commission_amount
               FROM insurance_commissions ic
               WHERE ic.policy_id=p.id AND ic.producer_party_id IS NULL
               ORDER BY ic.created_at ASC LIMIT 1),0) commission_amount
      FROM insurance_financial_events e
      JOIN insurance_policies p ON p.id=e.policy_id
      WHERE p.insurance_company_id=?
        AND e.event_type='POLICY_ISSUED'
        AND e.status='POSTED'
        AND datetime(e.created_at)>=datetime(?)
        AND datetime(e.created_at)<=datetime(?)
      ORDER BY e.created_at,e.id
    ''', [companyId.toString(), from, to]);
    for (final row in issues) {
      final amount = _payloadNumber(row['payload_json'], 'cost');
      if (amount.abs() <= 0.005) continue;
      items.add(InsuranceSettlementItem(
        type: 'POLICY_ISSUE',
        sourceId: row['event_id'].toString(),
        policyId: row['policy_id']?.toString(),
        label: _label(row, 'Policy issue'),
        amount: amount,
      ));
      commission += _n(row['commission_amount']);
    }

    final cancellations = await db.rawQuery('''
      SELECT e.id event_id,e.policy_id,issue.payload_json issue_payload,
             p.document_number,p.policy_number,
             COALESCE((SELECT ic.commission_amount
               FROM insurance_commissions ic
               WHERE ic.policy_id=p.id AND ic.producer_party_id IS NULL
               ORDER BY ic.created_at ASC LIMIT 1),0) commission_amount
      FROM insurance_financial_events e
      JOIN insurance_policies p ON p.id=e.policy_id
      LEFT JOIN insurance_financial_events issue
        ON issue.policy_id=p.id AND issue.event_type='POLICY_ISSUED'
      WHERE p.insurance_company_id=?
        AND e.event_type='POLICY_CANCELLED'
        AND e.status='POSTED'
        AND datetime(e.created_at)>=datetime(?)
        AND datetime(e.created_at)<=datetime(?)
      ORDER BY e.created_at,e.id
    ''', [companyId.toString(), from, to]);
    for (final row in cancellations) {
      final amount = _payloadNumber(row['issue_payload'], 'cost');
      if (amount.abs() <= 0.005) continue;
      items.add(InsuranceSettlementItem(
        type: 'POLICY_CANCELLATION',
        sourceId: row['event_id'].toString(),
        policyId: row['policy_id']?.toString(),
        label: _label(row, 'Policy cancellation'),
        amount: -amount.abs(),
      ));
      commission -= _n(row['commission_amount']);
    }

    final endorsements = await db.rawQuery('''
      SELECT e.id event_id,e.event_type,e.source_id,e.policy_id,
             en.delta_cost,p.document_number,p.policy_number
      FROM insurance_financial_events e
      JOIN insurance_endorsements en ON en.id=e.source_id
      JOIN insurance_policies p ON p.id=e.policy_id
      WHERE p.insurance_company_id=?
        AND e.event_type IN ('ENDORSEMENT_POSTED','ENDORSEMENT_REVERSED')
        AND e.status='POSTED'
        AND datetime(e.created_at)>=datetime(?)
        AND datetime(e.created_at)<=datetime(?)
      ORDER BY e.created_at,e.id
    ''', [companyId.toString(), from, to]);
    for (final row in endorsements) {
      final reversal = row['event_type'].toString() == 'ENDORSEMENT_REVERSED';
      final amount = _n(row['delta_cost']) * (reversal ? -1 : 1);
      if (amount.abs() <= 0.005) continue;
      items.add(InsuranceSettlementItem(
        type: reversal ? 'ENDORSEMENT_REVERSAL' : 'ENDORSEMENT',
        sourceId: row['event_id'].toString(),
        policyId: row['policy_id']?.toString(),
        label: _label(row, reversal ? 'Endorsement reversal' : 'Endorsement'),
        amount: InsurancePricingEngine.money(amount),
      ));
    }

    final payments = await db.rawQuery('''
      SELECT pp.id payment_link_id,pp.policy_id,pp.amount,
             p.document_number,p.policy_number
      FROM insurance_policy_payments pp
      JOIN insurance_policies p ON p.id=pp.policy_id
      WHERE p.insurance_company_id=?
        AND pp.direction='INSURER_PAYMENT'
        AND pp.status='POSTED'
        AND pp.settlement_id IS NULL
        AND datetime(pp.created_at)>=datetime(?)
        AND datetime(pp.created_at)<=datetime(?)
      ORDER BY pp.created_at,pp.id
    ''', [companyId.toString(), from, to]);
    for (final row in payments) {
      final amount = _n(row['amount']);
      if (amount <= 0.005) continue;
      items.add(InsuranceSettlementItem(
        type: 'POLICY_PAYMENT',
        sourceId: row['payment_link_id'].toString(),
        policyId: row['policy_id']?.toString(),
        label: _label(row, 'Previous insurer payment'),
        amount: -amount.abs(),
      ));
    }

    return _PreviewBuild(
      items: List.unmodifiable(items),
      commission: InsurancePricingEngine.money(commission),
    );
  }

  static Future<double> _settlementPayments(
    DatabaseExecutor db,
    String settlementId,
  ) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) total
      FROM insurance_policy_payments
      WHERE settlement_id=?
        AND direction='INSURER_PAYMENT'
        AND status='POSTED'
    ''', [settlementId]);
    return _n(rows.single['total']);
  }

  static Future<InsuranceCompanySettlementSnapshot> preview({
    required int companyId,
    required DateTime periodStart,
    required DateTime periodEnd,
    DatabaseExecutor? executor,
  }) async {
    final start = _dayStart(periodStart);
    final end = _dayEnd(periodEnd);
    if (end.isBefore(start)) {
      throw ArgumentError('Settlement period end cannot precede start.');
    }
    final db = await _db(executor);
    final company = await _company(db, companyId);
    final built = await _buildItems(db, companyId, start, end);
    var gross = 0.0;
    var reductions = 0.0;
    var previousPayments = 0.0;
    for (final item in built.items) {
      if (item.type == 'POLICY_PAYMENT') {
        previousPayments += item.amount.abs();
      } else if (item.amount >= 0) {
        gross += item.amount;
      } else {
        reductions += item.amount.abs();
      }
    }
    final id = _settlementId(companyId, start, end);
    final existing = await db.query(
      'insurance_settlements',
      columns: const ['id', 'status'],
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    final paid = await _settlementPayments(db, id);
    return InsuranceCompanySettlementSnapshot(
      settlementId: existing.isEmpty ? null : id,
      companyId: companyId,
      companyName: company['name'].toString(),
      periodStart: start,
      periodEnd: end,
      grossPolicies: InsurancePricingEngine.money(gross),
      cancellations: InsurancePricingEngine.money(reductions),
      commission: built.commission,
      previousPayments: InsurancePricingEngine.money(previousPayments),
      payable:
          InsurancePricingEngine.money(gross - reductions - previousPayments),
      settlementPayments: paid,
      status:
          existing.isEmpty ? 'PREVIEW' : existing.single['status'].toString(),
      items: built.items,
    );
  }

  static Future<void> _assertItemsUnclaimed(
    DatabaseExecutor db,
    String settlementId,
    List<InsuranceSettlementItem> items,
  ) async {
    for (final item in items) {
      final rows = await db.rawQuery('''
        SELECT si.settlement_id
        FROM insurance_settlement_items si
        JOIN insurance_settlements s ON s.id=si.settlement_id
        WHERE si.source_id=? AND si.item_type=?
          AND si.settlement_id<>?
          AND UPPER(COALESCE(s.status,'DRAFT'))<>'CANCELLED'
        LIMIT 1
      ''', [item.sourceId, item.type, settlementId]);
      if (rows.isNotEmpty) {
        throw StateError(
            'Settlement source is already included in another settlement.');
      }
    }
  }

  static Future<InsuranceCompanySettlementSnapshot> saveDraft({
    required int companyId,
    required DateTime periodStart,
    required DateTime periodEnd,
    Database? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insurancePolicyPost);
    final db = database ?? await DBService.database;
    final start = _dayStart(periodStart);
    final end = _dayEnd(periodEnd);
    if (end.isBefore(start)) {
      throw ArgumentError('Settlement period end cannot precede start.');
    }
    final id = _settlementId(companyId, start, end);

    return db.transaction((txn) async {
      await _company(txn, companyId);
      final current = await txn.query(
        'insurance_settlements',
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isNotEmpty &&
          current.single['status'].toString().toUpperCase() != 'DRAFT') {
        throw StateError('Only a draft settlement can be refreshed.');
      }
      final snapshot = await preview(
        companyId: companyId,
        periodStart: start,
        periodEnd: end,
        executor: txn,
      );
      await _assertItemsUnclaimed(txn, id, snapshot.items);
      final now = DateTime.now().toIso8601String();
      final values = <String, Object?>{
        'company_id': companyId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
        'gross_policies': snapshot.grossPolicies,
        'cancellations': snapshot.cancellations,
        'commission': snapshot.commission,
        'previous_payments': snapshot.previousPayments,
        'payable': snapshot.payable,
        'status': 'DRAFT',
      };
      if (current.isEmpty) {
        await txn.insert('insurance_settlements', {
          'id': id,
          ...values,
          'payment_voucher_id': null,
          'created_at': now,
          'posted_at': null,
        });
      } else {
        await txn.update(
          'insurance_settlements',
          values,
          where: 'id=?',
          whereArgs: [id],
        );
        await txn.delete(
          'insurance_settlement_items',
          where: 'settlement_id=?',
          whereArgs: [id],
        );
      }

      for (var index = 0; index < snapshot.items.length; index++) {
        final item = snapshot.items[index];
        await txn.insert('insurance_settlement_items', {
          'id': 'SETITEM:$id:${index.toString().padLeft(4, '0')}',
          'settlement_id': id,
          'policy_id': item.policyId,
          'item_type': item.type,
          'amount': item.amount,
          'source_id': item.sourceId,
          'created_at': now,
        });
      }
      return load(id, executor: txn);
    });
  }

  static Future<InsuranceCompanySettlementSnapshot> postDraft(
    String settlementId, {
    Database? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insurancePolicyPost);
    final clean = settlementId.trim();
    if (clean.isEmpty) throw ArgumentError('Settlement id is required.');
    final db = database ?? await DBService.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'insurance_settlements',
        columns: const ['id', 'status', 'payable'],
        where: 'id=?',
        whereArgs: [clean],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Insurance settlement not found.');
      final status = rows.single['status'].toString().toUpperCase();
      if (status == 'POSTED' || status == 'PARTIAL' || status == 'PAID') {
        return load(clean, executor: txn);
      }
      if (status != 'DRAFT') {
        throw StateError('Only a draft settlement can be posted.');
      }
      await txn.update(
        'insurance_settlements',
        {
          'status': 'POSTED',
          'posted_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [clean],
      );
      return load(clean, executor: txn);
    });
  }

  static Future<InsuranceCompanySettlementSnapshot> load(
    String settlementId, {
    DatabaseExecutor? executor,
  }) async {
    final clean = settlementId.trim();
    if (clean.isEmpty) throw ArgumentError('Settlement id is required.');
    final db = await _db(executor);
    final rows = await db.rawQuery('''
      SELECT s.*,c.name company_name
      FROM insurance_settlements s
      JOIN insurance_companies c ON c.id=s.company_id
      WHERE s.id=? LIMIT 1
    ''', [clean]);
    if (rows.isEmpty) throw StateError('Insurance settlement not found.');
    final row = rows.single;
    final itemRows = await db.query(
      'insurance_settlement_items',
      where: 'settlement_id=?',
      whereArgs: [clean],
      orderBy: 'created_at,id',
    );
    final items = itemRows
        .map(
          (item) => InsuranceSettlementItem(
            type: item['item_type'].toString(),
            sourceId: (item['source_id'] ?? '').toString(),
            policyId: item['policy_id']?.toString(),
            label: item['item_type'].toString(),
            amount: _n(item['amount']),
          ),
        )
        .toList(growable: false);
    final paid = await _settlementPayments(db, clean);
    return InsuranceCompanySettlementSnapshot(
      settlementId: clean,
      companyId: (row['company_id'] as num).toInt(),
      companyName: row['company_name'].toString(),
      periodStart: DateTime.parse(row['period_start'].toString()),
      periodEnd: DateTime.parse(row['period_end'].toString()),
      grossPolicies: _n(row['gross_policies']),
      cancellations: _n(row['cancellations']),
      commission: _n(row['commission']),
      previousPayments: _n(row['previous_payments']),
      payable: _n(row['payable']),
      settlementPayments: paid,
      status: row['status'].toString(),
      items: List.unmodifiable(items),
    );
  }

  static Future<List<InsuranceCompanySettlementSnapshot>> recent({
    int limit = 50,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final rows = await db.query(
      'insurance_settlements',
      columns: const ['id'],
      orderBy: 'period_end DESC,created_at DESC',
      limit: limit,
    );
    final result = <InsuranceCompanySettlementSnapshot>[];
    for (final row in rows) {
      result.add(await load(row['id'].toString(), executor: db));
    }
    return List.unmodifiable(result);
  }

  static Future<VoucherPayment> paySettlement({
    required String operationId,
    required String settlementId,
    required double amount,
    required DateTime date,
    required String method,
    Map<String, dynamic>? chequeDraft,
    String currency = 'ILS',
    String? notes,
    Database? database,
  }) async {
    if (operationId.trim().isEmpty || settlementId.trim().isEmpty) {
      throw ArgumentError(
          'Settlement payment operation and settlement are required.');
    }
    if (!amount.isFinite || amount <= 0.005) {
      throw ArgumentError('Settlement payment must be positive.');
    }
    final db = database ?? await DBService.database;
    final snapshot = await load(settlementId, executor: db);
    final status = snapshot.status.toUpperCase();
    if (status != 'POSTED' && status != 'PARTIAL' && status != 'PAID') {
      throw StateError('Settlement must be posted before payment.');
    }
    final voucherId = 'INS-SET-PAY:${operationId.trim()}';
    final existingLink = await db.query(
      'insurance_policy_payments',
      columns: const ['id'],
      where: 'settlement_id=? AND voucher_id=? AND status=?',
      whereArgs: [settlementId.trim(), voucherId, 'POSTED'],
      limit: 1,
    );
    if (existingLink.isEmpty && amount - snapshot.outstanding > 0.005) {
      throw StateError('Settlement payment exceeds outstanding amount.');
    }

    final company = await _company(db, snapshot.companyId);
    final supplierId = (company['supplier_id'] as num).toInt();
    final voucher = VoucherPayment(
      id: voucherId,
      voucherType: 'PAYMENT',
      partyType: 'SUPPLIER',
      partyId: supplierId.toString(),
      amount: InsurancePricingEngine.money(amount),
      currency: currency.trim().toUpperCase(),
      date: date,
      method: method.trim().toUpperCase(),
      reference: null,
      source: 'INSURANCE_SETTLEMENT',
      sourceId: settlementId.trim(),
      notes: notes ?? 'دفعة تسوية شركة تأمين',
    );
    final posted = await VoucherPaymentService.insertAndPost(
      voucher: voucher,
      partyName: company['name'].toString(),
      chequeDraft: chequeDraft,
      database: db,
      insuranceSettlementId: settlementId.trim(),
    );

    final refreshed = await load(settlementId, executor: db);
    final nextStatus = refreshed.outstanding <= 0.005 ? 'PAID' : 'PARTIAL';
    await db.update(
      'insurance_settlements',
      {
        'status': nextStatus,
        'payment_voucher_id': posted.id,
      },
      where: 'id=?',
      whereArgs: [settlementId.trim()],
    );
    return posted;
  }
}
