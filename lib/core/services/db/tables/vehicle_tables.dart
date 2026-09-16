import 'package:sqflite/sqflite.dart';

class VehicleTables {
  VehicleTables._();

  static const String tableName = 'vehicles';

  static String normalizeNumber(String input) {
    var value = input.trim();

    const arabicDigits = <String, String>{
      '\u0660': '0',
      '\u0661': '1',
      '\u0662': '2',
      '\u0663': '3',
      '\u0664': '4',
      '\u0665': '5',
      '\u0666': '6',
      '\u0667': '7',
      '\u0668': '8',
      '\u0669': '9',
      '\u06F0': '0',
      '\u06F1': '1',
      '\u06F2': '2',
      '\u06F3': '3',
      '\u06F4': '4',
      '\u06F5': '5',
      '\u06F6': '6',
      '\u06F7': '7',
      '\u06F8': '8',
      '\u06F9': '9',
    };

    arabicDigits.forEach((from, to) {
      value = value.replaceAll(from, to);
    });

    value = value.replaceAll(RegExp(r'[\s\-\./\\]+'), '');
    return value.toUpperCase();
  }

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        normalized_number TEXT NOT NULL,
        number TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        client_id INTEGER,
        owner_party_uuid TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(client_id) REFERENCES clients(id) ON DELETE SET NULL
      )
    ''');

    await _ensureColumn(db, 'normalized_number', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'number', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'model', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'client_id', 'INTEGER');
    await _ensureColumn(db, 'owner_party_uuid', 'TEXT');
    await _ensureColumn(db, 'is_active',
        'INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1))');
    await _ensureColumn(db, 'notes', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'created_at', 'TEXT');
    await _ensureColumn(db, 'updated_at', 'TEXT');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_vehicles_normalized_number '
      'ON $tableName(normalized_number);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehicles_client '
      'ON $tableName(client_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehicles_owner_party_uuid '
      'ON $tableName(owner_party_uuid);',
    );

    await _backfillFromRepairs(db);
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = info.any((row) => row['name']?.toString() == column);
    if (!exists) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN $column $definition');
    }
  }

  static Future<void> _backfillFromRepairs(DatabaseExecutor db) async {
    final repairs = await db.query(
      'repairs',
      columns: const [
        'vehicleNumber',
        'vehicleType',
        'vehicleModel',
        'client_id',
        'receivedDate',
        'created_at',
      ],
      where: 'vehicleNumber IS NOT NULL AND TRIM(vehicleNumber) <> ?',
      whereArgs: const [''],
      orderBy: 'COALESCE(receivedDate, created_at) DESC',
    );

    for (final row in repairs) {
      final number = row['vehicleNumber']?.toString().trim() ?? '';
      final normalized = normalizeNumber(number);
      if (normalized.isEmpty) continue;

      final clientId = _asInt(row['client_id']);
      final type = row['vehicleType']?.toString().trim() ?? '';
      final model = row['vehicleModel']?.toString().trim() ?? '';
      final sourceTime =
          row['receivedDate']?.toString().trim().isNotEmpty == true
              ? row['receivedDate'].toString()
              : row['created_at']?.toString();
      final now = DateTime.now().toUtc().toIso8601String();
      final timestamp =
          DateTime.tryParse(sourceTime ?? '')?.toUtc().toIso8601String() ?? now;

      final existing = await db.query(
        tableName,
        columns: const ['id'],
        where: 'normalized_number = ?',
        whereArgs: [normalized],
        limit: 1,
      );

      // Backfill is initialization-only. Once a canonical vehicle exists,
      // later app startups must never overwrite a user's master-data edits
      // from historical repair rows.
      if (existing.isNotEmpty) continue;

      await db.insert(
          tableName,
          {
            'normalized_number': normalized,
            'number': number,
            'type': type,
            'model': model,
            'client_id': clientId,
            'notes': '',
            'created_at': timestamp,
            'updated_at': timestamp,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> backfillOwnerPartyUuid(DatabaseExecutor db) async {
    final required = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('party_roles','sync_entity_registry','vehicles')",
    );
    if (required.length != 3) return;

    await db.execute('''
      UPDATE vehicles
      SET owner_party_uuid=(
        SELECT r.entity_uuid
        FROM party_roles pr
        JOIN sync_entity_registry r
          ON r.entity_type='party' AND r.local_id=pr.party_id
        WHERE pr.role='CUSTOMER'
          AND pr.legacy_id=CAST(vehicles.client_id AS TEXT)
        LIMIT 1
      )
      WHERE client_id IS NOT NULL
        AND (owner_party_uuid IS NULL OR TRIM(owner_party_uuid)='')
    ''');
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
