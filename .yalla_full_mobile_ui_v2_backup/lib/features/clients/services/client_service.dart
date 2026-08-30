// 📁 lib/features/clients/services/client_service.dart
//
// ClientService — ربط العملاء مع GL تلقائيًا (AR account) عبر DBService.
// - يضمن عمود account_id في clients.
// - عند insertClient و insertOrGetClientId: ينشئ حساب AR ويربطه.
// - متوافق مع StepBeneficiaryData.getClientNamesByType.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';

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
    final db = await DBService.database;
    await _ensureAccountColumn(db);

    final id = await db.insert(
      tableName,
      client.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // اربط حساب AR
    try {
      await DBService.ensureClientAccount(id);
    } catch (_) {}

    return id;
  }

  static Future<int> updateClient(Client client) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);

    final data = client.toMap()..remove('id');
    int count;

    if (client.id != null) {
      count = await db.update(
        tableName,
        data,
        where: 'id = ?',
        whereArgs: [client.id],
      );

      try {
        final accId = await _getClientAccountId(client.id!);
        if (accId == null) {
          await DBService.ensureClientAccount(client.id!);
        }
      } catch (_) {}

      return count;
    }

    // fallback بالاسم والنوع
    count = await db.update(
      tableName,
      data,
      where: 'name = ? AND type = ?',
      whereArgs: [client.name, client.type],
    );

    try {
      final cid = await getClientIdByName(client.name);
      if (cid != null) {
        final accId = await _getClientAccountId(cid);
        if (accId == null) {
          await DBService.ensureClientAccount(cid);
        }
      }
    } catch (_) {}

    return count;
  }

  static Future<int> deleteClient(int id) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    // لا نحذف حساب GL.
    return db.delete(tableName, where: 'id = ?', whereArgs: [id]);
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

  static String _normalizeName(String input) {
    var s = input.trim();
    s = s.replaceAll('شركة', '');
    s = s.replaceAll('تأمين', '');
    s = s.replaceAll(RegExp(r'\s+'), '');
    return s.toLowerCase();
  }

  static Future<bool> clientExists(String name, {String? type}) async {
    final db = await DBService.database;
    await _ensureAccountColumn(db);
    final param = _normalizeName(name);

    var where = '''
      LOWER(REPLACE(REPLACE(REPLACE(TRIM(name),'شركة',''),'تأمين',''),' ','')) = ?
    ''';
    final args = <Object?>[param];

    if (type != null && type.trim().isNotEmpty) {
      where += ' AND type = ?';
      args.add(type.trim());
    }

    final r = await db.query(
      tableName,
      columns: const ['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );
    return r.isNotEmpty;
  }

  /// إدراج سريع بالاسم والنوع مع ربط AR.
  static Future<void> insertClientByName(String name, String type) async {
    if (name.trim().isEmpty) return;
    if (await clientExists(name, type: type)) return;

    final db = await DBService.database;
    await _ensureAccountColumn(db);

    final id = await db.insert(tableName, {
      'name': name.trim(),
      'type': type.trim(),
      'phone': '',
      'email': '',
      'address': '',
      'notes': '',
    });

    try {
      await DBService.ensureClientAccount(id);
    } catch (_) {}
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
    final norm = _normalizeName(name);
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
    final existing = await getClientIdByName(name);
    if (existing != null) return existing;

    final db = await DBService.database;
    await _ensureAccountColumn(db);

    final id = await db.insert(tableName, {
      'name': name.trim(),
      'type': type.trim(),
      'phone': '',
      'email': '',
      'address': '',
      'notes': '',
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
