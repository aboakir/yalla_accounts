// 📁 lib/features/finance/services/ledger_database_service.dart
//
// P1.005 — legacy compatibility reader only.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/ledger_entry.dart';

class LedgerDatabaseService {
  static const _table = 'ledger_entries';

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT,
        debit_account TEXT NOT NULL,
        credit_account TEXT NOT NULL,
        amount REAL NOT NULL,
        reference_type TEXT,
        reference_id TEXT,
        is_approved INTEGER DEFAULT 0,
        transaction_type TEXT
      )
    ''');
  }

  static Never _blocked() {
    throw StateError(
      'Legacy ledger_entries mutation is disabled by P1.005. '
      'Use the owning business service and PostingEngine.',
    );
  }

  static Future<int> insertEntry(LedgerEntry entry) async => _blocked();
  static Future<int> updateEntry(LedgerEntry entry) async => _blocked();
  static Future<int> deleteEntry(int id) async => _blocked();

  static Future<int> deleteEntriesByReference(
    String refType,
    String refId,
  ) async =>
      _blocked();

  static Future<List<LedgerEntry>> getAllEntries() async {
    final db = await DBService.database;
    final maps = await db.query(_table, orderBy: 'date DESC, id DESC');
    return maps.map(LedgerEntry.fromMap).toList();
  }

  static Future<List<LedgerEntry>> getEntriesByReference(
    String refType,
    String refId,
  ) async {
    final db = await DBService.database;
    final maps = await db.query(
      _table,
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: [refType, refId],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map(LedgerEntry.fromMap).toList();
  }

  static Future<void> setApproval(int entryId, bool approved) async {
    _blocked();
  }
}
