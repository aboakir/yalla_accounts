import 'package:sqflite/sqflite.dart';

class VehicleTables {
  VehicleTables._();

  static const String tableName = 'vehicles';

  static String normalizeNumber(String input) {
    var value = input.trim();

    const arabicDigits = <String, String>{
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
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
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(client_id) REFERENCES clients(id) ON DELETE SET NULL
      )
    ''');

    await _ensureColumn(
      db,
      'normalized_number',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(db, 'number', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'type', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'model', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'client_id', 'INTEGER');
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
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $column $definition',
      );
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
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
