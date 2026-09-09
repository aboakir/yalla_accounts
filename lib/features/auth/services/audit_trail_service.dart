import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/p16_security_tables.dart';

class AuditTrailService {
  AuditTrailService._();

  static Future<void> log({
    DatabaseExecutor? executor,
    String? actorUserId,
    String? actorRole,
    required String action,
    required String entityType,
    String? entityId,
    Object? before,
    Object? after,
    String? reason,
    Map<String, Object?>? metadata,
  }) async {
    final ex = executor ?? await DBService.database;
    await P16SecurityTables.ensure(ex);

    var actorId = actorUserId?.trim();
    var role = actorRole?.trim();
    actorId = (actorId == null || actorId.isEmpty)
        ? await CurrentUserContext.userId()
        : actorId;

    if ((role == null || role.isEmpty) && actorId != null) {
      try {
        final rows = await ex.query(
          'users',
          columns: const ['role'],
          where: 'id = ?',
          whereArgs: [actorId],
          limit: 1,
        );
        if (rows.isNotEmpty) role = rows.first['role']?.toString();
      } catch (_) {}
    }

    String? deviceId;
    try {
      final rows = await ex.query(
        'installation_identity',
        columns: const ['device_id'],
        where: 'singleton_id = 1',
        limit: 1,
      );
      if (rows.isNotEmpty) deviceId = rows.first['device_id']?.toString();
    } catch (_) {}

    String? sessionId;
    if (actorId != null) {
      try {
        final rows = await ex.query(
          'auth_sessions',
          columns: const ['id'],
          where: 'user_id = ? AND revoked_at IS NULL',
          whereArgs: [actorId],
          orderBy: 'created_at DESC',
          limit: 1,
        );
        if (rows.isNotEmpty) sessionId = rows.first['id']?.toString();
      } catch (_) {}
    }

    await ex.insert('app_audit_events', {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'actor_user_id': actorId,
      'actor_role': role,
      'action': action.trim(),
      'entity_type': entityType.trim(),
      'entity_id': entityId?.trim(),
      'before_json': _encode(before),
      'after_json': _encode(after),
      'reason': _blankToNull(reason),
      'device_id': deviceId,
      'session_id': sessionId,
      'metadata_json': _encode(metadata),
    });
  }

  static Future<List<Map<String, Object?>>> query({
    String? actorUserId,
    String? entityType,
    String? entityId,
    String? actionContains,
    DateTime? from,
    DateTime? to,
    int limit = 250,
  }) async {
    final db = await DBService.database;
    await P16SecurityTables.ensure(db);
    final where = <String>[];
    final args = <Object?>[];
    if ((actorUserId ?? '').trim().isNotEmpty) {
      where.add('actor_user_id = ?');
      args.add(actorUserId!.trim());
    }
    if ((entityType ?? '').trim().isNotEmpty) {
      where.add('entity_type = ?');
      args.add(entityType!.trim());
    }
    if ((entityId ?? '').trim().isNotEmpty) {
      where.add('entity_id = ?');
      args.add(entityId!.trim());
    }
    if ((actionContains ?? '').trim().isNotEmpty) {
      where.add('action LIKE ?');
      args.add('%${actionContains!.trim()}%');
    }
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.add('created_at <= ?');
      args.add(to.toUtc().toIso8601String());
    }
    return db.query(
      'app_audit_events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
      limit: limit.clamp(1, 1000),
    );
  }

  static String? _encode(Object? value) {
    if (value == null) return null;
    try {
      return jsonEncode(value);
    } catch (_) {
      return jsonEncode({'value': value.toString()});
    }
  }

  static String? _blankToNull(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
