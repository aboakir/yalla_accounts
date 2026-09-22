import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/vehicle_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

class _ResolvedInsuranceCompany {
  const _ResolvedInsuranceCompany({
    required this.id,
    required this.partyId,
    required this.supplierId,
    required this.name,
    required this.defaultCommissionRate,
  });

  final int id;
  final String partyId;
  final int supplierId;
  final String name;
  final double defaultCommissionRate;
}

class _ResolvedProduct {
  const _ResolvedProduct({
    required this.id,
    required this.defaultCommissionRate,
  });

  final String id;
  final double defaultCommissionRate;
}

/// Bridges the policy wizard to the canonical Party, vehicle, accounting,
/// receipt and cheque cores. The legacy insurance child tables are used only
/// for non-posting installment/promissory schedules.
class InsurancePolicyService {
  InsurancePolicyService._();

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static Future<DateTime?> _postingDateForExistingOperation(
    DatabaseExecutor db,
    String operationId,
  ) async {
    final rows = await db.query(
      'insurance_policies',
      columns: const ['posting_request_json', 'gl_entry_id'],
      where: 'operation_id=?',
      whereArgs: [operationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = _clean(rows.single['posting_request_json']?.toString());
    if (raw == null) {
      final glId = (rows.single['gl_entry_id'] as num?)?.toInt();
      if (glId == null) {
        throw StateError('Posted policy has no canonical posting date.');
      }
      final glRows = await db.query(
        'gl_entries',
        columns: const ['date'],
        where: 'id=? AND source=?',
        whereArgs: [glId, 'INSURANCE_POLICY'],
        limit: 1,
      );
      final legacyDate = glRows.isEmpty
          ? null
          : DateTime.tryParse(glRows.single['date']?.toString() ?? '');
      if (legacyDate == null) {
        throw StateError('Posted policy has no canonical posting date.');
      }
      return legacyDate;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Posted policy has an invalid canonical request.');
    }
    final value = _clean(decoded['posting_date']?.toString());
    final parsed = value == null ? null : DateTime.tryParse(value);
    if (parsed == null) {
      throw StateError('Posted policy has no canonical posting date.');
    }
    return parsed;
  }

  static void _validateDraft(PolicyDraft draft) {
    final requiredText = <String, String?>{
      'Insurer policy number': draft.policyNumber,
      'Vehicle plate': draft.vehiclePlate ?? draft.vehicleNumber,
      'Vehicle make': draft.vehicleMake ?? draft.vehicleType,
      'Vehicle model year': draft.vehicleModelYear,
      'Engine capacity': draft.engineCc ?? draft.engineSize,
      'Insured name': draft.insuredName,
      'Insured phone': draft.insuredPhone,
      'Insurance company': draft.companyName,
    };
    for (final entry in requiredText.entries) {
      if (_clean(entry.value) == null) {
        throw ArgumentError('${entry.key} is required.');
      }
    }
    if (_clean(draft.productId) == null) {
      throw ArgumentError('Insurance product is required.');
    }
    final start = draft.startDate;
    final end = draft.endDate;
    if (start == null || end == null || !end.isAfter(start)) {
      throw ArgumentError('Policy end date must be after start date.');
    }
    final purchase = draft.buyPrice;
    final sale = draft.sellPrice;
    if (purchase == null || !purchase.isFinite || purchase < 0) {
      throw ArgumentError('Policy purchase price is invalid.');
    }
    if (sale == null || !sale.isFinite || sale <= 0) {
      throw ArgumentError('Policy sale price is invalid.');
    }
    final paymentIssues = draft.payment.validateAgainst(sale);
    if (paymentIssues.isNotEmpty) {
      throw StateError(paymentIssues.first);
    }
    final method = draft.payment.immediatePaymentMethod.trim().toUpperCase();
    if (method != 'CASH' && method != 'BANK') {
      throw StateError('Immediate policy payment must use CASH or BANK.');
    }
  }

  static Future<_ResolvedInsuranceCompany> _resolveCompanyOn(
    DatabaseExecutor db,
    PolicyDraft draft,
  ) async {
    final byId = draft.insuranceCompanyId;
    final rows = byId != null
        ? await db.query(
            'insurance_companies',
            where: 'id=? AND is_active=1',
            whereArgs: [byId],
            limit: 1,
          )
        : await db.rawQuery(
            '''SELECT * FROM insurance_companies
               WHERE TRIM(name)=? COLLATE NOCASE AND is_active=1
               ORDER BY id LIMIT 2''',
            [draft.companyName!.trim()],
          );
    if (rows.isEmpty) {
      throw StateError('Active insurance company was not found.');
    }
    if (rows.length > 1) {
      throw StateError('Insurance company name is ambiguous.');
    }

    final company = rows.single;
    final companyId = (company['id'] as num?)?.toInt() ??
        int.tryParse(company['id'].toString());
    if (companyId == null || companyId <= 0) {
      throw StateError('Insurance company has an invalid identity.');
    }
    final companyName = (company['name'] ?? '').toString().trim();
    var supplierId = (company['supplier_id'] as num?)?.toInt();
    if (supplierId == null || supplierId <= 0) {
      final suppliers = await db.rawQuery(
        'SELECT id FROM suppliers WHERE TRIM(name)=? COLLATE NOCASE LIMIT 1',
        [companyName],
      );
      if (suppliers.isEmpty) {
        supplierId = await db.insert(
          'suppliers',
          {'name': companyName},
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await db.update(
          'suppliers',
          {'pid': 'S${supplierId.toString().padLeft(4, '0')}'},
          where: 'id=?',
          whereArgs: [supplierId],
        );
      } else {
        supplierId = (suppliers.single['id'] as num).toInt();
      }
    }

    var supplierRoles = await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['SUPPLIER', supplierId.toString()],
      limit: 1,
    );
    if (supplierRoles.isEmpty) {
      final now = DateTime.now().toIso8601String();
      final partyId = 'SUPPLIER:$supplierId';
      await db.insert(
        'parties',
        {
          'id': partyId,
          'display_name': companyName,
          'role_codes': '[]',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.insert(
        'party_roles',
        {
          'party_id': partyId,
          'role': 'SUPPLIER',
          'legacy_id': supplierId.toString(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      supplierRoles = [
        {'party_id': partyId},
      ];
    }
    final partyId = supplierRoles.single['party_id'].toString();
    final party = await db.query(
      'parties',
      columns: const ['id'],
      where: 'id=? AND is_active=1',
      whereArgs: [partyId],
      limit: 1,
    );
    if (party.isEmpty) {
      throw StateError('Insurance-company Party is inactive or missing.');
    }

    final companyRoleByLegacyId = await db.query(
      'party_roles',
      columns: const ['party_id'],
      where: 'role=? AND legacy_id=?',
      whereArgs: ['INSURANCE_COMPANY', companyId.toString()],
      limit: 1,
    );
    final companyRoleOnSupplierParty = await db.query(
      'party_roles',
      columns: const ['legacy_id'],
      where: 'party_id=? AND role=?',
      whereArgs: [partyId, 'INSURANCE_COMPANY'],
      limit: 1,
    );
    if (companyRoleOnSupplierParty.isNotEmpty &&
        companyRoleOnSupplierParty.single['legacy_id'].toString() !=
            companyId.toString()) {
      throw StateError('Insurance-company Party is linked to another company.');
    }
    if (companyRoleByLegacyId.isNotEmpty &&
        companyRoleByLegacyId.single['party_id'].toString() != partyId) {
      await db.delete(
        'party_roles',
        where: 'role=? AND legacy_id=? AND party_id=?',
        whereArgs: [
          'INSURANCE_COMPANY',
          companyId.toString(),
          companyRoleByLegacyId.single['party_id'].toString(),
        ],
      );
    }
    if (companyRoleOnSupplierParty.isEmpty) {
      await db.insert(
        'party_roles',
        {
          'party_id': partyId,
          'role': 'INSURANCE_COMPANY',
          'legacy_id': companyId.toString(),
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    await db.update(
      'insurance_companies',
      {
        'party_id': partyId,
        'supplier_id': supplierId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [companyId],
    );
    return _ResolvedInsuranceCompany(
      id: companyId,
      partyId: partyId,
      supplierId: supplierId,
      name: companyName,
      defaultCommissionRate: _number(company['default_commission_rate']),
    );
  }

  static String? _canonicalProductType(String? coverageType) {
    final raw = _clean(coverageType);
    if (raw == null) return null;
    final lower = raw.toLowerCase();
    if (raw.contains('شامل') || lower.contains('comprehensive')) {
      return 'COMPREHENSIVE';
    }
    if (raw.contains('طرف') || lower.contains('third')) {
      return 'THIRD_PARTY';
    }
    return raw.toUpperCase().replaceAll(RegExp(r'\s+'), '_');
  }

  static Future<_ResolvedProduct> _resolveProductOn(
    DatabaseExecutor db,
    PolicyDraft draft,
    int companyId,
  ) async {
    List<Map<String, Object?>> rows;
    final requestedId = _clean(draft.productId);
    if (requestedId != null) {
      rows = await db.query(
        'insurance_products',
        where: 'id=? AND company_id=? AND is_active=1',
        whereArgs: [requestedId, companyId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Selected insurance product is not active.');
      }
    } else {
      final productType = _canonicalProductType(draft.coverageType);
      if (productType == null) {
        throw StateError('Insurance product selection is required.');
      }
      rows = await db.query(
        'insurance_products',
        where: 'company_id=? AND UPPER(product_type)=? AND is_active=1',
        whereArgs: [companyId, productType],
        orderBy: 'id',
        limit: 2,
      );
      if (rows.isEmpty) {
        throw StateError('No active insurance product matches coverage type.');
      }
      if (rows.length > 1) {
        throw StateError('Insurance product mapping is ambiguous.');
      }
    }
    final row = rows.single;
    return _ResolvedProduct(
      id: row['id'].toString(),
      defaultCommissionRate: _number(row['default_commission_rate']),
    );
  }

  static Future<int> _resolveVehicleOn(
    DatabaseExecutor db,
    PolicyDraft draft,
    int clientId,
  ) async {
    final plate = (draft.vehiclePlate ?? draft.vehicleNumber ?? '').trim();
    final normalized = VehicleTables.normalizeNumber(plate);
    final existing = await db.query(
      VehicleTables.tableName,
      columns: const ['id', 'client_id', 'is_active'],
      where: 'normalized_number=?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      if ((existing.single['is_active'] as num?)?.toInt() == 0) {
        throw StateError('Inactive vehicle must be restored before insurance.');
      }
      final owner = (existing.single['client_id'] as num?)?.toInt();
      if (owner != null && owner != clientId) {
        throw StateError('Vehicle is linked to another canonical customer.');
      }
    }
    return VehicleService.upsertFromRepairOn(
      db,
      number: plate,
      type: (draft.vehicleMake ?? draft.vehicleType ?? '').trim(),
      model: (draft.vehicleModelYear ?? '').trim(),
      clientId: clientId,
    );
  }

  static List<ReceiptInstrumentInput> _initialReceiptInstruments(
    PolicyDraft draft,
    String operationId,
  ) {
    final plan = draft.payment;
    final instruments = <ReceiptInstrumentInput>[];
    if (plan.type == PolicyPaymentPlanType.cashOnly ||
        plan.type == PolicyPaymentPlanType.cashPlusCheques) {
      instruments.add(
        ReceiptInstrumentInput(
          instrumentKey: 'POLICY:$operationId:IMMEDIATE',
          method: plan.immediatePaymentMethod.trim().toLowerCase(),
          amount: plan.cashAmount!,
        ),
      );
    }
    if (plan.type == PolicyPaymentPlanType.chequesOnly ||
        plan.type == PolicyPaymentPlanType.cashPlusCheques) {
      for (final entry in plan.cheques.asMap().entries) {
        final cheque = entry.value;
        final key = 'POLICY:$operationId:CHEQUE:${entry.key + 1}';
        instruments.add(
          ReceiptInstrumentInput(
            instrumentKey: key,
            method: 'cheque',
            amount: cheque.amount!,
            chequeDraft: {
              'uuid': key,
              'instrument_key': key,
              'cheque_no': cheque.chequeNumber!.trim(),
              'drawer_name': cheque.drawerName!.trim(),
              'bank_name': cheque.bankName!.trim(),
              'issue_date': cheque.issueDate!.toIso8601String(),
              'due_date': cheque.dueDate!.toIso8601String(),
              if (_clean(cheque.imagePath) != null)
                'notes': 'Policy cheque image: ${cheque.imagePath!.trim()}',
            },
          ),
        );
      }
    }
    return instruments;
  }

  static InsurancePolicyPostingCommand _postingCommand({
    required PolicyDraft draft,
    required String operationId,
    required DateTime postingDate,
    required int clientId,
    required String insuredPartyId,
    required int vehicleId,
    required _ResolvedInsuranceCompany company,
    required _ResolvedProduct product,
    required List<InsuranceInstallmentScheduleInput> installments,
    required List<InsurancePromissoryScheduleInput> promissories,
  }) {
    return InsurancePolicyPostingCommand(
      operationId: operationId,
      documentNumber: _clean(draft.documentNumber),
      policyNumber: draft.policyNumber!.trim(),
      previousPolicyId: _clean(draft.previousPolicyId),
      clientId: clientId,
      insuredPartyId: insuredPartyId,
      vehicleId: vehicleId,
      vehiclePlate: _clean(draft.vehiclePlate ?? draft.vehicleNumber),
      vehicleMake: _clean(draft.vehicleMake ?? draft.vehicleType),
      vehicleModelYear: _clean(draft.vehicleModelYear),
      companyId: company.id.toString(),
      insurerPartyId: company.partyId,
      insurerSupplierId: company.supplierId,
      productId: product.id,
      coverageType: _clean(draft.coverageType),
      coverageIds: List.unmodifiable(draft.coverageIds),
      engineCc: _clean(draft.engineCc ?? draft.engineSize),
      engineNumber: _clean(draft.engineNumber),
      chassisNumber: _clean(draft.chassisNumber),
      isVip: draft.isVip,
      installments: installments,
      promissories: promissories,
      startDate: draft.startDate!,
      endDate: draft.endDate!,
      postingDate: postingDate,
      purchasePrice: draft.buyPrice!,
      salePrice: draft.sellPrice!,
      commissionRate: product.defaultCommissionRate,
      notes: _clean(draft.notes),
    );
  }

  static Never _retryMismatch() {
    throw StateError('Policy retry differs from original operation.');
  }

  static bool _sameText(String? left, Object? right) =>
      _clean(left)?.toLowerCase() == _clean(right?.toString())?.toLowerCase();

  static String _phoneKey(Object? value) =>
      (value ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');

  /// Saves and posts one wizard draft. Retrying the same draft returns the
  /// original policy; changing a material field while reusing operationId is
  /// rejected by the financial core.
  static Future<String> savePolicyDraft(
    PolicyDraft draft, {
    Database? database,
  }) async {
    final policyPostPermit = await AuthorizationGuard.issuePermit(
      PermissionKeys.insurancePolicyPost,
    );
    draft.syncLegacyFromNew();
    _validateDraft(draft);
    final operationId = _clean(draft.operationId) ?? const Uuid().v4();
    draft.operationId = operationId;
    final instruments = _initialReceiptInstruments(draft, operationId);
    final receiptAuthorization = instruments.isEmpty
        ? null
        : await PaymentService.preauthorizeInsuranceReceipt(
            includesCheque: instruments.any(
              (instrument) => instrument.chequeDraft != null,
            ),
          );
    final db = database ?? await DBService.database;
    final now = DateTime.now();
    final postingDate = draft.postingDate ??
        await _postingDateForExistingOperation(db, operationId) ??
        DateTime(now.year, now.month, now.day);
    draft.postingDate = postingDate;
    final installments = <InsuranceInstallmentScheduleInput>[
      for (final entry in draft.payment.installments.asMap().entries)
        InsuranceInstallmentScheduleInput(
          id: '$operationId:${entry.key + 1}',
          amount: entry.value.amount!,
          dueDate: entry.value.dueDate!,
          note: entry.value.note,
        ),
    ];
    final promissories = <InsurancePromissoryScheduleInput>[
      for (final entry in draft.payment.promissories.asMap().entries)
        InsurancePromissoryScheduleInput(
          id: '$operationId:${entry.key + 1}',
          amount: entry.value.amount!,
          dueDate: entry.value.dueDate!,
          imagePath: entry.value.imagePath,
        ),
    ];
    late InsurancePolicyPostingResult posted;
    late _ResolvedInsuranceCompany resolvedCompany;
    late _ResolvedProduct resolvedProduct;

    await SyncFoundationService.transaction(db, (txn) async {
      final existing = await txn.query(
        'insurance_policies',
        where: 'operation_id=?',
        whereArgs: [operationId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        int? integer(Object? value) => value is num
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '');
        final companyId = integer(row['insurance_company_id']);
        final clientId = integer(row['client_id']);
        final vehicleId = integer(row['vehicle_id']);
        final supplierId = integer(row['insurer_supplier_id']);
        final insuredPartyId = _clean(row['insured_party_id']?.toString());
        final insurerPartyId = _clean(row['insurer_party_id']?.toString());
        final productId = _clean(row['product_id']?.toString());
        if (companyId == null ||
            companyId <= 0 ||
            clientId == null ||
            clientId <= 0 ||
            vehicleId == null ||
            vehicleId <= 0 ||
            supplierId == null ||
            supplierId <= 0 ||
            insuredPartyId == null ||
            insurerPartyId == null ||
            productId == null) {
          throw StateError(
              'Policy exists in partial canonical identity state.');
        }
        if ((draft.insuranceCompanyId != null &&
                draft.insuranceCompanyId != companyId) ||
            !_sameText(draft.companyName, row['company_name']) ||
            !_sameText(draft.productId, productId) ||
            !_sameText(draft.insuredName, row['insured_name']) ||
            _phoneKey(draft.insuredPhone) != _phoneKey(row['insured_phone']) ||
            VehicleTables.normalizeNumber(
                  draft.vehiclePlate ?? draft.vehicleNumber ?? '',
                ) !=
                VehicleTables.normalizeNumber(
                  row['vehicle_plate']?.toString() ?? '',
                ) ||
            !_sameText(
              draft.vehicleMake ?? draft.vehicleType,
              row['vehicle_make'],
            ) ||
            !_sameText(draft.vehicleModelYear, row['vehicle_model_year'])) {
          _retryMismatch();
        }
        resolvedCompany = _ResolvedInsuranceCompany(
          id: companyId,
          partyId: insurerPartyId,
          supplierId: supplierId,
          name: row['company_name'].toString(),
          defaultCommissionRate: _number(row['commission_rate']),
        );
        resolvedProduct = _ResolvedProduct(
          id: productId,
          defaultCommissionRate: _number(row['commission_rate']),
        );
        posted = await InsuranceFinancialService.postPolicy(
          _postingCommand(
            draft: draft,
            operationId: operationId,
            postingDate: postingDate,
            clientId: clientId,
            insuredPartyId: insuredPartyId,
            vehicleId: vehicleId,
            company: resolvedCompany,
            product: resolvedProduct,
            installments: installments,
            promissories: promissories,
          ),
          database: txn,
          authorizationPermit: policyPostPermit,
        );
        if (instruments.isNotEmpty) {
          await InsuranceFinancialService.collectPolicy(
            operationId: 'POLICY:$operationId:INITIAL_RECEIPT',
            policyId: posted.policyId,
            date: postingDate,
            instruments: instruments,
            notes: _clean(draft.notes) ??
                'Initial receipt for ${posted.documentNumber}',
            database: txn,
            authorizationToken: receiptAuthorization,
          );
        }
        return;
      }

      final insured = await InsuranceCrmService.ensureInsuredCustomer(
        name: draft.insuredName!.trim(),
        phone: draft.insuredPhone!.trim(),
        executor: txn,
      );
      resolvedCompany = await _resolveCompanyOn(txn, draft);
      resolvedProduct = await _resolveProductOn(
        txn,
        draft,
        resolvedCompany.id,
      );
      final vehicleId = await _resolveVehicleOn(txn, draft, insured.clientId);

      posted = await InsuranceFinancialService.postPolicy(
        _postingCommand(
          draft: draft,
          operationId: operationId,
          postingDate: postingDate,
          clientId: insured.clientId,
          insuredPartyId: insured.partyId,
          vehicleId: vehicleId,
          company: resolvedCompany,
          product: resolvedProduct,
          installments: installments,
          promissories: promissories,
        ),
        database: txn,
        authorizationPermit: policyPostPermit,
      );

      if (instruments.isNotEmpty) {
        await InsuranceFinancialService.collectPolicy(
          operationId: 'POLICY:$operationId:INITIAL_RECEIPT',
          policyId: posted.policyId,
          date: postingDate,
          instruments: instruments,
          notes: _clean(draft.notes) ??
              'Initial receipt for ${posted.documentNumber}',
          database: txn,
          authorizationToken: receiptAuthorization,
        );
      }
    });

    draft.documentNumber = posted.documentNumber;
    draft.insuranceCompanyId = resolvedCompany.id;
    draft.companyName = resolvedCompany.name;
    draft.productId = resolvedProduct.id;
    return posted.policyId;
  }
}
