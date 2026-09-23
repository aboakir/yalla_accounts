import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
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
    this.source,
    this.responsibleUserId,
    this.currentCompany,
    this.lastContactAt,
    this.nextContactAt,
    this.contactResult,
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
  final String? source;
  final String? responsibleUserId;
  final String? currentCompany;
  final DateTime? lastContactAt;
  final DateTime? nextContactAt;
  final String? contactResult;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class InsuranceContactRecord {
  const InsuranceContactRecord({
    required this.id,
    required this.partyId,
    required this.contactAt,
    required this.channel,
    required this.createdAt,
    this.result,
    this.notes,
    this.nextFollowUpAt,
  });

  final String id;
  final String partyId;
  final DateTime contactAt;
  final String channel;
  final String? result;
  final String? notes;
  final DateTime? nextFollowUpAt;
  final DateTime createdAt;
}

class InsuranceDrivingLicenseRecord {
  const InsuranceDrivingLicenseRecord({
    required this.id,
    required this.partyId,
    required this.licenseNumber,
    required this.expiryDate,
    required this.categories,
    required this.createdAt,
    required this.updatedAt,
    this.licenseType,
    this.issueDate,
    this.notes,
  });

  final String id;
  final String partyId;
  final String licenseNumber;
  final String? licenseType;
  final DateTime? issueDate;
  final DateTime expiryDate;
  final List<String> categories;
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

  static const prospectStatuses = <String>{
    'PROSPECT',
    'CONTACTED',
    'NO_ANSWER',
    'WHATSAPP_SENT',
    'QUOTE_SENT',
    'INTERESTED',
    'NOT_INTERESTED',
    'FOLLOW_UP',
    'CONVERTED',
    'LOST',
    'REJECTED',
    'CLOSED',
    'CANCELLED',
  };

  static String _canonicalStatus(String value) {
    final status = value.trim().toUpperCase();
    if (!prospectStatuses.contains(status)) {
      throw ArgumentError('Unsupported insurance prospect status.');
    }
    return status;
  }

  static String _phoneIdentityKey(String value) =>
      YallaDigitNormalizer.normalize(value).replaceAll(RegExp(r'[^0-9]'), '');

  static String _insuredNameKey(String value) => YallaDigitNormalizer.normalize(
        value,
      ).trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static Future<List<InsuranceProspectRecord>> listProspects({
    DatabaseExecutor? executor,
    bool includeConverted = true,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceView);
    final db = executor ?? await DBService.database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.party_id, p.status, p.city, p.source,
             p.responsible_user_id, p.current_company,
             p.current_policy_expiry, p.vehicle_summary,
             p.last_contact_at, p.next_contact_at, p.contact_result,
             p.notes, p.created_at, p.updated_at,
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
      source: row['source']?.toString(),
      responsibleUserId: row['responsible_user_id']?.toString(),
      currentCompany: row['current_company']?.toString(),
      vehicleSummary: row['vehicle_summary']?.toString(),
      currentPolicyExpiry: parseOptional('current_policy_expiry'),
      lastContactAt: parseOptional('last_contact_at'),
      nextContactAt: parseOptional('next_contact_at'),
      contactResult: row['contact_result']?.toString(),
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
    String? source,
    String? responsibleUserId,
    String? currentCompany,
    DateTime? lastContactAt,
    DateTime? nextContactAt,
    String? contactResult,
    String? notes,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceCrmManage);
    final cleanName = name.trim();
    final rawPhone = phone.trim();
    final cleanPhone = _phoneIdentityKey(rawPhone);
    final canonicalStatus = _canonicalStatus(status);
    if (rawPhone.isNotEmpty && cleanPhone.isEmpty) {
      throw ArgumentError('Prospect phone must contain digits.');
    }
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
          'status': canonicalStatus,
          'city': city?.trim(),
          'source': source?.trim(),
          'responsible_user_id': responsibleUserId?.trim(),
          'current_company': currentCompany?.trim(),
          'current_policy_expiry': currentPolicyExpiry?.toIso8601String(),
          'last_contact_at': lastContactAt?.toIso8601String(),
          'next_contact_at': nextContactAt?.toIso8601String(),
          'contact_result': contactResult?.trim(),
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
      final matches = <Map<String, Object?>>[];
      for (final row in await db.query(
        'parties',
        columns: const ['id', 'display_name', 'phone'],
        where: 'is_active=1',
      )) {
        if (_phoneIdentityKey((row['phone'] ?? '').toString()) == phone) {
          matches.add(row);
        }
      }
      if (matches.length > 1) {
        throw StateError(
          'Multiple Party identities use this phone; merge them before CRM entry.',
        );
      }
      if (matches.length == 1) {
        final existingName =
            _insuredNameKey((matches.single['display_name'] ?? '').toString());
        final requestedName = _insuredNameKey(name);
        if (requestedName.isNotEmpty &&
            existingName.isNotEmpty &&
            requestedName != existingName) {
          throw StateError(
            'This phone belongs to a different Party identity.',
          );
        }
        return matches.single['id'].toString();
      }
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
    String? source,
    String? responsibleUserId,
    String? currentCompany,
    DateTime? lastContactAt,
    DateTime? nextContactAt,
    String? contactResult,
    String? notes,
    String? status,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceCrmManage);
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
      final rawPhone = phone.trim();
      final canonicalPhone = _phoneIdentityKey(rawPhone);
      if (rawPhone.isNotEmpty && canonicalPhone.isEmpty) {
        throw ArgumentError('Prospect phone must contain digits.');
      }
      if (canonicalPhone.isNotEmpty) {
        final conflicts = <Map<String, Object?>>[];
        for (final row in await txn.query(
          'parties',
          columns: const ['id', 'phone'],
          where: 'is_active=1 AND id<>?',
          whereArgs: [partyId],
        )) {
          if (_phoneIdentityKey((row['phone'] ?? '').toString()) ==
              canonicalPhone) {
            conflicts.add(row);
          }
        }
        if (conflicts.isNotEmpty) {
          throw StateError('This phone belongs to another Party identity.');
        }
      }

      final displayName = name.trim().isEmpty ? 'عميل محتمل' : name.trim();
      await txn.update(
        'parties',
        {
          'display_name': displayName,
          'phone': canonicalPhone.isEmpty ? null : canonicalPhone,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [partyId],
      );

      final customerRoles = await txn.query(
        'party_roles',
        columns: const ['legacy_id'],
        where: 'party_id=? AND role=?',
        whereArgs: [partyId, 'CUSTOMER'],
        limit: 1,
      );
      if (customerRoles.isNotEmpty) {
        final clientId = int.tryParse(
          customerRoles.single['legacy_id'].toString(),
        );
        if (clientId == null) {
          throw StateError('Customer Party role has an invalid client id.');
        }
        final changedClient = await txn.update(
          'clients',
          {
            'name': displayName,
            'phone': canonicalPhone.isEmpty ? null : canonicalPhone,
          },
          where: 'id=?',
          whereArgs: [clientId],
        );
        if (changedClient != 1) {
          throw StateError('Customer Party role points to a missing client.');
        }
      }

      final canonicalStatus = status == null
          ? rows.single['status'].toString()
          : _canonicalStatus(status);
      await txn.update(
        'insurance_prospects',
        {
          'status': canonicalStatus,
          'city': city?.trim(),
          'source': source?.trim(),
          'responsible_user_id': responsibleUserId?.trim(),
          'current_company': currentCompany?.trim(),
          'current_policy_expiry': currentPolicyExpiry?.toIso8601String(),
          'vehicle_summary': vehicleSummary?.trim(),
          'last_contact_at': lastContactAt?.toIso8601String(),
          'next_contact_at': nextContactAt?.toIso8601String(),
          'contact_result': contactResult?.trim(),
          'notes': notes?.trim(),
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  static Future<List<InsuranceContactRecord>> listContactHistory({
    required String prospectId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final prospect = await db.query(
      'insurance_prospects',
      columns: const ['party_id'],
      where: 'id=?',
      whereArgs: [prospectId.trim()],
      limit: 1,
    );
    if (prospect.isEmpty) {
      throw StateError('Insurance prospect not found.');
    }
    final partyId = prospect.single['party_id'].toString();
    final rows = await db.query(
      'insurance_contacts',
      where: 'party_id=?',
      whereArgs: [partyId],
      orderBy: 'contact_at DESC, created_at DESC',
    );
    DateTime date(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
    DateTime? optionalDate(Object? value) {
      final raw = value?.toString().trim() ?? '';
      return raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    return rows
        .map(
          (row) => InsuranceContactRecord(
            id: row['id'].toString(),
            partyId: partyId,
            contactAt: date(row['contact_at']),
            channel: row['channel'].toString(),
            result: row['result']?.toString(),
            notes: row['notes']?.toString(),
            nextFollowUpAt: optionalDate(row['next_follow_up_at']),
            createdAt: date(row['created_at']),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> recordContact({
    required String prospectId,
    required String channel,
    DateTime? contactAt,
    String? result,
    String? notes,
    DateTime? nextFollowUpAt,
    String? status,
    String? createdBy,
    DatabaseExecutor? database,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceCrmManage);
    final cleanChannel = channel.trim().toUpperCase();
    if (cleanChannel.isEmpty) {
      throw ArgumentError('Insurance contact channel is required.');
    }
    final db = database ?? await DBService.database;
    await SyncFoundationService.writeOn<void>(db, (txn) async {
      final rows = await txn.query(
        'insurance_prospects',
        columns: const ['party_id', 'status'],
        where: 'id=?',
        whereArgs: [prospectId.trim()],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Insurance prospect not found.');
      }
      final now = DateTime.now();
      final effectiveContactAt = contactAt ?? now;
      final partyId = rows.single['party_id'].toString();
      final canonicalStatus = status == null
          ? rows.single['status'].toString()
          : _canonicalStatus(status);

      await txn.insert('insurance_contacts', {
        'id': const Uuid().v4(),
        'party_id': partyId,
        'contact_at': effectiveContactAt.toIso8601String(),
        'channel': cleanChannel,
        'result': result?.trim(),
        'notes': notes?.trim(),
        'next_follow_up_at': nextFollowUpAt?.toIso8601String(),
        'created_by': createdBy?.trim(),
        'created_at': now.toIso8601String(),
      });
      await txn.update(
        'insurance_prospects',
        {
          'status': canonicalStatus,
          'last_contact_at': effectiveContactAt.toIso8601String(),
          'next_contact_at': nextFollowUpAt?.toIso8601String(),
          'contact_result': result?.trim(),
          'updated_at': now.toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [prospectId.trim()],
      );
    });
  }

  static Future<List<InsuranceDrivingLicenseRecord>> listDrivingLicenses({
    required String partyId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final rows = await db.query(
      'insurance_driver_licenses',
      where: 'party_id=?',
      whereArgs: [partyId.trim()],
      orderBy: 'expiry_date ASC, license_number ASC',
    );
    DateTime date(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
    DateTime? optionalDate(Object? value) {
      final raw = value?.toString().trim() ?? '';
      return raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    List<String> categories(Object? value) {
      final raw = value?.toString().trim() ?? '';
      if (raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((entry) => entry.toString())
              .where((entry) => entry.trim().isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
      return const [];
    }

    return rows
        .map(
          (row) => InsuranceDrivingLicenseRecord(
            id: row['id'].toString(),
            partyId: row['party_id'].toString(),
            licenseNumber: row['license_number'].toString(),
            licenseType: row['license_type']?.toString(),
            issueDate: optionalDate(row['issue_date']),
            expiryDate: date(row['expiry_date']),
            categories: categories(row['categories_json']),
            notes: row['notes']?.toString(),
            createdAt: date(row['created_at']),
            updatedAt: date(row['updated_at']),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> archiveProspect(String id) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceCrmManage);
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
    await AuthorizationGuard.require(PermissionKeys.insuranceCrmManage);
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
    await AuthorizationGuard.require(PermissionKeys.insuranceCrmManage);
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
