import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class InsuranceProspectRecord {
  const InsuranceProspectRecord({
    required this.id,
    required this.partyId,
    required this.name,
    required this.phone,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.vehicleSummary,
    this.currentPolicyExpiry,
    this.city,
    this.notes,
  });

  final String id;
  final String partyId;
  final String name;
  final String phone;
  final String status;
  final String? vehicleSummary;
  final DateTime? currentPolicyExpiry;
  final String? city;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class InsuranceInsuredIdentity {
  const InsuranceInsuredIdentity({
    required this.partyId,
    required this.clientId,
  });

  final String partyId;
  final int clientId;
}

class InsuranceCrmService {
  InsuranceCrmService._();

  static String _phoneIdentityKey(String value) =>
      YallaDigitNormalizer.normalize(value).replaceAll(RegExp(r'[^0-9]'), '');

  static String _insuredNameKey(String value) => YallaDigitNormalizer.normalize(
        value,
      ).trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static Future<List<InsuranceProspectRecord>> listProspects({
    DatabaseExecutor? executor,
    bool includeConverted = true,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.party_id, p.status, p.city, p.current_policy_expiry,
             p.vehicle_summary, p.notes, p.created_at, p.updated_at,
             m.display_name, m.phone
      FROM insurance_prospects p
      JOIN parties m ON m.id=p.party_id
      WHERE p.status <> 'ARCHIVED'
        AND (?=1 OR p.status <> 'CONVERTED')
      ORDER BY
        CASE WHEN p.current_policy_expiry IS NULL THEN 1 ELSE 0 END,
        p.current_policy_expiry ASC,
        p.updated_at DESC
    ''', [includeConverted ? 1 : 0]);
    return rows.map(_fromRow).toList();
  }

  static InsuranceProspectRecord _fromRow(Map<String, Object?> row) {
    DateTime parse(String key) =>
        DateTime.tryParse((row[key] ?? '').toString()) ?? DateTime(1970);
    DateTime? parseOptional(String key) {
      final raw = (row[key] ?? '').toString().trim();
      return raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    return InsuranceProspectRecord(
      id: row['id'].toString(),
      partyId: row['party_id'].toString(),
      name: (row['display_name'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      status: (row['status'] ?? 'PROSPECT').toString(),
      city: row['city']?.toString(),
      vehicleSummary: row['vehicle_summary']?.toString(),
      currentPolicyExpiry: parseOptional('current_policy_expiry'),
      notes: row['notes']?.toString(),
      createdAt: parse('created_at'),
      updatedAt: parse('updated_at'),
    );
  }

  static Future<InsuranceProspectRecord> createProspect({
    required String name,
    required String phone,
    String status = 'PROSPECT',
    String? vehicleSummary,
    DateTime? currentPolicyExpiry,
    String? city,
    String? notes,
  }) async {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    if (cleanName.isEmpty &&
        cleanPhone.isEmpty &&
        (vehicleSummary ?? '').trim().isEmpty &&
        currentPolicyExpiry == null) {
      throw ArgumentError('Prospect requires at least one identifying field.');
    }

    final db = await DBService.database;
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    await SyncFoundationService.transaction(db, (txn) async {
      final partyId = await _resolveOrCreateParty(
        txn,
        name: cleanName,
        phone: cleanPhone,
        fallbackId: id,
        now: now,
      );

      await txn.insert(
        'party_roles',
        {
          'party_id': partyId,
          'role': 'PROSPECT',
          'legacy_id': id,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await txn.insert(
        'insurance_prospects',
        {
          'id': id,
          'party_id': partyId,
          'status': status,
          'city': city?.trim(),
          'source': null,
          'responsible_user_id': null,
          'current_company': null,
          'current_policy_expiry': currentPolicyExpiry?.toIso8601String(),
          'last_contact_at': null,
          'next_contact_at': null,
          'contact_result': null,
          'tags_json': null,
          'vehicle_summary': vehicleSummary?.trim(),
          'notes': notes?.trim(),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });

    return (await listProspects()).firstWhere((row) => row.id == id);
  }

  static Future<String> _resolveOrCreateParty(
    DatabaseExecutor db, {
    required String name,
    required String phone,
    required String fallbackId,
    required String now,
  }) async {
    if (phone.isNotEmpty) {
      final byPhone = await db.query(
        'parties',
        columns: const ['id'],
        where: 'TRIM(phone)=? AND is_active=1',
        whereArgs: [phone],
        limit: 2,
      );
      if (byPhone.length == 1) return byPhone.single['id'].toString();
    }

    final partyId = 'PROSPECT:$fallbackId';
    await db.insert(
      'parties',
      {
        'id': partyId,
        'display_name': name.isEmpty ? 'عميل محتمل' : name,
        'phone': phone.isEmpty ? null : phone,
        'role_codes': '[]',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return partyId;
  }

  static Future<void> updateProspect({
    required String id,
    required String name,
    required String phone,
    String? vehicleSummary,
    DateTime? currentPolicyExpiry,
    String? city,
    String? notes,
    String? status,
  }) async {
    final db = await DBService.database;
    await SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.query(
        'insurance_prospects',
        columns: const ['party_id', 'status'],
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Insurance prospect not found.');
      final partyId = rows.single['party_id'].toString();
      final now = DateTime.now().toIso8601String();

      await txn.update(
        'parties',
        {
          'display_name': name.trim().isEmpty ? 'عميل محتمل' : name.trim(),
          'phone': phone.trim().isEmpty ? null : phone.trim(),
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [partyId],
      );
      await txn.update(
        'insurance_prospects',
        {
          'status': status ?? rows.single['status'],
          'city': city?.trim(),
          'current_policy_expiry': currentPolicyExpiry?.toIso8601String(),
          'vehicle_summary': vehicleSummary?.trim(),
          'notes': notes?.trim(),
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  static Future<void> archiveProspect(String id) async {
    final db = await DBService.database;
    await db.update(
      'insurance_prospects',
      {
        'status': 'ARCHIVED',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  static Future<int> convertToInsured(String prospectId) async {
    final db = await DBService.database;
    late int clientId;
    await SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.rawQuery('''
        SELECT p.party_id, m.display_name, m.phone
        FROM insurance_prospects p
        JOIN parties m ON m.id=p.party_id
        WHERE p.id=?
        LIMIT 1
      ''', [prospectId]);
      if (rows.isEmpty) throw StateError('Insurance prospect not found.');
      final partyId = rows.single['party_id'].toString();

      final customerRole = await txn.query(
        'party_roles',
        columns: const ['legacy_id'],
        where: 'party_id=? AND role=?',
        whereArgs: [partyId, 'CUSTOMER'],
        limit: 1,
      );
      if (customerRole.isNotEmpty) {
        clientId = int.parse(customerRole.single['legacy_id'].toString());
      } else {
        await txn.update(
          'party_projection_guard',
          {'suppressed': 1},
          where: 'singleton_id=1',
        );
        try {
          clientId = await txn.insert('clients', {
            'name': (rows.single['display_name'] ?? 'عميل').toString(),
            'type': 'individual',
            'phone': rows.single['phone']?.toString(),
          });
          final now = DateTime.now().toIso8601String();
          await txn.insert(
            'party_roles',
            {
              'party_id': partyId,
              'role': 'CUSTOMER',
              'legacy_id': clientId.toString(),
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } finally {
          await txn.update(
            'party_projection_guard',
            {'suppressed': 0},
            where: 'singleton_id=1',
          );
        }
      }

      final now = DateTime.now().toIso8601String();
      await txn.insert(
        'party_roles',
        {
          'party_id': partyId,
          'role': 'INSURED',
          'legacy_id': prospectId,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'insurance_prospects',
        {'status': 'CONVERTED', 'updated_at': now},
        where: 'id=?',
        whereArgs: [prospectId],
      );
    });
    return clientId;
  }

  static Future<InsuranceInsuredIdentity> ensureInsuredCustomer({
    required String name,
    required String phone,
    DatabaseExecutor? executor,
  }) async {
    final cleanName = name.trim();
    final canonicalPhone = _phoneIdentityKey(phone);
    if (cleanName.isEmpty || phone.trim().isEmpty) {
      throw ArgumentError('Insured name and phone are required.');
    }
    if (canonicalPhone.isEmpty) {
      throw ArgumentError('Insured phone must contain digits.');
    }

    final db = executor ?? await DBService.database;
    return SyncFoundationService.writeOn(db, (txn) async {
      final candidates = <String, Map<String, Object?>>{};
      for (final row in await txn.rawQuery('''
        SELECT p.id,
               p.display_name,
               p.phone,
               c.id AS client_id,
               c.name AS client_name,
               c.phone AS client_phone
        FROM parties p
        LEFT JOIN party_roles r
          ON r.party_id=p.id AND r.role='CUSTOMER'
        LEFT JOIN clients c
          ON CAST(c.id AS TEXT)=r.legacy_id
        WHERE p.is_active=1
      ''')) {
        final partyPhoneKey = _phoneIdentityKey(
          (row['phone'] ?? '').toString(),
        );
        final clientPhoneKey = _phoneIdentityKey(
          (row['client_phone'] ?? '').toString(),
        );
        if (partyPhoneKey == canonicalPhone ||
            clientPhoneKey == canonicalPhone) {
          candidates[row['id'].toString()] = row;
        }
      }

      final matches = candidates.values.toList(growable: false);
      if (matches.length > 1) {
        throw StateError(
          'Multiple Party identities use this phone; merge them before issuing.',
        );
      }
      if (matches.isNotEmpty) {
        final expectedName = _insuredNameKey(cleanName);
        final identityNames = <String>{
          _insuredNameKey((matches.single['display_name'] ?? '').toString()),
          if (matches.single['client_id'] != null)
            _insuredNameKey((matches.single['client_name'] ?? '').toString()),
        }..remove('');
        if (identityNames.any((existing) => existing != expectedName)) {
          throw StateError(
            'This phone belongs to a different insured Party identity.',
          );
        }
      }

      final now = DateTime.now().toIso8601String();
      late String partyId;
      String? prospectId;
      if (matches.isEmpty) {
        prospectId = const Uuid().v4();
        partyId = 'PROSPECT:$prospectId';
        await txn.insert(
          'parties',
          {
            'id': partyId,
            'display_name': cleanName,
            'phone': canonicalPhone,
            'role_codes': '[]',
            'is_active': 1,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await txn.insert(
          'party_roles',
          {
            'party_id': partyId,
            'role': 'PROSPECT',
            'legacy_id': prospectId,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await txn.insert(
          'insurance_prospects',
          {
            'id': prospectId,
            'party_id': partyId,
            'status': 'PROSPECT',
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        partyId = matches.single['id'].toString();
        final prospects = await txn.query(
          'insurance_prospects',
          columns: const ['id'],
          where: 'party_id=?',
          whereArgs: [partyId],
          limit: 1,
        );
        if (prospects.isNotEmpty) {
          prospectId = prospects.single['id'].toString();
        }
        await txn.update(
          'parties',
          {
            'phone': canonicalPhone,
            'updated_at': now,
          },
          where: 'id=?',
          whereArgs: [partyId],
        );
      }

      final customerRoles = await txn.query(
        'party_roles',
        columns: const ['legacy_id'],
        where: 'party_id=? AND role=?',
        whereArgs: [partyId, 'CUSTOMER'],
        limit: 1,
      );
      late int clientId;
      if (customerRoles.isNotEmpty) {
        clientId = int.parse(customerRoles.single['legacy_id'].toString());
        final client = await txn.query(
          'clients',
          columns: const ['id', 'name'],
          where: 'id=?',
          whereArgs: [clientId],
          limit: 1,
        );
        if (client.isEmpty) {
          throw StateError('Customer Party role points to a missing client.');
        }
        if (_insuredNameKey(client.single['name'].toString()) !=
            _insuredNameKey(cleanName)) {
          throw StateError(
            'This phone belongs to a different insured customer.',
          );
        }
        await txn.update(
          'clients',
          {'phone': canonicalPhone},
          where: 'id=?',
          whereArgs: [clientId],
        );
      } else {
        final guard = await txn.query(
          'party_projection_guard',
          columns: const ['suppressed'],
          where: 'singleton_id=1',
          limit: 1,
        );
        final oldSuppressed = guard.isEmpty
            ? 0
            : ((guard.single['suppressed'] as num?)?.toInt() ?? 0);
        await txn.update(
          'party_projection_guard',
          {'suppressed': 1},
          where: 'singleton_id=1',
        );
        try {
          clientId = await txn.insert(
            'clients',
            {'name': cleanName, 'type': 'individual', 'phone': canonicalPhone},
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          await txn.insert(
            'party_roles',
            {
              'party_id': partyId,
              'role': 'CUSTOMER',
              'legacy_id': clientId.toString(),
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } finally {
          await txn.update(
            'party_projection_guard',
            {'suppressed': oldSuppressed},
            where: 'singleton_id=1',
          );
        }
      }

      final insuredRole = await txn.query(
        'party_roles',
        columns: const ['legacy_id'],
        where: 'party_id=? AND role=?',
        whereArgs: [partyId, 'INSURED'],
        limit: 1,
      );
      if (insuredRole.isEmpty) {
        await txn.insert(
          'party_roles',
          {
            'party_id': partyId,
            'role': 'INSURED',
            'legacy_id': clientId.toString(),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      if (prospectId != null) {
        await txn.update(
          'insurance_prospects',
          {'status': 'CONVERTED', 'updated_at': now},
          where: 'id=?',
          whereArgs: [prospectId],
        );
      }
      return InsuranceInsuredIdentity(
        partyId: partyId,
        clientId: clientId,
      );
    });
  }

  static Future<void> upsertDrivingLicense({
    required String partyId,
    required String licenseNumber,
    String? licenseType,
    DateTime? issueDate,
    required DateTime expiryDate,
    List<String> categories = const [],
    String? notes,
  }) async {
    final cleanNumber = licenseNumber.trim();
    if (cleanNumber.isEmpty) throw ArgumentError('License number is required.');
    final db = await DBService.database;
    await SyncFoundationService.transaction(db, (txn) async {
      final now = DateTime.now().toIso8601String();
      final existing = await txn.query(
        'insurance_driver_licenses',
        columns: const ['id'],
        where: 'party_id=? AND license_number=?',
        whereArgs: [partyId, cleanNumber],
        limit: 1,
      );
      final data = {
        'party_id': partyId,
        'license_number': cleanNumber,
        'license_type': licenseType?.trim(),
        'issue_date': issueDate?.toIso8601String(),
        'expiry_date': expiryDate.toIso8601String(),
        'categories_json': categories.isEmpty ? null : jsonEncode(categories),
        'notes': notes?.trim(),
        'updated_at': now,
      };
      if (existing.isEmpty) {
        await txn.insert('insurance_driver_licenses', {
          'id': const Uuid().v4(),
          ...data,
          'documents_json': null,
          'created_at': now,
        });
      } else {
        await txn.update(
          'insurance_driver_licenses',
          data,
          where: 'id=?',
          whereArgs: [existing.single['id']],
        );
      }

      await txn.delete(
        'insurance_alerts',
        where: 'party_id=? AND alert_type LIKE ? AND status=?',
        whereArgs: [partyId, 'DRIVING_LICENSE%', 'OPEN'],
      );
      for (final days in const [60, 30, 14, 7, 3, 1, 0]) {
        final due = expiryDate.subtract(Duration(days: days));
        await txn.insert('insurance_alerts', {
          'id': 'LIC:$partyId:$cleanNumber:$days',
          'alert_type': 'DRIVING_LICENSE_EXPIRY',
          'party_id': partyId,
          'policy_id': null,
          'claim_id': null,
          'due_at': due.toIso8601String(),
          'status': 'OPEN',
          'severity': days <= 3 ? 'HIGH' : 'NORMAL',
          'message': days == 0
              ? 'تنتهي رخصة القيادة اليوم'
              : 'متبقي $days يوم على انتهاء رخصة القيادة',
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  }
}
