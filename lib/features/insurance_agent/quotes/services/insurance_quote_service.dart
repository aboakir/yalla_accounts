import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_financial_service.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_pricing_engine.dart';

class InsuranceQuoteItemInput {
  const InsuranceQuoteItemInput({
    required this.companyId,
    required this.premium,
    required this.purchasePrice,
    required this.salePrice,
    this.productId,
    this.discount = 0,
    this.deductible = 0,
    this.commissionRate = 0,
    this.fees = 0,
    this.tax = 0,
    this.directCost = 0,
    this.coverageJson,
  });

  final int companyId;
  final String? productId;
  final double premium;
  final double purchasePrice;
  final double salePrice;
  final double discount;
  final double deductible;
  final double commissionRate;
  final double fees;
  final double tax;
  final double directCost;
  final String? coverageJson;

  double get finalPrice => salePrice - discount + fees + tax;
}

class InsuranceQuoteResult {
  const InsuranceQuoteResult({
    required this.quoteId,
    required this.quoteNumber,
    required this.itemIds,
  });

  final String quoteId;
  final String quoteNumber;
  final List<String> itemIds;
}

class InsuranceQuoteSummary {
  const InsuranceQuoteSummary({
    required this.id,
    required this.quoteNumber,
    required this.partyName,
    required this.status,
    required this.requestedAt,
    required this.itemCount,
    this.acceptedItemId,
    this.issuedPolicyId,
  });

  final String id;
  final String quoteNumber;
  final String partyName;
  final String status;
  final DateTime requestedAt;
  final int itemCount;
  final String? acceptedItemId;
  final String? issuedPolicyId;
}

class InsuranceQuoteItemRecord {
  const InsuranceQuoteItemRecord({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.status,
    required this.purchasePrice,
    required this.salePrice,
    required this.finalPrice,
    required this.discount,
    required this.commissionRate,
    this.productId,
    this.productName,
  });

  final String id;
  final int companyId;
  final String companyName;
  final String? productId;
  final String? productName;
  final String status;
  final double purchasePrice;
  final double salePrice;
  final double finalPrice;
  final double discount;
  final double commissionRate;
}

class InsuranceQuoteService {
  InsuranceQuoteService._();

  static Future<List<InsuranceQuoteSummary>> listQuotes({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery('''
      SELECT q.id,q.quote_number,q.status,q.requested_at,
             q.accepted_item_id,q.issued_policy_id,
             p.display_name AS party_name,
             COUNT(qi.id) AS item_count
      FROM insurance_quotes q
      JOIN parties p ON p.id=q.party_id
      LEFT JOIN insurance_quote_items qi ON qi.quote_id=q.id
      GROUP BY q.id
      ORDER BY q.requested_at DESC,q.id DESC
    ''');
    return rows
        .map((row) => InsuranceQuoteSummary(
              id: row['id'].toString(),
              quoteNumber: (row['quote_number'] ?? '').toString(),
              partyName: (row['party_name'] ?? '').toString(),
              status: (row['status'] ?? 'DRAFT').toString().toUpperCase(),
              requestedAt: DateTime.parse(row['requested_at'].toString()),
              itemCount: (row['item_count'] as num?)?.toInt() ?? 0,
              acceptedItemId: row['accepted_item_id']?.toString(),
              issuedPolicyId: row['issued_policy_id']?.toString(),
            ))
        .toList(growable: false);
  }

  static Future<List<InsuranceQuoteItemRecord>> listQuoteItems(
    String quoteId, {
    DatabaseExecutor? executor,
  }) async {
    final id = quoteId.trim();
    if (id.isEmpty) throw ArgumentError('Quote id is required.');
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery('''
      SELECT qi.id,qi.company_id,qi.product_id,qi.status,
             qi.purchase_price,qi.sale_price,qi.final_price,qi.discount,
             qi.commission_rate,c.name AS company_name,pr.name AS product_name
      FROM insurance_quote_items qi
      JOIN insurance_companies c ON c.id=qi.company_id
      LEFT JOIN insurance_products pr ON pr.id=qi.product_id
      WHERE qi.quote_id=?
      ORDER BY qi.created_at ASC,qi.id ASC
    ''', [id]);
    return rows
        .map((row) => InsuranceQuoteItemRecord(
              id: row['id'].toString(),
              companyId: (row['company_id'] as num).toInt(),
              companyName: (row['company_name'] ?? '').toString(),
              productId: row['product_id']?.toString(),
              productName: row['product_name']?.toString(),
              status: (row['status'] ?? 'OFFERED').toString().toUpperCase(),
              purchasePrice: (row['purchase_price'] as num).toDouble(),
              salePrice: (row['sale_price'] as num).toDouble(),
              finalPrice: (row['final_price'] as num).toDouble(),
              discount: (row['discount'] as num).toDouble(),
              commissionRate: (row['commission_rate'] as num).toDouble(),
            ))
        .toList(growable: false);
  }

  static Future<InsuranceQuoteResult> createQuote({
    required String quoteNumber,
    required String partyId,
    int? clientId,
    String? prospectId,
    int? vehicleId,
    required List<InsuranceQuoteItemInput> items,
    String? notes,
    String? createdBy,
  }) async {
    final cleanNumber = quoteNumber.trim();
    final cleanParty = partyId.trim();
    if (cleanNumber.isEmpty || cleanParty.isEmpty) {
      throw ArgumentError('Quote number and party are required.');
    }
    if (items.isEmpty) {
      throw StateError('Quote requires at least one company offer.');
    }

    final db = await DBService.database;
    final quoteId = const Uuid().v4();
    final itemIds = <String>[];
    await SyncFoundationService.transaction(db, (txn) async {
      final party = await txn.query(
        'parties',
        columns: const ['id'],
        where: 'id=? AND is_active=1',
        whereArgs: [cleanParty],
        limit: 1,
      );
      if (party.isEmpty) throw StateError('Quote party not found.');
      if (clientId != null) {
        final clients = await txn.query(
          'clients',
          columns: const ['id'],
          where: 'id=?',
          whereArgs: [clientId],
          limit: 1,
        );
        if (clients.isEmpty) throw StateError('Quote client not found.');
      }
      if (prospectId != null && prospectId.trim().isNotEmpty) {
        final prospects = await txn.query(
          'insurance_prospects',
          columns: const ['party_id'],
          where: 'id=?',
          whereArgs: [prospectId.trim()],
          limit: 1,
        );
        if (prospects.isEmpty ||
            prospects.single['party_id']?.toString() != cleanParty) {
          throw StateError('Quote prospect does not match Party Master.');
        }
      }
      if (vehicleId != null) {
        final vehicles = await txn.query(
          'vehicles',
          columns: const ['id'],
          where: 'id=?',
          whereArgs: [vehicleId],
          limit: 1,
        );
        if (vehicles.isEmpty) throw StateError('Quote vehicle not found.');
      }

      final now = DateTime.now().toIso8601String();
      await txn.insert('insurance_quotes', {
        'id': quoteId,
        'quote_number': cleanNumber,
        'prospect_id': prospectId?.trim(),
        'party_id': cleanParty,
        'client_id': clientId,
        'vehicle_id': vehicleId,
        'status': 'DRAFT',
        'requested_at': now,
        'accepted_item_id': null,
        'issued_policy_id': null,
        'notes': notes?.trim(),
        'created_by': createdBy,
        'created_at': now,
        'updated_at': now,
      });

      for (final input in items) {
        if (!input.finalPrice.isFinite ||
            input.finalPrice <= 0 ||
            !input.purchasePrice.isFinite ||
            input.purchasePrice < 0 ||
            !input.salePrice.isFinite ||
            input.salePrice <= 0 ||
            input.discount < 0 ||
            input.discount > input.salePrice) {
          throw StateError('Quote prices are invalid.');
        }
        final companies = await txn.query(
          'insurance_companies',
          columns: const ['id'],
          where: 'id=? AND is_active=1',
          whereArgs: [input.companyId],
          limit: 1,
        );
        if (companies.isEmpty) {
          throw StateError('Quote insurance company is not active.');
        }
        if (input.productId?.trim().isNotEmpty == true) {
          final products = await txn.query(
            'insurance_products',
            columns: const ['id', 'company_id'],
            where: 'id=? AND is_active=1',
            whereArgs: [input.productId!.trim()],
            limit: 1,
          );
          if (products.isEmpty ||
              (products.single['company_id'] as num).toInt() !=
                  input.companyId) {
            throw StateError('Quote product does not belong to company.');
          }
        }

        final itemId = const Uuid().v4();
        itemIds.add(itemId);
        final commissionAmount = input.premium * input.commissionRate / 100.0;
        await txn.insert('insurance_quote_items', {
          'id': itemId,
          'quote_id': quoteId,
          'company_id': input.companyId,
          'product_id': input.productId?.trim(),
          'premium': input.premium,
          'purchase_price': input.purchasePrice,
          'sale_price': input.salePrice,
          'discount': input.discount,
          'deductible': input.deductible,
          'commission_rate': input.commissionRate,
          'commission_amount':
              double.parse(commissionAmount.toStringAsFixed(2)),
          'fees': input.fees,
          'tax': input.tax,
          'direct_cost': input.directCost,
          'final_price': input.finalPrice,
          'coverage_json': input.coverageJson,
          'status': 'OFFERED',
          'created_at': now,
        });
      }
    });

    return InsuranceQuoteResult(
      quoteId: quoteId,
      quoteNumber: cleanNumber,
      itemIds: itemIds,
    );
  }

  static Future<void> acceptQuote({
    required String quoteId,
    required String itemId,
  }) async {
    final db = await DBService.database;
    await SyncFoundationService.transaction(db, (txn) async {
      final item = await txn.query(
        'insurance_quote_items',
        columns: const ['id'],
        where: 'id=? AND quote_id=?',
        whereArgs: [itemId, quoteId],
        limit: 1,
      );
      if (item.isEmpty) {
        throw StateError('Selected quote item does not belong to quote.');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'insurance_quote_items',
        {'status': 'DECLINED'},
        where: 'quote_id=?',
        whereArgs: [quoteId],
      );
      await txn.update(
        'insurance_quote_items',
        {'status': 'ACCEPTED'},
        where: 'id=?',
        whereArgs: [itemId],
      );
      await txn.update(
        'insurance_quotes',
        {
          'status': 'ACCEPTED',
          'accepted_item_id': itemId,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [quoteId],
      );
    });
  }

  static Future<InsurancePolicyPostingResult> issueAcceptedQuote({
    required String quoteId,
    required String policyNumber,
    required DateTime startDate,
    required DateTime endDate,
    required DateTime postingDate,
    String? createdBy,
  }) async {
    final db = await DBService.database;
    final rows = await db.rawQuery('''
      SELECT q.id quote_id,q.party_id,q.client_id,q.prospect_id,q.vehicle_id,
             q.status quote_status,q.issued_policy_id,q.accepted_item_id,
             qi.company_id,qi.product_id,qi.premium,qi.purchase_price,
             qi.sale_price,qi.discount,qi.commission_rate,qi.fees,qi.tax,
             qi.direct_cost,qi.final_price,
             c.party_id insurer_party_id,c.supplier_id,c.name company_name
      FROM insurance_quotes q
      JOIN insurance_quote_items qi ON qi.id=q.accepted_item_id
      JOIN insurance_companies c ON c.id=qi.company_id
      WHERE q.id=? LIMIT 1
    ''', [quoteId]);
    if (rows.isEmpty) throw StateError('Accepted quote not found.');
    final row = rows.single;
    final status = (row['quote_status'] ?? '').toString().toUpperCase();
    if (status == 'ISSUED') {
      final policyId = row['issued_policy_id']?.toString();
      if (policyId == null || policyId.isEmpty) {
        throw StateError('Issued quote has no policy link.');
      }
      final policies = await db.query(
        'insurance_policies',
        columns: const ['gl_entry_id', 'document_number'],
        where: 'id=?',
        whereArgs: [policyId],
        limit: 1,
      );
      if (policies.isEmpty) throw StateError('Issued quote policy is missing.');
      final glId = (policies.single['gl_entry_id'] as num?)?.toInt();
      if (glId == null) throw StateError('Issued quote policy is not posted.');
      final documentNumber =
          (policies.single['document_number'] ?? '').toString().trim();
      if (documentNumber.isEmpty) {
        throw StateError('Issued quote policy has no document number.');
      }
      return InsurancePolicyPostingResult(
        policyId: policyId,
        documentNumber: documentNumber,
        glEntryId: glId,
        pricing: InsurancePricingResult(
          purchasePrice: (row['purchase_price'] as num).toDouble(),
          salePrice: (row['final_price'] as num).toDouble(),
          basePremium: (row['premium'] as num).toDouble(),
          discount: 0,
          fees: (row['fees'] as num).toDouble(),
          tax: (row['tax'] as num).toDouble(),
          commissionRate: (row['commission_rate'] as num).toDouble(),
          commissionAmount: 0,
          directCost: (row['direct_cost'] as num).toDouble(),
          netSaleAmount: (row['final_price'] as num).toDouble(),
          netInsurerPayable: (row['purchase_price'] as num).toDouble(),
          grossProfit: 0,
          markupPercent: 0,
          marginPercent: 0,
        ),
        wasExisting: true,
      );
    }
    if (status != 'ACCEPTED') {
      throw StateError('Quote must be accepted before policy issuance.');
    }

    var clientId = (row['client_id'] as num?)?.toInt();
    if (clientId == null) {
      final prospectId = row['prospect_id']?.toString();
      if (prospectId == null || prospectId.isEmpty) {
        throw StateError('Quote needs a client or convertible prospect.');
      }
      clientId = await InsuranceCrmService.convertToInsured(prospectId);
      await db.update(
        'insurance_quotes',
        {
          'client_id': clientId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [quoteId],
      );
    }

    final result = await InsuranceFinancialService.postPolicy(
      InsurancePolicyPostingCommand(
        operationId: 'QUOTE:$quoteId',
        policyNumber: policyNumber,
        clientId: clientId,
        insuredPartyId: row['party_id'].toString(),
        vehicleId: (row['vehicle_id'] as num?)?.toInt(),
        companyId: row['company_id'].toString(),
        insurerPartyId: row['insurer_party_id'].toString(),
        insurerSupplierId: (row['supplier_id'] as num).toInt(),
        productId: row['product_id']?.toString(),
        startDate: startDate,
        endDate: endDate,
        postingDate: postingDate,
        purchasePrice: (row['purchase_price'] as num).toDouble(),
        salePrice: (row['sale_price'] as num).toDouble(),
        basePremium: (row['premium'] as num).toDouble(),
        discount: (row['discount'] as num).toDouble(),
        commissionRate: (row['commission_rate'] as num).toDouble(),
        fees: (row['fees'] as num).toDouble(),
        tax: (row['tax'] as num).toDouble(),
        directCost: (row['direct_cost'] as num).toDouble(),
        createdBy: createdBy,
      ),
    );

    await db.update(
      'insurance_quotes',
      {
        'status': 'ISSUED',
        'issued_policy_id': result.policyId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [quoteId],
    );
    return result;
  }
}
