import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';

class PartySyncService {
  PartySyncService._();

  static Future<void> applyInbound(
    DatabaseExecutor executor,
    InboundSyncChange change,
  ) async {
    if (executor is! Transaction) {
      throw ArgumentError('Party inbound sync requires a transaction.');
    }
    if (change.entityType != 'party') {
      throw StateError('SYNC_PARTY_UNSUPPORTED_ENTITY:${change.entityType}');
    }
    final payload = Map<String, Object?>.from(change.payload);
    final displayName = (payload['display_name'] ?? '').toString().trim();
    if (change.operation != 'DELETE' && displayName.isEmpty) {
      throw const FormatException('Party display_name is required.');
    }
    final roles = _roles(payload['role_codes']);
    final registry = await executor.query(
      SyncFoundationTables.registry,
      where: 'entity_type=? AND entity_uuid=?',
      whereArgs: ['party', change.entityUuid],
      limit: 1,
    );
    final existing = registry.isEmpty ? null : registry.single;
    if (existing == null && change.revision != 1) {
      throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
    }
    if (existing != null &&
        ((existing['revision'] as num?)?.toInt() ?? -1) + 1 !=
            change.revision) {
      throw StateError('SYNC_REMOTE_REVISION_CONFLICT');
    }
    final localId =
        existing?['local_id']?.toString() ?? 'SYNC:${change.entityUuid}';

    await SyncFoundationService.withRemoteMutation(
      executor,
      entityType: 'party',
      entityUuid: change.entityUuid,
      revision: change.revision,
      action: () async {
        await PartyTables.setLegacyProjectionSuppressed(executor, true);
        try {
          await _upsertParty(
              executor, change, payload, localId, displayName, roles);
          if (change.operation != 'DELETE') {
            await _reconcileLegacyRoles(
                executor, localId, displayName, payload, roles);
          }
        } finally {
          await PartyTables.setLegacyProjectionSuppressed(executor, false);
        }
      },
    );
  }

  static Set<String> _roles(Object? raw) {
    Object? decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      decoded = jsonDecode(raw);
    }
    if (decoded == null) return <String>{};
    if (decoded is! List) {
      throw const FormatException('Party role_codes must be a JSON list.');
    }
    final roles = decoded.map((e) => PartyTables.canonicalRole(e)).toSet();
    if (!PartyTables.supportedRoles.containsAll(roles)) {
      throw const FormatException('Party contains an unsupported role.');
    }
    return roles;
  }

  static Future<void> _upsertParty(
    DatabaseExecutor db,
    InboundSyncChange change,
    Map<String, Object?> payload,
    String localId,
    String displayName,
    Set<String> roles,
  ) async {
    final current = await db.query('parties',
        where: 'id=?', whereArgs: [localId], limit: 1);
    final name = displayName.isNotEmpty
        ? displayName
        : current.isNotEmpty
            ? current.single['display_name']!.toString()
            : 'Deleted Party ${change.entityUuid.substring(0, 8)}';
    final roleList = roles.toList()..sort();
    final values = <String, Object?>{
      'display_name': name,
      'phone': _text(payload['phone']),
      'email': _text(payload['email']),
      'address': _text(payload['address']),
      'notes': _text(payload['notes']),
      'role_codes': jsonEncode(roleList),
      'is_active':
          change.operation == 'DELETE' ? 0 : _active(payload['is_active']),
      'updated_at': change.occurredAt.toUtc().toIso8601String(),
    };
    if (current.isEmpty) {
      await db.insert('parties', {
        'id': localId,
        ...values,
        'merged_into_id': null,
        'created_at': _text(payload['created_at']) ??
            change.occurredAt.toUtc().toIso8601String(),
      });
    } else {
      await db.update('parties', values, where: 'id=?', whereArgs: [localId]);
    }
  }

  static int _active(Object? raw) {
    if (raw == null) return 1;
    if (raw == true || raw == 1 || raw.toString() == '1') return 1;
    if (raw == false || raw == 0 || raw.toString() == '0') return 0;
    throw const FormatException('Party is_active is invalid.');
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Future<void> _reconcileLegacyRoles(
    DatabaseExecutor db,
    String partyId,
    String displayName,
    Map<String, Object?> payload,
    Set<String> desired,
  ) async {
    for (final role in const ['CUSTOMER', 'SUPPLIER']) {
      final mappings = await db.query(
        'party_roles',
        where: 'party_id=? AND role=?',
        whereArgs: [partyId, role],
        limit: 1,
      );
      if (!desired.contains(role)) {
        if (mappings.isNotEmpty) {
          await db.delete('party_roles',
              where: 'party_id=? AND role=?', whereArgs: [partyId, role]);
        }
        continue;
      }
      final legacyId = mappings.isEmpty
          ? await _findOrCreateLegacy(db, partyId, role, displayName, payload)
          : mappings.single['legacy_id']!.toString();
      await _updateLegacy(db, role, legacyId, displayName, payload);
      if (mappings.isEmpty) {
        await db.insert('party_roles', {
          'party_id': partyId,
          'role': role,
          'legacy_id': legacyId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }
  }

  static Future<String> _findOrCreateLegacy(
    DatabaseExecutor db,
    String partyId,
    String role,
    String displayName,
    Map<String, Object?> payload,
  ) async {
    final table = role == 'CUSTOMER' ? 'clients' : 'suppliers';
    final matches = await db.rawQuery(
      'SELECT id FROM $table WHERE LOWER(TRIM(name))=LOWER(TRIM(?))',
      [displayName],
    );
    if (matches.length > 1) {
      throw StateError('SYNC_PARTY_LEGACY_NAME_AMBIGUOUS');
    }
    if (matches.isNotEmpty) {
      final id = matches.single['id']!.toString();
      final mapped = await db.query('party_roles',
          columns: ['party_id'],
          where: 'role=? AND legacy_id=?',
          whereArgs: [role, id],
          limit: 1);
      if (mapped.isNotEmpty && mapped.single['party_id'] != partyId) {
        throw StateError('SYNC_PARTY_LEGACY_NAME_CONFLICT');
      }
      return id;
    }
    if (role == 'CUSTOMER') {
      final id = await db.insert('clients', {
        'name': displayName,
        'type': 'أفراد',
        'phone': _text(payload['phone']) ?? '',
        'email': _text(payload['email']) ?? '',
        'address': _text(payload['address']) ?? '',
        'notes': _text(payload['notes']) ?? '',
      });
      return id.toString();
    }
    final id = await db.insert('suppliers', {
      'name': displayName,
      if (await _hasColumn(db, 'suppliers', 'phone'))
        'phone': _text(payload['phone']) ?? '',
      if (await _hasColumn(db, 'suppliers', 'address'))
        'address': _text(payload['address']) ?? '',
    });
    if (await _hasColumn(db, 'suppliers', 'pid')) {
      await db.update('suppliers', {'pid': 'S${id.toString().padLeft(4, '0')}'},
          where: 'id=?', whereArgs: [id]);
    }
    return id.toString();
  }

  static Future<void> _updateLegacy(
    DatabaseExecutor db,
    String role,
    String legacyId,
    String displayName,
    Map<String, Object?> payload,
  ) async {
    if (role == 'CUSTOMER') {
      await db.update(
          'clients',
          {
            'name': displayName,
            if (await _hasColumn(db, 'clients', 'phone'))
              'phone': _text(payload['phone']) ?? '',
            if (await _hasColumn(db, 'clients', 'email'))
              'email': _text(payload['email']) ?? '',
            if (await _hasColumn(db, 'clients', 'address'))
              'address': _text(payload['address']) ?? '',
            if (await _hasColumn(db, 'clients', 'notes'))
              'notes': _text(payload['notes']) ?? '',
          },
          where: 'id=?',
          whereArgs: [int.tryParse(legacyId) ?? legacyId]);
      return;
    }
    await db.update(
        'suppliers',
        {
          'name': displayName,
          if (await _hasColumn(db, 'suppliers', 'phone'))
            'phone': _text(payload['phone']) ?? '',
          if (await _hasColumn(db, 'suppliers', 'address'))
            'address': _text(payload['address']) ?? '',
        },
        where: 'id=?',
        whereArgs: [int.tryParse(legacyId) ?? legacyId]);
  }

  static Future<bool> _hasColumn(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name']?.toString() == column);
  }
}
