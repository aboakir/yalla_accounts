import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

/// P1.001 compatibility adapter.
///
/// Older code may still import DatabaseProvider, but it is no longer allowed
/// to open a second SQLite file.
class DatabaseProvider {
  DatabaseProvider._();
  static final DatabaseProvider instance = DatabaseProvider._();

  Future<Database> get database => DBService.database;
}
