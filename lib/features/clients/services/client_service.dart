// 📁 lib/features/clients/services/client_service.dart
//
// ClientService — ربط العملاء مع GL تلقائيًا (AR account) عبر DBService.
// - يضمن عمود account_id في clients.
// - عند insertClient و insertOrGetClientId: ينشئ حساب AR ويربطه.
// - متوافق مع StepBeneficiaryData.getClientNamesByType.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';

class DuplicateClientException implements Exception {
  const DuplicateClientException(this.name);

  final String name;

  @override
  String toString() => 'العميل $name موجود مسبقًا';
}

class ClientProfileSnapshot {
  const ClientProfileSnapshot({
    required this.repairCount,
    required this.vehicleCount,
    required this.vehicleNumbers,
    required this.recentRepairs,
  });

  final int repairCount;
  final int vehicleCount;
  final List<String> vehicleNumbers;
  final List<Map<String, dynamic>> recentRepairs;
}

class ClientService {
  static const String tableName = 'clients';

  /// إنشاء جدول العملاء + فهارس + ضمان account_id
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_name ON $tableName(LOWER(name));');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_type ON $tableName(type);');

    await _ensureAccountColumn(db);
  }

  static Future<void> _ensureAccountColumn(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info($tableName)');
    final has = info.any((c) => (c['name'] as String?) == 'account_id');
    if (!has) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN account_id INTEGER;');
    }
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_${tableName}_account ON $tableName(account_id);');
    } catch (_) {}
  }

  // ===================== CRUD =====================

  static Future<int> insertClient(Client client) async {
    final id = await DBService.inTx<int>((txn) async {
      await _ensureAccountColumn(txn);

      final duplicate = await findDuplicateIdOn(
        txn,
        client.name,
        type: client.type,
      );
      if (duplicate != null) {
        throw DuplicateClientException(client.name);
      }

      final id = await txn.insert(
        tableName,
        client.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await OfflineOutboxService.enqueue(
        txn,
        channel: OfflineOutboxService.channelSync,
        operation: 'UPSERT',
        entityType: 'client',
        entityId: id.toString(),
        idempotencyKey: 'client:$id:create',
        payload: {
          'schema': 1,
          'entity_type': 'client',
          'entity_id': id,
          'name': client.name.trim(),
          'type': client.type.trim(),
          'phone': client.phone.trim(),
          'email': client.email.trim(),
          'address': client.address.trim(),
          'notes': client.notes.trim(),
        },
      );

      return id;
    });

    // Preserve the established accounting behavior: the AR account remains a
    // separate accounting concern and is not changed by P05.
    try {
      await DBService.ensureClientAccount(id);
    } catch (_) {}

    return id;
  }

  static Future<int> updateClient(Client client) async {
    var id = client.id;
    if (id == null) {
      id = await getClientIdByName(client.name);
      if (id == null) {
        throw StateError('العميل غير موجود للتعديل');
      }
    }

    final clientId = id;
    final count = await DBService.inTx<int>((txn) async {
      await _ensureAccountColumn(txn);

      final duplicate = await findDuplicateIdOn(
        txn,
        client.name,
        type: client.type,
        excludeId: clientId,
      );
      if (duplicate != null) {
        throw DuplicateClientException(client.name);
      }

      final data = client.toMap()..remove('id');
      final changed = await txn.update(
        tableName,
        data,
        where: 'id = ?',
        whereArgs: [clientId],
      );

      if (changed > 0) {
        final now = DateTime.now().toUtc().toIso8601String();
        await OfflineOutboxService.enqueue(
          txn,
          channel: OfflineOutboxService.channelSync,
          operation: 'UPSERT',
          entityType: 'client',
          entityId: clientId.toString(),
          idempotencyKey: 'client:$clientId:update:$now',
          payload: {
            'schema': 1,
            'entity_type': 'client',
            'entity_id': clientId,
            'name': client.name.trim(),
            'type': client.type.trim(),
            'phone': client.phone.trim(),
            'email': client.email.trim(),
            'address': client.address.trim(),
            'notes': client.notes.trim(),
          },
        );
      }

      return changed;
    });

    try {
      final accId = await _getClientAccountId(clientId);
      if (accId == null) {
        await DBService.ensureClientAccount(clientId);
      }
    } catch (_) {}

    return count;
  }

  static Future<int> deleteClient(int id) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);

    final linkedRepairs = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM repairs WHERE client_id = ?',
            [id],
          ),
        ) ??
        0;
    final linkedVehicles = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM vehicles WHERE client_id = ?',
            [id],
          ),
        ) ??
        0;

    if (linkedRepairs > 0 || linkedVehicles > 0) {
      throw StateError(
        'لا يمكن حذف العميل لأن له مركبات أو ملفات إصلاح محفوظة. '
        'يمكن تعديل بياناته بدلًا من حذف السجل التاريخي.',
      );
    }

    return DBService.inTx<int>((txn) async {
      final row = await txn.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (row.isEmpty) return 0;

      final changed = await txn.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (changed > 0) {
        final now = DateTime.now().toUtc().toIso8601String();
        await OfflineOutboxService.enqueue(
          txn,
          channel: OfflineOutboxService.channelSync,
          operation: 'DELETE',
          entityType: 'client',
          entityId: id.toString(),
          idempotencyKey: 'client:$id:delete:$now',
          payload: {
            'schema': 1,
            'entity_type': 'client',
            'entity_id': id,
            'name': row.first['name']?.toString() ?? '',
          },
        );
      }

      return changed;
    });
  }

  static Future<List<Client>> getAllClients() async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    final rows = await db.query(tableName, orderBy: 'LOWER(name) ASC');
    return rows.map(Client.fromMap).toList();
  }

  static Future<List<Client>> getClientsByType(String type) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    final rows = await db.query(
      tableName,
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'LOWER(name) ASC',
    );
    return rows.map(Client.fromMap).toList();
  }

  // ===================== Helpers =====================

  static String normalizeNameForIdentity(String input) {
    var value = input.trim().toLowerCase();
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    return value;
  }

  static String _legacyNormalizedName(String input) {
    var value = input.trim();
    value = value.replaceAll('شركة', '');
    value = value.replaceAll('تأمين', '');
    value = value.replaceAll(RegExp(r'\s+'), '');
    return value.toLowerCase();
  }

  static Future<int?> findDuplicateIdOn(
    DatabaseExecutor db,
    String name, {
    String? type,
    int? excludeId,
  }) async {
    final exact = normalizeNameForIdentity(name);
    final legacy = _legacyNormalizedName(name);

    String identityWhere;
    final args = <Object?>[exact];

    if (type != null && type.trim().isNotEmpty) {
      // Exact duplicate names are blocked globally because the existing DB
      // contract has UNIQUE(name). Legacy-normalized matching remains type-aware.
      identityWhere = '''
        (
          LOWER(TRIM(name)) = ?
          OR (
            LOWER(REPLACE(REPLACE(REPLACE(TRIM(name),'شركة',''),'تأمين',''),' ','')) = ?
            AND type = ?
          )
        )
      ''';
      args
        ..add(legacy)
        ..add(type.trim());
    } else {
      identityWhere = '''
        (
          LOWER(TRIM(name)) = ?
          OR LOWER(REPLACE(REPLACE(REPLACE(TRIM(name),'شركة',''),'تأمين',''),' ','')) = ?
        )
      ''';
      args.add(legacy);
    }

    var where = identityWhere;
    if (excludeId != null) {
      where = '($where) AND id <> ?';
      args.add(excludeId);
    }

    final rows = await db.query(
      tableName,
      columns: const ['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final value = rows.first['id'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static Future<bool> clientExists(
    String name, {
    String? type,
    int? excludeId,
  }) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    return await findDuplicateIdOn(
          db,
          name,
          type: type,
          excludeId: excludeId,
        ) !=
        null;
  }

  static Future<int> upsertFromRepairOn(
    DatabaseExecutor db, {
    required String name,
    required String type,
  }) async {
    final duplicate = await findDuplicateIdOn(
      db,
      name,
      type: type,
    );
    if (duplicate != null) return duplicate;

    final id = await db.insert(
      tableName,
      {
        'name': name.trim(),
        'type': type.trim(),
        'phone': '',
        'email': '',
        'address': '',
        'notes': '',
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    await OfflineOutboxService.enqueue(
      db,
      channel: OfflineOutboxService.channelSync,
      operation: 'UPSERT',
      entityType: 'client',
      entityId: id.toString(),
      idempotencyKey: 'client:$id:create',
      payload: {
        'schema': 1,
        'entity_type': 'client',
        'entity_id': id,
        'name': name.trim(),
        'type': type.trim(),
      },
    );

    return id;
  }

  /// إدراج سريع بالاسم والنوع مع ربط AR.
  static Future<void> insertClientByName(String name, String type) async {
    if (name.trim().isEmpty) return;
    await insertOrGetClientId(name, type);
  }

  /// أسماء العملاء حسب النوع. مرتبة ومميّزة.
  static Future<List<String>> getClientNamesByType(String type) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    final rows = await db.query(
      tableName,
      columns: const ['name'],
      where:
          '(LOWER(type) = LOWER(?) OR LOWER(type) = LOWER("افراد") OR LOWER(type) = LOWER("individual")) '
          'AND name IS NOT NULL AND TRIM(name) <> ""',
      whereArgs: [type.trim()],
      orderBy: 'LOWER(name) ASC',
    );
    final names = rows
        .map((e) => (e['name'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static Future<List<Client>> search({
    String? query,
    String? type,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);

    final where = <String>[];
    final args = <Object?>[];

    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      where.add(
          '(name LIKE ? OR phone LIKE ? OR email LIKE ? OR address LIKE ? OR notes LIKE ?)');
      args
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like);
    }

    if (type != null && type.trim().isNotEmpty) {
      where.add('type = ?');
      args.add(type.trim());
    }

    final rows = await db.query(
      tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'LOWER(name) ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Client.fromMap).toList();
  }

  // ===================== ID/Name mapping =====================

  static Future<int?> getClientIdByName(String name) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    final norm = _legacyNormalizedName(name);
    final r = await db.rawQuery('''
      SELECT id FROM $tableName
      WHERE LOWER(REPLACE(REPLACE(REPLACE(TRIM(name),'شركة',''),'تأمين',''),' ','')) = ?
      LIMIT 1
    ''', [norm]);
    if (r.isEmpty) return null;
    final v = r.first['id'];
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  /// يرجّع id إن وجد، وإلا ينشئ العميل ويربطه بحساب AR ثم يرجّع id.
  static Future<int> insertOrGetClientId(String name, String type) async {
    final id = await DBService.inTx<int>((txn) async {
      await _ensureAccountColumn(txn);
      return upsertFromRepairOn(
        txn,
        name: name,
        type: type,
      );
    });

    try {
      await DBService.ensureClientAccount(id);
    } catch (_) {}

    return id;
  }

  static Future<String?> getClientNameById(int id) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    final r = await db.query(
      tableName,
      columns: const ['name'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (r.isEmpty) return null;
    final v = r.first['name'];
    return v?.toString();
  }

  static Future<int> getTotalClients() async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// يرجّع/يضمن account_id للعميل
  static Future<int> getOrEnsureAccountId(
      int clientId, String clientName) async {
    final acc = await _getClientAccountId(clientId);
    if (acc != null) return acc;
    return DBService.ensureClientAccount(clientId);
  }

  static Future<Client?> getClientById(int id) async {
    final db = await DBService.database;
    final rows = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Client.fromMap(rows.first);
  }

  static Future<ClientProfileSnapshot> getProfileSnapshot(int clientId) async {
    final db = await DBService.database;

    final repairCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM repairs WHERE client_id = ?',
            [clientId],
          ),
        ) ??
        0;

    final vehicleRows = await db.query(
      'vehicles',
      columns: const ['number'],
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'updated_at DESC, id DESC',
    );

    final recentRepairs = await db.query(
      'repairs',
      columns: const [
        'id',
        'vehicleType',
        'vehicleNumber',
        'receivedDate',
        'vehicleStatus',
      ],
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'receivedDate DESC, created_at DESC',
      limit: 5,
    );

    return ClientProfileSnapshot(
      repairCount: repairCount,
      vehicleCount: vehicleRows.length,
      vehicleNumbers: vehicleRows
          .map((row) => row['number']?.toString() ?? '')
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false),
      recentRepairs: recentRepairs
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false),
    );
  }

  // ===== داخلي =====

  static Future<int?> _getClientAccountId(int clientId) async {
    final db = await DBService.database;
    final r = await db.query(
      tableName,
      columns: const ['account_id'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (r.isEmpty) return null;
    final v = r.first['account_id'];
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
