import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/tables/technical_tables.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('P06 archive changes only archive metadata and queues Outbox', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE repairs(
        id TEXT PRIMARY KEY,
        isArchived INTEGER DEFAULT 0,
        updated_at TEXT,
        fileValue REAL,
        paidAmount REAL,
        paymentStatus TEXT,
        vehicleStatus TEXT
      )
    ''');
    await TechnicalTables.createAllTables(db);

    await db.insert('repairs', {
      'id': 'r-archive',
      'isArchived': 0,
      'updated_at': '2026-09-01T00:00:00.000Z',
      'fileValue': 1234.5,
      'paidAmount': 500.0,
      'paymentStatus': 'مسدد جزئي',
      'vehicleStatus': 'قيد الإصلاح',
    });

    expect(
      await RepairDatabaseService.setArchivedOn(
        db,
        'r-archive',
        true,
      ),
      1,
    );

    final row = (await db.query('repairs')).single;
    expect(row['isArchived'], 1);
    expect(row['fileValue'], 1234.5);
    expect(row['paidAmount'], 500.0);
    expect(row['paymentStatus'], 'مسدد جزئي');
    expect(row['vehicleStatus'], 'قيد الإصلاح');

    final outbox = (await db.query(
      TechnicalTables.outboxTable,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['repair', 'r-archive'],
    ))
        .single;

    expect(outbox['sent'], 0);
    final payload =
        jsonDecode(outbox['payload_json'] as String) as Map<String, dynamic>;
    expect(payload['is_archived'], isTrue);
    expect(payload.containsKey('fileValue'), isFalse);
    expect(payload.containsKey('paidAmount'), isFalse);
  });

  test('P06 repeated same archive state is a no-op', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE repairs(
        id TEXT PRIMARY KEY,
        isArchived INTEGER DEFAULT 0,
        updated_at TEXT
      )
    ''');
    await TechnicalTables.createAllTables(db);

    await db.insert('repairs', {
      'id': 'r-noop',
      'isArchived': 1,
      'updated_at': '2026-09-01T00:00:00.000Z',
    });

    expect(
      await RepairDatabaseService.setArchivedOn(
        db,
        'r-noop',
        true,
      ),
      0,
    );

    final queued = await db.query(
      TechnicalTables.outboxTable,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['repair', 'r-noop'],
    );
    expect(queued, isEmpty);
  });
}
