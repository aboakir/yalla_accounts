// P1.001 compatibility shim.
//
// This legacy path previously contained a second RepairDatabaseService that
// opened another yalla_accounts.db. Any future import resolves to the canonical
// service instead.
export 'repair_database_service.dart';
