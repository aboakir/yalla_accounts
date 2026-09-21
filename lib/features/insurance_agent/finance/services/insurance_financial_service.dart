import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import 'insurance_pricing_engine.dart';

class InsurancePolicyPostingCommand {
  const InsurancePolicyPostingCommand({
    required this.operationId,
    required this.policyNumber,
    required this.clientId,
    required this.insuredPartyId,
    required this.companyId,
    required this.insurerPartyId,
    required this.insurerSupplierId,
    required this.startDate,
    required this.endDate,
    required this.postingDate,
    required this.purchasePrice,
    required this.salePrice,
    this.policyId,
    this.vehicleId,
    this.productId,
    this.basePremium = 0,
    this.discount = 0,
    this.fees = 0,
    this.tax = 0,
    this.commissionRate = 0,
    this.directCost = 0,
    this.currency = 'ILS',
    this.notes,
    this.createdBy,
  });

  final String operationId;
  final String? policyId;
  final String policyNumber;
  final int clientId;
  final String insuredPartyId;
  final int? vehicleId;
  final String companyId;
  final String insurerPartyId;
  final int insurerSupplierId;
  final String? productId;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime postingDate;
  final double purchasePrice;
  final double salePrice;
  final double basePremium;
  final double discount;
  final double fees;
  final double tax;
  final double commissionRate;
  final double directCost;
  final String currency;
  final String? notes;
  final String? createdBy;
}

class InsurancePolicyPostingResult {
  const InsurancePolicyPostingResult({
    required this.policyId,
    required this.glEntryId,
    required this.pricing,
    required this.wasExisting,
  });
  final String policyId;
  final int glEntryId;
  final InsurancePricingResult pricing;
  final bool wasExisting;
}

class InsurancePolicyBalances {
  const InsurancePolicyBalances({
    required this.sale,
    required this.customerReceipts,
    required this.customerOutstanding,
    required this.insurerPayable,
    required this.insurerPayments,
    required this.insurerOutstanding,
  });
  final double sale;
  final double customerReceipts;
  final double customerOutstanding;
  final double insurerPayable;
  final double insurerPayments;
  final double insurerOutstanding;
}

class InsuranceFinancialService {
  InsuranceFinancialService._();

  static double _n(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

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

  static Future<InsurancePolicyPostingResult> postPolicy(
    InsurancePolicyPostingCommand command, {
    Database? database,
  }) async {
    final op = command.operationId.trim();
    final number = command.policyNumber.trim();
    final companyId = command.companyId.trim();
    if (op.isEmpty ||
        number.isEmpty ||
        companyId.isEmpty ||
        command.insuredPartyId.trim().isEmpty ||
        command.insurerPartyId.trim().isEmpty) {
      throw ArgumentError('Insurance policy master fields are required.');
    }
    if (command.clientId <= 0 || command.insurerSupplierId <= 0) {
      throw ArgumentError('Insurance client/company supplier are required.');
    }
    if (!command.endDate.isAfter(command.startDate)) {
      throw ArgumentError('Policy end date must be after start date.');
    }

    final pricing = InsurancePricingEngine.calculate(
      InsurancePricingInput(
        purchasePrice: command.purchasePrice,
        salePrice: command.salePrice,
        basePremium: command.basePremium,
        discount: command.discount,
        fees: command.fees,
        tax: command.tax,
        commissionRate: command.commissionRate,
        directCost: command.directCost,
      ),
    );
    if (pricing.netSaleAmount <= 0) {
      throw StateError('Policy net sale must be greater than zero.');
    }

    final db = database ?? await DBService.database;
    final actor = command.createdBy?.trim().isNotEmpty == true
        ? command.createdBy!.trim()
        : (await CurrentUserContext.userId()) ?? 'OWNER_LOCAL';

    return SyncFoundationService.transaction<InsurancePolicyPostingResult>(db, (
      txn,
    ) async {
      await _assertOpen(txn, command.postingDate);
      final existing = await txn.query(
        'insurance_policies',
        where: 'operation_id=?',
        whereArgs: [op],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        final same = row['policy_number']?.toString() == number &&
            (row['client_id'] as num?)?.toInt() == command.clientId &&
            row['insurance_company_id']?.toString() == companyId &&
            _n(row['net_sale_amount']).toStringAsFixed(2) ==
                pricing.netSaleAmount.toStringAsFixed(2) &&
            _n(row['net_insurer_payable']).toStringAsFixed(2) ==
                pricing.netInsurerPayable.toStringAsFixed(2);
        if (!same) {
          throw StateError('Policy retry differs from original operation.');
        }
        final gl = (row['gl_entry_id'] as num?)?.toInt();
        if (gl == null ||
            (row['posting_status'] ?? '').toString().toUpperCase() !=
                'POSTED') {
          throw StateError('Policy exists in partial posting state.');
        }
        return InsurancePolicyPostingResult(
          policyId: row['id'].toString(),
          glEntryId: gl,
          pricing: pricing,
          wasExisting: true,
        );
      }

      final clients = await txn.query(
        'clients',
        columns: const ['id', 'name', 'phone'],
        where: 'id=?',
        whereArgs: [command.clientId],
        limit: 1,
      );
      if (clients.isEmpty) throw StateError('Insurance client not found.');
      final parties = await txn.query(
        'parties',
        columns: const ['id', 'display_name', 'phone'],
        where: 'id=? AND is_active=1',
        whereArgs: [command.insuredPartyId.trim()],
        limit: 1,
      );
      if (parties.isEmpty) throw StateError('Insured party not found.');
      final companies = await txn.query(
        'insurance_companies',
        columns: const ['id', 'party_id', 'supplier_id', 'name'],
        where: 'id=? AND is_active=1',
        whereArgs: [companyId],
        limit: 1,
      );
      if (companies.isEmpty) {
        throw StateError('Insurance company master record not found.');
      }
      final company = companies.single;
      if (company['party_id']?.toString() != command.insurerPartyId.trim() ||
          (company['supplier_id'] as num?)?.toInt() !=
              command.insurerSupplierId) {
        throw StateError('Company Party/Supplier links do not match policy.');
      }

      Map<String, Object?>? vehicle;
      if (command.vehicleId != null) {
        final rows = await txn.query(
          'vehicles',
          where: 'id=?',
          whereArgs: [command.vehicleId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Insurance vehicle not found.');
        vehicle = rows.single;
      }
      if (command.productId?.trim().isNotEmpty == true) {
        final product = await txn.query(
          'insurance_products',
          columns: const ['id', 'company_id'],
          where: 'id=? AND is_active=1',
          whereArgs: [command.productId!.trim()],
          limit: 1,
        );
        if (product.isEmpty ||
            product.single['company_id']?.toString() != companyId) {
          throw StateError('Product does not belong to selected company.');
        }
      }

      final arId = await AccountingTables.ensureClientAccountOn(
        txn,
        command.clientId,
      );
      final apId = await AccountingTables.ensureSupplierAccountOn(
        txn,
        command.insurerSupplierId.toString(),
      );
      final revenueId = await _account(txn, '4010');
      final costId = await _account(txn, '5010');
      final taxId = pricing.tax > 0.005 ? await _account(txn, '2105') : null;
      final directId =
          pricing.directCost > 0.005 ? await _account(txn, '5030') : null;
      final accruedId =
          pricing.directCost > 0.005 ? await _account(txn, '2190') : null;

      final policyId = command.policyId?.trim().isNotEmpty == true
          ? command.policyId!.trim()
          : const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final client = clients.single;
      final insured = parties.single;

      final policy = <String, Object?>{
        'id': policyId,
        'created_at': now,
        'updated_at': now,
        'vehicle_plate': (vehicle?['number'] ?? '').toString(),
        'vehicle_make': (vehicle?['type'] ?? '').toString(),
        'vehicle_model_year': (vehicle?['model'] ?? '').toString(),
        'engine_cc': '',
        'insured_name':
            (insured['display_name'] ?? client['name'] ?? '').toString(),
        'insured_phone': (insured['phone'] ?? client['phone'] ?? '').toString(),
        'company_name': (company['name'] ?? '').toString(),
        'start_date': command.startDate.toIso8601String(),
        'end_date': command.endDate.toIso8601String(),
        'is_vip': 0,
        'buy_price': pricing.purchasePrice,
        'sell_price': pricing.salePrice,
        'payment_type': 'canonical_receipt',
        'cash_amount': 0.0,
        'notes': command.notes,
        'operation_id': op,
        'policy_number': number,
        'status': 'ACTIVE',
        'client_id': command.clientId,
        'insured_party_id': command.insuredPartyId.trim(),
        'vehicle_id': command.vehicleId,
        'insurance_company_id': companyId,
        'insurer_party_id': command.insurerPartyId.trim(),
        'insurer_supplier_id': command.insurerSupplierId,
        'product_id': command.productId?.trim(),
        'base_premium': pricing.basePremium,
        'discount': pricing.discount,
        'fees': pricing.fees,
        'tax': pricing.tax,
        'commission_rate': pricing.commissionRate,
        'commission_amount': pricing.commissionAmount,
        'direct_cost': pricing.directCost,
        'net_sale_amount': pricing.netSaleAmount,
        'net_insurer_payable': pricing.netInsurerPayable,
        'gross_profit': pricing.grossProfit,
        'markup_percent': pricing.markupPercent,
        'margin_percent': pricing.marginPercent,
        'currency': command.currency.trim().toUpperCase(),
        'posting_key': 'POLICY:$op',
        'posting_status': 'PENDING',
        'created_by': actor,
        'updated_by': actor,
        'version_no': 1,
      };
      await txn.insert(
        'insurance_policies',
        policy,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final revenueBeforeTax = InsurancePricingEngine.money(
        pricing.netSaleAmount - pricing.tax,
      );
      final lines = <Map<String, Object?>>[
        {
          'account_id': arId,
          'debit': pricing.netSaleAmount,
          'credit': 0.0,
          'party_type': 'CLIENT',
          'party_id': command.clientId.toString(),
          'invoice_id': policyId,
        },
        if (revenueBeforeTax > 0.005)
          {
            'account_id': revenueId,
            'debit': 0.0,
            'credit': revenueBeforeTax,
            'invoice_id': policyId,
          },
        if (pricing.tax > 0.005)
          {
            'account_id': taxId,
            'debit': 0.0,
            'credit': pricing.tax,
            'invoice_id': policyId,
          },
        if (pricing.purchasePrice > 0.005)
          {
            'account_id': costId,
            'debit': pricing.purchasePrice,
            'credit': 0.0,
            'invoice_id': policyId,
          },
        if (pricing.purchasePrice > 0.005)
          {
            'account_id': apId,
            'debit': 0.0,
            'credit': pricing.purchasePrice,
            'party_type': 'SUPPLIER',
            'party_id': command.insurerSupplierId.toString(),
            'invoice_id': policyId,
          },
        if (pricing.directCost > 0.005)
          {
            'account_id': directId,
            'debit': pricing.directCost,
            'credit': 0.0,
            'invoice_id': policyId,
          },
        if (pricing.directCost > 0.005)
          {
            'account_id': accruedId,
            'debit': 0.0,
            'credit': pricing.directCost,
            'invoice_id': policyId,
          },
      ];

      final glId = await DBService.postEntryGLOn(
        ex: txn,
        date: command.postingDate,
        ref: number,
        source: 'INSURANCE_POLICY',
        sourceId: policyId,
        sourceNumber: number,
        createdBy: actor,
        note: 'إصدار بوليصة تأمين — $number',
        lines: lines,
      );

      await txn.update(
        'insurance_policies',
        {
          'gl_entry_id': glId,
          'posting_status': 'POSTED',
          'posted_at': now,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [policyId],
      );

      final snapshot = Map<String, Object?>.from(policy)
        ..['gl_entry_id'] = glId
        ..['posting_status'] = 'POSTED'
        ..['posted_at'] = now;
      await txn.insert(
          'insurance_policy_versions',
          {
            'id': 'PV:$policyId:1',
            'policy_id': policyId,
            'version_no': 1,
            'snapshot_json': jsonEncode(snapshot),
            'reason': 'ISSUED',
            'created_by': actor,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      if (pricing.commissionAmount > 0.005) {
        await txn.insert(
            'insurance_commissions',
            {
              'id': 'COM:$policyId:1',
              'policy_id': policyId,
              'company_id': companyId,
              'producer_party_id': null,
              'commission_rate': pricing.commissionRate,
              'commission_amount': pricing.commissionAmount,
              'status': 'ACCRUED',
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort);
      }

      await txn.insert(
          'insurance_financial_events',
          {
            'id': 'EVT:POLICY:$policyId',
            'event_key': 'POLICY:$op',
            'event_type': 'POLICY_ISSUED',
            'source_type': 'INSURANCE_POLICY',
            'source_id': policyId,
            'policy_id': policyId,
            'amount': pricing.netSaleAmount,
            'gl_entry_id': glId,
            'reversal_of_event_id': null,
            'status': 'POSTED',
            'payload_json': jsonEncode({
              'sale': pricing.netSaleAmount,
              'cost': pricing.purchasePrice,
              'direct_cost': pricing.directCost,
              'profit': pricing.grossProfit,
              'margin': pricing.marginPercent,
              'markup': pricing.markupPercent,
            }),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      await txn.insert(
          'insurance_renewals',
          {
            'id': 'REN:$policyId',
            'policy_id': policyId,
            'previous_policy_id': null,
            'renewal_date': command.endDate.toIso8601String(),
            'status': 'PENDING',
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

      for (final days in const [60, 30, 14, 7, 3, 1, 0]) {
        final due = command.endDate.subtract(Duration(days: days));
        await txn.insert(
            'insurance_alerts',
            {
              'id': 'ALERT:$policyId:POLICY_EXPIRY:$days',
              'alert_type': 'POLICY_EXPIRY',
              'party_id': command.insuredPartyId.trim(),
              'policy_id': policyId,
              'claim_id': null,
              'due_at': due.toIso8601String(),
              'status': 'OPEN',
              'severity': days <= 3 ? 'HIGH' : 'NORMAL',
              'message': days == 0
                  ? 'تنتهي البوليصة اليوم'
                  : 'متبقي $days يوم على انتهاء البوليصة',
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      await AuditTrailService.log(
        executor: txn,
        actorUserId: actor,
        action: 'INSURANCE_POLICY_POSTED',
        entityType: 'INSURANCE_POLICY',
        entityId: policyId,
        after: snapshot,
        metadata: {'gl_entry_id': glId, 'operation_id': op},
      );

      return InsurancePolicyPostingResult(
        policyId: policyId,
        glEntryId: glId,
        pricing: pricing,
        wasExisting: false,
      );
    });
  }

  static Future<CanonicalReceiptResult> collectPolicy({
    required String operationId,
    required String policyId,
    required DateTime date,
    required List<ReceiptInstrumentInput> instruments,
    String? notes,
    Database? database,
  }) {
    return PaymentService.insertCanonicalInsuranceReceipt(
      operationId: operationId,
      database: database,
      policyId: policyId,
      date: date,
      instruments: instruments,
      notes: notes,
    );
  }

  static Future<VoucherPayment> payInsuranceCompanyForPolicy({
    required String operationId,
    required String policyId,
    required double amount,
    required DateTime date,
    required String method,
    Map<String, dynamic>? chequeDraft,
    String currency = 'ILS',
    String? notes,
    Database? database,
  }) async {
    if (operationId.trim().isEmpty || policyId.trim().isEmpty) {
      throw ArgumentError('Insurance payment operation and policy required.');
    }
    if (!amount.isFinite || amount <= 0.005) {
      throw ArgumentError('Insurance company payment must be positive.');
    }
    final db = database ?? await DBService.database;
    final rows = await db.rawQuery(
      '''SELECT p.insurer_supplier_id, c.name
         FROM insurance_policies p
         LEFT JOIN insurance_companies c ON c.id=p.insurance_company_id
         WHERE p.id=? AND p.posting_status='POSTED'
         LIMIT 1''',
      [policyId],
    );
    if (rows.isEmpty) throw StateError('Posted insurance policy not found.');
    final supplierId = (rows.single['insurer_supplier_id'] as num?)?.toInt();
    if (supplierId == null || supplierId <= 0) {
      throw StateError('Policy has no insurance-company supplier link.');
    }

    final voucher = VoucherPayment(
      id: 'INS-PAY:${operationId.trim()}',
      voucherType: 'PAYMENT',
      partyType: 'SUPPLIER',
      partyId: supplierId.toString(),
      amount: InsurancePricingEngine.money(amount),
      currency: currency.trim().toUpperCase(),
      date: date,
      method: method.trim().toUpperCase(),
      reference: null,
      source: 'INSURANCE_POLICY',
      sourceId: policyId,
      notes: notes ?? 'دفعة لشركة التأمين عن البوليصة',
    );
    return VoucherPaymentService.insertAndPost(
      voucher: voucher,
      partyName: (rows.single['name'] ?? 'شركة التأمين').toString(),
      chequeDraft: chequeDraft,
      database: db,
      insurancePolicyId: policyId,
    );
  }

  static Future<InsurancePolicyBalances> balances(
    String policyId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final policies = await db.query(
      'insurance_policies',
      columns: const ['net_sale_amount', 'net_insurer_payable'],
      where: 'id=?',
      whereArgs: [policyId],
      limit: 1,
    );
    if (policies.isEmpty) throw StateError('Insurance policy not found.');
    final sale = _n(policies.single['net_sale_amount']);
    final payable = _n(policies.single['net_insurer_payable']);
    final sums = await db.rawQuery(
      '''SELECT direction, COALESCE(SUM(amount),0) total
         FROM insurance_policy_payments
         WHERE policy_id=? AND status='POSTED'
         GROUP BY direction''',
      [policyId],
    );
    double receipts = 0;
    double payments = 0;
    for (final row in sums) {
      final amount = _n(row['total']);
      if (row['direction'] == 'CUSTOMER_RECEIPT') receipts += amount;
      if (row['direction'] == 'INSURER_PAYMENT') payments += amount;
      if (row['direction'] == 'REFUND') receipts -= amount;
    }
    return InsurancePolicyBalances(
      sale: InsurancePricingEngine.money(sale),
      customerReceipts: InsurancePricingEngine.money(receipts),
      customerOutstanding: InsurancePricingEngine.money(sale - receipts),
      insurerPayable: InsurancePricingEngine.money(payable),
      insurerPayments: InsurancePricingEngine.money(payments),
      insurerOutstanding: InsurancePricingEngine.money(payable - payments),
    );
  }

  static Future<int> cancelPolicy({
    required String policyId,
    required String reason,
    String? createdBy,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Cancellation reason is required.');
    }
    final db = await DBService.database;
    final actor = createdBy?.trim().isNotEmpty == true
        ? createdBy!.trim()
        : (await CurrentUserContext.userId()) ?? 'OWNER_LOCAL';

    return SyncFoundationService.transaction<int>(db, (txn) async {
      await _assertOpen(txn, DateTime.now());
      final rows = await txn.query(
        'insurance_policies',
        where: 'id=?',
        whereArgs: [policyId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Insurance policy not found.');
      final policy = rows.single;

      if ((policy['status'] ?? '').toString().toUpperCase() == 'CANCELLED') {
        final reversal = (policy['reversal_gl_entry_id'] as num?)?.toInt();
        if (reversal == null) {
          throw StateError('Cancelled policy has no reversal GL entry.');
        }
        return reversal;
      }
      if ((policy['posting_status'] ?? '').toString().toUpperCase() !=
          'POSTED') {
        throw StateError('Only a posted policy can be cancelled.');
      }
      final glId = (policy['gl_entry_id'] as num?)?.toInt();
      if (glId == null) throw StateError('Policy has no posted GL entry.');

      final reversal = await AccountingTables.reverseEntryGLOn(
        txn,
        glId,
        createdBy: actor,
        note: 'إلغاء بوليصة تأمين — ${reason.trim()}',
      );
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'insurance_policies',
        {
          'status': 'CANCELLED',
          'posting_status': 'REVERSED',
          'reversal_gl_entry_id': reversal,
          'reversed_at': now,
          'updated_at': now,
          'updated_by': actor,
        },
        where: 'id=?',
        whereArgs: [policyId],
      );
      await txn.update(
        'insurance_alerts',
        {'status': 'CANCELLED', 'updated_at': now},
        where: 'policy_id=? AND status=?',
        whereArgs: [policyId, 'OPEN'],
      );
      await txn.update(
        'insurance_renewals',
        {'status': 'CANCELLED', 'updated_at': now},
        where: 'policy_id=?',
        whereArgs: [policyId],
      );

      await txn.insert(
          'insurance_financial_events',
          {
            'id': 'EVT:CANCEL:$policyId',
            'event_key': 'CANCEL:$policyId',
            'event_type': 'POLICY_CANCELLED',
            'source_type': 'INSURANCE_POLICY',
            'source_id': policyId,
            'policy_id': policyId,
            'amount': _n(policy['net_sale_amount']),
            'gl_entry_id': reversal,
            'reversal_of_event_id': 'EVT:POLICY:$policyId',
            'status': 'POSTED',
            'payload_json': jsonEncode({'reason': reason.trim()}),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort);

      await AuditTrailService.log(
        executor: txn,
        actorUserId: actor,
        action: 'INSURANCE_POLICY_CANCELLED',
        entityType: 'INSURANCE_POLICY',
        entityId: policyId,
        before: policy,
        after: (await txn.query(
          'insurance_policies',
          where: 'id=?',
          whereArgs: [policyId],
          limit: 1,
        ))
            .single,
        reason: reason.trim(),
        metadata: {'reversal_gl_entry_id': reversal},
      );
      return reversal;
    });
  }
}
