import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';

class InsuranceCompanyRecord {
  const InsuranceCompanyRecord({
    required this.id,
    required this.partyId,
    required this.supplierId,
    required this.code,
    required this.name,
    required this.defaultCommissionRate,
    required this.isActive,
    this.phone,
    this.address,
    this.payable = 0,
    this.paid = 0,
  });

  final int id;
  final String partyId;
  final int supplierId;
  final String code;
  final String name;
  final String? phone;
  final String? address;
  final double defaultCommissionRate;
  final bool isActive;
  final double payable;
  final double paid;
  double get outstanding => payable - paid;
}

class InsuranceProductRecord {
  const InsuranceProductRecord({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    required this.productType,
    required this.defaultCommissionRate,
    required this.isActive,
  });

  final String id;
  final int companyId;
  final String code;
  final String name;
  final String productType;
  final double defaultCommissionRate;
  final bool isActive;
}

class InsuranceMasterDataService {
  InsuranceMasterDataService._();

  static double _number(Object? raw) =>
      raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;

  static Future<List<InsuranceCompanyRecord>> listCompanies({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery('''
      SELECT c.id,c.party_id,c.supplier_id,c.code,c.name,c.phone,c.address,
             c.default_commission_rate,c.is_active,
             COALESCE(SUM(CASE WHEN p.posting_status='POSTED'
                              THEN p.net_insurer_payable ELSE 0 END),0) payable,
             COALESCE((
               SELECT SUM(ip.amount)
               FROM insurance_policy_payments ip
               JOIN insurance_policies pp ON pp.id=ip.policy_id
               WHERE pp.insurance_company_id=CAST(c.id AS TEXT)
                 AND ip.direction='INSURER_PAYMENT'
                 AND ip.status='POSTED'
             ),0) paid
      FROM insurance_companies c
      LEFT JOIN insurance_policies p
        ON p.insurance_company_id=CAST(c.id AS TEXT)
      WHERE c.party_id IS NOT NULL AND c.supplier_id IS NOT NULL
      GROUP BY c.id
      ORDER BY c.is_active DESC,c.name
    ''');
    return rows
        .map(
          (row) => InsuranceCompanyRecord(
            id: (row['id'] as num).toInt(),
            partyId: row['party_id'].toString(),
            supplierId: (row['supplier_id'] as num).toInt(),
            code: (row['code'] ?? '').toString(),
            name: (row['name'] ?? '').toString(),
            phone: row['phone']?.toString(),
            address: row['address']?.toString(),
            defaultCommissionRate: _number(row['default_commission_rate']),
            isActive: ((row['is_active'] as num?)?.toInt() ?? 1) == 1,
            payable: _number(row['payable']),
            paid: _number(row['paid']),
          ),
        )
        .toList();
  }

  static Future<InsuranceCompanyRecord> createCompany({
    required String code,
    required String name,
    String? phone,
    String? address,
    double defaultCommissionRate = 0,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    final cleanName = name.trim();
    if (cleanCode.isEmpty || cleanName.isEmpty) {
      throw ArgumentError('Insurance company code and name are required.');
    }
    if (!defaultCommissionRate.isFinite ||
        defaultCommissionRate < 0 ||
        defaultCommissionRate > 100) {
      throw ArgumentError('Commission rate must be between 0 and 100.');
    }

    final db = await DBService.database;
    late int companyId;
    await SyncFoundationService.transaction(db, (txn) async {
      final duplicate = await txn.rawQuery(
        '''SELECT id FROM insurance_companies
           WHERE UPPER(TRIM(code))=? OR TRIM(name)=? COLLATE NOCASE
           LIMIT 1''',
        [cleanCode, cleanName],
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Insurance company code/name already exists.');
      }

      final suppliers = await txn.rawQuery(
        'SELECT id FROM suppliers WHERE TRIM(name)=? COLLATE NOCASE LIMIT 1',
        [cleanName],
      );
      late int supplierId;
      if (suppliers.isEmpty) {
        supplierId = await txn.insert('suppliers', {
          'name': cleanName,
          'phone': phone?.trim(),
          'address': address?.trim(),
        });
        await txn.update(
          'suppliers',
          {'pid': 'S${supplierId.toString().padLeft(4, '0')}'},
          where: 'id=?',
          whereArgs: [supplierId],
        );
      } else {
        supplierId = (suppliers.single['id'] as num).toInt();
      }

      var partyRows = await txn.query(
        'party_roles',
        columns: const ['party_id'],
        where: 'role=? AND legacy_id=?',
        whereArgs: ['SUPPLIER', supplierId.toString()],
        limit: 1,
      );
      if (partyRows.isEmpty) {
        final partyId = 'SUPPLIER:$supplierId';
        final now = DateTime.now().toIso8601String();
        await txn.insert(
          'parties',
          {
            'id': partyId,
            'display_name': cleanName,
            'phone': phone?.trim(),
            'address': address?.trim(),
            'role_codes': '[]',
            'is_active': 1,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.insert('party_roles', {
          'party_id': partyId,
          'role': 'SUPPLIER',
          'legacy_id': supplierId.toString(),
          'created_at': now,
        });
        partyRows = [
          {'party_id': partyId}
        ];
      }
      final partyId = partyRows.single['party_id'].toString();
      final now = DateTime.now().toIso8601String();

      companyId = await txn.insert('insurance_companies', {
        'party_id': partyId,
        'supplier_id': supplierId,
        'code': cleanCode,
        'name': cleanName,
        'phone': phone?.trim(),
        'address': address?.trim(),
        'default_commission_rate': defaultCommissionRate,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert(
        'party_roles',
        {
          'party_id': partyId,
          'role': 'INSURANCE_COMPANY',
          'legacy_id': companyId.toString(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });

    return (await listCompanies()).firstWhere((row) => row.id == companyId);
  }

  static Future<void> updateCompany({
    required int companyId,
    required String code,
    required String name,
    String? phone,
    String? address,
    required double defaultCommissionRate,
    bool isActive = true,
  }) async {
    final db = await DBService.database;
    await SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.query(
        'insurance_companies',
        columns: const ['party_id', 'supplier_id'],
        where: 'id=?',
        whereArgs: [companyId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Insurance company not found.');
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'insurance_companies',
        {
          'code': code.trim().toUpperCase(),
          'name': name.trim(),
          'phone': phone?.trim(),
          'address': address?.trim(),
          'default_commission_rate': defaultCommissionRate,
          'is_active': isActive ? 1 : 0,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [companyId],
      );
      await txn.update(
        'parties',
        {
          'display_name': name.trim(),
          'phone': phone?.trim(),
          'address': address?.trim(),
          'is_active': isActive ? 1 : 0,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [rows.single['party_id']],
      );
      await txn.update(
        'suppliers',
        {
          'name': name.trim(),
          'phone': phone?.trim(),
          'address': address?.trim(),
        },
        where: 'id=?',
        whereArgs: [rows.single['supplier_id']],
      );
    });
  }

  static Future<InsuranceProductRecord> createProduct({
    required int companyId,
    required String code,
    required String name,
    required String productType,
    double defaultCommissionRate = 0,
  }) async {
    final db = await DBService.database;
    final company = await db.query(
      'insurance_companies',
      columns: const ['id'],
      where: 'id=? AND is_active=1',
      whereArgs: [companyId],
      limit: 1,
    );
    if (company.isEmpty) throw StateError('Active insurance company required.');

    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('insurance_products', {
      'id': id,
      'company_id': companyId,
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'product_type': productType.trim().toUpperCase(),
      'default_commission_rate': defaultCommissionRate,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    return (await listProducts(companyId: companyId))
        .firstWhere((row) => row.id == id);
  }

  static Future<List<InsuranceProductRecord>> listProducts({
    required int companyId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.query(
      'insurance_products',
      where: 'company_id=?',
      whereArgs: [companyId],
      orderBy: 'is_active DESC,name',
    );
    return rows
        .map(
          (row) => InsuranceProductRecord(
            id: row['id'].toString(),
            companyId: (row['company_id'] as num).toInt(),
            code: row['code'].toString(),
            name: row['name'].toString(),
            productType: row['product_type'].toString(),
            defaultCommissionRate:
                _number(row['default_commission_rate']),
            isActive: ((row['is_active'] as num?)?.toInt() ?? 1) == 1,
          ),
        )
        .toList();
  }

  static Future<String> createCoverage({
    required String productId,
    required String code,
    required String name,
    double deductible = 0,
    double? limitAmount,
    String? description,
  }) async {
    final db = await DBService.database;
    final product = await db.query(
      'insurance_products',
      columns: const ['id'],
      where: 'id=? AND is_active=1',
      whereArgs: [productId],
      limit: 1,
    );
    if (product.isEmpty) throw StateError('Active insurance product required.');
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('insurance_coverages', {
      'id': id,
      'product_id': productId,
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'description': description?.trim(),
      'deductible': deductible,
      'limit_amount': limitAmount,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }
}
