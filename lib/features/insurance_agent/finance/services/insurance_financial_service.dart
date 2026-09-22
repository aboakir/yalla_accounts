import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/document_number_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

import 'insurance_pricing_engine.dart';

class InsuranceInstallmentScheduleInput {
  const InsuranceInstallmentScheduleInput({
    required this.id,
    required this.amount,
    required this.dueDate,
    this.note,
  });

  final String id;
  final double amount;
  final DateTime dueDate;
  final String? note;
}

class InsurancePromissoryScheduleInput {
  const InsurancePromissoryScheduleInput({
    required this.id,
    required this.amount,
    required this.dueDate,
    this.imagePath,
  });

  final String id;
  final double amount;
  final DateTime dueDate;
  final String? imagePath;
}

class InsurancePolicyPostingCommand {
  const InsurancePolicyPostingCommand({
    required this.operationId,
    required this.policyNumber,
    this.documentNumber,
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
    this.previousPolicyId,
    this.vehicleId,
    this.vehiclePlate,
    this.vehicleMake,
    this.vehicleModelYear,
    this.productId,
    this.engineCc,
    this.engineNumber,
    this.chassisNumber,
    this.coverageType,
    this.coverageIds = const [],
    this.isVip = false,
    this.installments = const [],
    this.promissories = const [],
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
  final String? previousPolicyId;
  final String policyNumber;
  final String? documentNumber;
  final int clientId;
  final String insuredPartyId;
  final int? vehicleId;
  final String? vehiclePlate;
  final String? vehicleMake;
  final String? vehicleModelYear;
  final String companyId;
  final String insurerPartyId;
  final int insurerSupplierId;
  final String? productId;
  final String? engineCc;
  final String? engineNumber;
  final String? chassisNumber;
  final String? coverageType;
  final List<String> coverageIds;
  final bool isVip;
  final List<InsuranceInstallmentScheduleInput> installments;
  final List<InsurancePromissoryScheduleInput> promissories;
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
    required this.documentNumber,
    required this.glEntryId,
    required this.pricing,
    required this.wasExisting,
  });
  final String policyId;
  final String documentNumber;
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

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static void _validateSchedules(
    InsurancePolicyPostingCommand command,
    InsurancePricingResult pricing,
  ) {
    void validateIdsAndAmounts(
      Iterable<({String id, double amount, DateTime dueDate})> rows,
      String label,
    ) {
      final ids = <String>{};
      for (final row in rows) {
        if (row.id.trim().isEmpty || !ids.add(row.id.trim())) {
          throw StateError(
              '$label schedule keys must be non-empty and unique.');
        }
        final amount = InsurancePricingEngine.money(row.amount);
        if (!row.amount.isFinite || amount <= 0.005) {
          throw StateError('$label schedule amounts must be positive.');
        }
      }
    }

    validateIdsAndAmounts(
      command.installments
          .map((row) => (id: row.id, amount: row.amount, dueDate: row.dueDate)),
      'Installment',
    );
    validateIdsAndAmounts(
      command.promissories
          .map((row) => (id: row.id, amount: row.amount, dueDate: row.dueDate)),
      'Promissory-note',
    );

    void requireScheduleTotal(Iterable<double> amounts, String label) {
      final total = amounts.fold<double>(
        0,
        (sum, value) => sum + InsurancePricingEngine.money(value),
      );
      if ((InsurancePricingEngine.money(total) - pricing.netSaleAmount).abs() >
          0.005) {
        throw StateError('$label schedule must equal the policy sale amount.');
      }
    }

    if (command.installments.isNotEmpty) {
      requireScheduleTotal(
        command.installments.map((row) => row.amount),
        'Installment',
      );
    }
    if (command.promissories.isNotEmpty) {
      requireScheduleTotal(
        command.promissories.map((row) => row.amount),
        'Promissory-note',
      );
    }
  }

  static String _postingRequestJson(
    InsurancePolicyPostingCommand command,
    InsurancePricingResult pricing, {
    required String documentNumber,
  }) {
    final installments = [...command.installments]
      ..sort((a, b) => a.id.compareTo(b.id));
    final promissories = [...command.promissories]
      ..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode({
      'operation_id': command.operationId.trim(),
      'document_number': documentNumber,
      'policy_number': command.policyNumber.trim(),
      'previous_policy_id': _clean(command.previousPolicyId),
      'client_id': command.clientId,
      'insured_party_id': command.insuredPartyId.trim(),
      'vehicle_id': command.vehicleId,
      'vehicle_plate': _clean(command.vehiclePlate),
      'vehicle_make': _clean(command.vehicleMake),
      'vehicle_model_year': _clean(command.vehicleModelYear),
      'company_id': command.companyId.trim(),
      'insurer_party_id': command.insurerPartyId.trim(),
      'insurer_supplier_id': command.insurerSupplierId,
      'product_id': _clean(command.productId),
      'coverage_type': _clean(command.coverageType),
      'coverage_ids': [...command.coverageIds]..sort(),
      'is_vip': command.isVip,
      'engine_cc': _clean(command.engineCc),
      'engine_number': _clean(command.engineNumber),
      'chassis_number': _clean(command.chassisNumber),
      'start_date': command.startDate.toIso8601String(),
      'end_date': command.endDate.toIso8601String(),
      'posting_date': command.postingDate.toIso8601String(),
      'purchase_price': pricing.purchasePrice,
      'sale_price': pricing.salePrice,
      'base_premium': pricing.basePremium,
      'discount': pricing.discount,
      'fees': pricing.fees,
      'tax': pricing.tax,
      'commission_rate': pricing.commissionRate,
      'direct_cost': pricing.directCost,
      'currency': command.currency.trim().toUpperCase(),
      'notes': _clean(command.notes),
      'installments': [
        for (final row in installments)
          {
            'id': row.id.trim(),
            'amount': InsurancePricingEngine.money(row.amount),
            'due_date': row.dueDate.toIso8601String(),
            'note': _clean(row.note),
          },
      ],
      'promissories': [
        for (final row in promissories)
          {
            'id': row.id.trim(),
            'amount': InsurancePricingEngine.money(row.amount),
            'due_date': row.dueDate.toIso8601String(),
            'image_path': _clean(row.imagePath),
          },
      ],
    });
  }

  static bool _sameMoney(Object? stored, double requested) =>
      (_n(stored) * 100).round() == (requested * 100).round();

  static bool _sameOptionalText(Object? stored, String? requested) =>
      _clean(stored?.toString()) == _clean(requested);

  static bool _sameOptionalInt(Object? stored, int? requested) {
    final value =
        stored is num ? stored.toInt() : int.tryParse(stored?.toString() ?? '');
    return value == requested;
  }

  static bool _sameDate(Object? stored, DateTime requested) {
    final parsed = DateTime.tryParse(stored?.toString() ?? '');
    return parsed != null && parsed.isAtSameMomentAs(requested);
  }

  static bool _sameStringList(Object? stored, List<String> requested) {
    List<Object?> decoded;
    try {
      final value = jsonDecode(_clean(stored?.toString()) ?? '[]');
      if (value is! List) return false;
      decoded = value.cast<Object?>();
    } on FormatException {
      return false;
    }
    final storedValues = decoded
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList()
      ..sort();
    final requestedValues = requested
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList()
      ..sort();
    return jsonEncode(storedValues) == jsonEncode(requestedValues);
  }

  static Future<bool> _matchesLegacySchedules(
    DatabaseExecutor db,
    String policyId,
    InsurancePolicyPostingCommand command,
  ) async {
    final storedInstallments = await db.query(
      'insurance_policy_installments',
      columns: const ['id', 'amount', 'due_date', 'note'],
      where: 'policy_id=?',
      whereArgs: [policyId],
    );
    if (storedInstallments.length != command.installments.length) return false;
    final installmentById = {
      for (final row in storedInstallments) row['id'].toString(): row,
    };
    for (final requested in command.installments) {
      final row = installmentById['INST:$policyId:${requested.id.trim()}'];
      if (row == null ||
          !_sameMoney(row['amount'], requested.amount) ||
          !_sameDate(row['due_date'], requested.dueDate) ||
          !_sameOptionalText(row['note'], requested.note)) {
        return false;
      }
    }

    final storedPromissories = await db.query(
      'insurance_policy_promissories',
      columns: const ['id', 'amount', 'due_date', 'image_path'],
      where: 'policy_id=?',
      whereArgs: [policyId],
    );
    if (storedPromissories.length != command.promissories.length) return false;
    final promissoryById = {
      for (final row in storedPromissories) row['id'].toString(): row,
    };
    for (final requested in command.promissories) {
      final row = promissoryById['PROM:$policyId:${requested.id.trim()}'];
      if (row == null ||
          !_sameMoney(row['amount'], requested.amount) ||
          !_sameDate(row['due_date'], requested.dueDate) ||
          !_sameOptionalText(row['image_path'], requested.imagePath)) {
        return false;
      }
    }
    return true;
  }

  /// Upgrade the idempotency fingerprint lazily for policies posted by the
  /// first v85 financial core. Those rows have immutable GL/AR/AP evidence but
  /// predate posting_request_json and the Phase 10 wizard-only fields.
  static Future<bool> _matchesLegacyV85Posting(
    DatabaseExecutor db,
    Map<String, Object?> row,
    InsurancePolicyPostingCommand command,
    InsurancePricingResult pricing,
  ) async {
    if (command.policyId?.trim().isNotEmpty == true &&
        command.policyId!.trim() != row['id']?.toString()) {
      return false;
    }
    final glId = (row['gl_entry_id'] as num?)?.toInt();
    if (glId == null) return false;
    final glRows = await db.query(
      'gl_entries',
      columns: const ['date'],
      where: 'id=? AND source=? AND source_id=?',
      whereArgs: [glId, 'INSURANCE_POLICY', row['id']?.toString()],
      limit: 1,
    );
    if (glRows.isEmpty ||
        !_sameDate(glRows.single['date'], command.postingDate)) {
      return false;
    }

    final policyId = row['id']?.toString() ?? '';
    if (policyId.isEmpty ||
        !await _matchesLegacySchedules(db, policyId, command)) {
      return false;
    }

    return row['policy_number']?.toString() == command.policyNumber.trim() &&
        _sameOptionalText(
            row['previous_policy_id'], command.previousPolicyId) &&
        (row['client_id'] as num?)?.toInt() == command.clientId &&
        row['insured_party_id']?.toString() == command.insuredPartyId.trim() &&
        _sameOptionalInt(row['vehicle_id'], command.vehicleId) &&
        VehicleTables.normalizeNumber(
              row['vehicle_plate']?.toString() ?? '',
            ) ==
            VehicleTables.normalizeNumber(command.vehiclePlate ?? '') &&
        _sameOptionalText(row['vehicle_make'], command.vehicleMake) &&
        _sameOptionalText(
            row['vehicle_model_year'], command.vehicleModelYear) &&
        row['insurance_company_id']?.toString() == command.companyId.trim() &&
        row['insurer_party_id']?.toString() == command.insurerPartyId.trim() &&
        (row['insurer_supplier_id'] as num?)?.toInt() ==
            command.insurerSupplierId &&
        _sameOptionalText(row['product_id'], command.productId) &&
        _sameOptionalText(row['coverage_type'], command.coverageType) &&
        _sameStringList(row['coverage_ids_json'], command.coverageIds) &&
        ((row['is_vip'] as num?)?.toInt() ?? 0) == (command.isVip ? 1 : 0) &&
        _sameOptionalText(row['engine_cc'], command.engineCc) &&
        _sameOptionalText(row['engine_number'], command.engineNumber) &&
        _sameOptionalText(row['chassis_number'], command.chassisNumber) &&
        _sameDate(row['start_date'], command.startDate) &&
        _sameDate(row['end_date'], command.endDate) &&
        _sameMoney(row['buy_price'], pricing.purchasePrice) &&
        _sameMoney(row['sell_price'], pricing.salePrice) &&
        _sameMoney(row['base_premium'], pricing.basePremium) &&
        _sameMoney(row['discount'], pricing.discount) &&
        _sameMoney(row['fees'], pricing.fees) &&
        _sameMoney(row['tax'], pricing.tax) &&
        (_n(row['commission_rate']) - pricing.commissionRate).abs() <
            0.000000001 &&
        _sameMoney(row['direct_cost'], pricing.directCost) &&
        _sameMoney(row['net_sale_amount'], pricing.netSaleAmount) &&
        _sameMoney(row['net_insurer_payable'], pricing.netInsurerPayable) &&
        (row['currency'] ?? 'ILS').toString().trim().toUpperCase() ==
            command.currency.trim().toUpperCase() &&
        _sameOptionalText(row['notes'], command.notes);
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

  static Future<InsurancePolicyPostingResult> postPolicy(
    InsurancePolicyPostingCommand command, {
    DatabaseExecutor? database,
    AuthorizationPermit? authorizationPermit,
  }) async {
    if (authorizationPermit == null) {
      await AuthorizationGuard.require(PermissionKeys.insurancePolicyPost);
    } else {
      AuthorizationGuard.consumePermit(
        authorizationPermit,
        PermissionKeys.insurancePolicyPost,
      );
    }
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
    _validateSchedules(command, pricing);

    final db = database ?? await DBService.database;
    final actor = command.createdBy?.trim().isNotEmpty == true
        ? command.createdBy!.trim()
        : (await CurrentUserContext.userId()) ?? 'OWNER_LOCAL';

    return SyncFoundationService.writeOn<InsurancePolicyPostingResult>(db, (
      txn,
    ) async {
      final existing = await txn.query(
        'insurance_policies',
        where: 'operation_id=?',
        whereArgs: [op],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        final storedDocument = _clean(row['document_number']?.toString());
        if (storedDocument == null) {
          throw StateError('Posted policy has no canonical document number.');
        }
        final requestedDocument = _clean(command.documentNumber);
        if (requestedDocument != null && requestedDocument != storedDocument) {
          throw StateError('Policy retry differs from original operation.');
        }
        final request = _postingRequestJson(
          command,
          pricing,
          documentNumber: storedDocument,
        );
        final storedRequest = _clean(row['posting_request_json']?.toString());
        if (storedRequest == null) {
          if (!await _matchesLegacyV85Posting(txn, row, command, pricing)) {
            throw StateError('Policy retry differs from original operation.');
          }
          final changed = await txn.update(
            'insurance_policies',
            {'posting_request_json': request},
            where:
                'id=? AND (posting_request_json IS NULL OR TRIM(posting_request_json)=?)',
            whereArgs: [row['id'], ''],
          );
          if (changed != 1) {
            throw StateError('Policy retry fingerprint upgrade failed.');
          }
        } else if (storedRequest != request) {
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
          documentNumber: storedDocument,
          glEntryId: gl,
          pricing: pricing,
          wasExisting: true,
        );
      }

      await _assertOpen(txn, command.postingDate);

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
      final insuredRoles = await txn.query(
        'party_roles',
        columns: const ['role', 'legacy_id'],
        where: 'party_id=? AND role IN (?,?)',
        whereArgs: [command.insuredPartyId.trim(), 'CUSTOMER', 'INSURED'],
      );
      final customerRoleMatches = insuredRoles.any(
        (row) =>
            row['role'] == 'CUSTOMER' &&
            row['legacy_id']?.toString() == command.clientId.toString(),
      );
      if (!customerRoleMatches ||
          !insuredRoles.any((row) => row['role'] == 'INSURED')) {
        throw StateError('Insured Party/customer roles do not match policy.');
      }
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
      final supplier = await txn.query(
        'suppliers',
        columns: const ['id'],
        where: 'id=?',
        whereArgs: [command.insurerSupplierId],
        limit: 1,
      );
      final companyRoles = await txn.query(
        'party_roles',
        columns: const ['role', 'legacy_id'],
        where: 'party_id=? AND role IN (?,?)',
        whereArgs: [
          command.insurerPartyId.trim(),
          'SUPPLIER',
          'INSURANCE_COMPANY',
        ],
      );
      if (supplier.isEmpty ||
          !companyRoles.any(
            (row) =>
                row['role'] == 'SUPPLIER' &&
                row['legacy_id']?.toString() ==
                    command.insurerSupplierId.toString(),
          ) ||
          !companyRoles.any(
            (row) =>
                row['role'] == 'INSURANCE_COMPANY' &&
                row['legacy_id']?.toString() == companyId,
          )) {
        throw StateError(
          'Insurance company must be one Supplier + Party + company role.',
        );
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
        final ownerClientId = (vehicle['client_id'] as num?)?.toInt();
        if (ownerClientId != null && ownerClientId != command.clientId) {
          throw StateError('Insurance vehicle belongs to another customer.');
        }
      }
      final previousPolicyId = _clean(command.previousPolicyId);
      if (previousPolicyId != null) {
        final previousRows = await txn.query(
          'insurance_policies',
          columns: const ['id', 'client_id', 'insured_party_id'],
          where: 'id=?',
          whereArgs: [previousPolicyId],
          limit: 1,
        );
        if (previousRows.isEmpty) {
          throw StateError('Previous insurance policy not found.');
        }
        final previous = previousRows.single;
        if ((previous['client_id'] as num?)?.toInt() != command.clientId ||
            previous['insured_party_id']?.toString() !=
                command.insuredPartyId.trim()) {
          throw StateError('Renewal must keep the canonical insured/customer.');
        }
        final priorRenewal = await txn.query(
          'insurance_renewals',
          columns: const ['new_policy_id'],
          where: 'policy_id=?',
          whereArgs: [previousPolicyId],
          limit: 1,
        );
        if (priorRenewal.isEmpty) {
          throw StateError('Previous policy has no renewal candidate.');
        }
        final linked = _clean(priorRenewal.single['new_policy_id']?.toString());
        if (linked != null && linked != _clean(command.policyId)) {
          throw StateError('Previous policy is already linked to a renewal.');
        }
      }
      Map<String, Object?>? productRow;
      if (command.productId?.trim().isNotEmpty == true) {
        final product = await txn.query(
          'insurance_products',
          columns: const ['id', 'company_id', 'product_type'],
          where: 'id=? AND is_active=1',
          whereArgs: [command.productId!.trim()],
          limit: 1,
        );
        if (product.isEmpty ||
            product.single['company_id']?.toString() != companyId) {
          throw StateError('Product does not belong to selected company.');
        }
        productRow = product.single;
      }
      final coverageIds = command.coverageIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (coverageIds.length != command.coverageIds.length) {
        throw StateError('Policy coverage keys must be non-empty and unique.');
      }
      if (coverageIds.isNotEmpty && productRow == null) {
        throw StateError('Policy coverages require a selected product.');
      }
      if (coverageIds.isNotEmpty) {
        final placeholders = List.filled(coverageIds.length, '?').join(',');
        final coverages = await txn.rawQuery(
          'SELECT id FROM insurance_coverages '
          'WHERE product_id=? AND is_active=1 AND id IN ($placeholders)',
          [command.productId!.trim(), ...coverageIds],
        );
        if (coverages.length != coverageIds.length) {
          throw StateError('Coverage does not belong to selected product.');
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
      final requestedDocument = _clean(command.documentNumber);
      final documentNumber = requestedDocument ??
          await DocumentNumberService.nextOn(
            txn,
            documentType: 'INSURANCE_POLICY',
          );
      if (requestedDocument != null) {
        await DocumentNumberService.advancePastOn(
          txn,
          documentType: 'INSURANCE_POLICY',
          documentNumber: requestedDocument,
        );
      }
      final postingRequest = _postingRequestJson(
        command,
        pricing,
        documentNumber: documentNumber,
      );
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
        'engine_cc': _clean(command.engineCc) ?? '',
        'engine_number': _clean(command.engineNumber),
        'chassis_number': _clean(command.chassisNumber),
        'insured_name':
            (insured['display_name'] ?? client['name'] ?? '').toString(),
        'insured_phone': (insured['phone'] ?? client['phone'] ?? '').toString(),
        'company_name': (company['name'] ?? '').toString(),
        'start_date': command.startDate.toIso8601String(),
        'end_date': command.endDate.toIso8601String(),
        'is_vip': command.isVip ? 1 : 0,
        'buy_price': pricing.purchasePrice,
        'sell_price': pricing.salePrice,
        'payment_type': 'canonical_receipt',
        'cash_amount': 0.0,
        'notes': command.notes,
        'operation_id': op,
        'document_number': documentNumber,
        'policy_number': number,
        'coverage_type': _clean(command.coverageType),
        'coverage_ids_json': jsonEncode([...coverageIds]..sort()),
        'posting_request_json': postingRequest,
        'status': 'ACTIVE',
        'previous_policy_id': _clean(command.previousPolicyId),
        'client_id': command.clientId,
        'insured_party_id': command.insuredPartyId.trim(),
        'vehicle_id': command.vehicleId,
        'insurance_company_id': companyId,
        'insurer_party_id': command.insurerPartyId.trim(),
        'insurer_supplier_id': command.insurerSupplierId,
        'product_id': _clean(command.productId),
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

      for (final schedule in command.installments) {
        await txn.insert(
          'insurance_policy_installments',
          {
            'id': 'INST:$policyId:${schedule.id.trim()}',
            'policy_id': policyId,
            'amount': InsurancePricingEngine.money(schedule.amount),
            'due_date': schedule.dueDate.toIso8601String(),
            'note': _clean(schedule.note),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final schedule in command.promissories) {
        await txn.insert(
          'insurance_policy_promissories',
          {
            'id': 'PROM:$policyId:${schedule.id.trim()}',
            'policy_id': policyId,
            'amount': InsurancePricingEngine.money(schedule.amount),
            'due_date': schedule.dueDate.toIso8601String(),
            'image_path': _clean(schedule.imagePath),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

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
        ref: documentNumber,
        source: 'INSURANCE_POLICY',
        sourceId: policyId,
        sourceNumber: documentNumber,
        createdBy: actor,
        note: 'إصدار بوليصة تأمين — $documentNumber / $number',
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

      if (previousPolicyId != null) {
        final changed = await txn.update(
          'insurance_renewals',
          {
            'status': 'RENEWED',
            'outcome': 'RENEWED',
            'new_policy_id': policyId,
            'updated_at': now,
          },
          where: 'policy_id=? AND (new_policy_id IS NULL OR new_policy_id=?)',
          whereArgs: [previousPolicyId, policyId],
        );
        if (changed != 1) {
          throw StateError(
              'Previous policy renewal link could not be recorded.');
        }
      }

      await txn.insert(
          'insurance_renewals',
          {
            'id': 'REN:$policyId',
            'policy_id': policyId,
            'previous_policy_id': _clean(command.previousPolicyId),
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
        metadata: {
          'gl_entry_id': glId,
          'operation_id': op,
          'document_number': documentNumber,
          'insurer_policy_number': number,
        },
      );

      return InsurancePolicyPostingResult(
        policyId: policyId,
        documentNumber: documentNumber,
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
    DatabaseExecutor? database,
    InsuranceReceiptAuthorizationToken? authorizationToken,
  }) {
    return PaymentService.insertCanonicalInsuranceReceipt(
      operationId: operationId,
      database: database,
      authorizationToken: authorizationToken,
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
      final livePayments = await txn.query(
        'insurance_policy_payments',
        columns: const ['id'],
        where: 'policy_id=? AND status=?',
        whereArgs: [policyId, 'POSTED'],
        limit: 1,
      );
      if (livePayments.isNotEmpty) {
        throw StateError(
          'Reverse all posted policy receipts and insurer payments before cancellation.',
        );
      }

      final reversal = await DBService.reverseEntryGLOn(
        txn,
        glId,
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
