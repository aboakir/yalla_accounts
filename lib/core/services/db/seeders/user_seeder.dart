import 'package:yalla_accounts/core/security/release_diagnostics.dart';
import 'package:sqflite/sqflite.dart';

/// P1.002 compatibility shim.
///
/// Commercial installations no longer seed universal users, shared passwords,
/// or offline activation-code batches. First owner creation is explicit in the
/// first-run registration flow.
class UserSeeder {
  static Future<void> seed(Database db) async {
    ReleaseDiagnostics.debug(
      'ℹ P1.002: default-user seeding disabled; first owner must be explicit.',
    );
  }

  static Future<void> seedIfEmpty(Database db) => seed(db);

  static Future<void> seedActivationCodes(Database db) async {
    ReleaseDiagnostics.debug(
      'ℹ P1.002: legacy activation-code seeding disabled.',
    );
  }
}
