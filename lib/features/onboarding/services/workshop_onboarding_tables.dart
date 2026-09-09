import 'package:sqflite/sqflite.dart';

/// Progress only: never credentials, PINs, recovery codes or license grants.
class WorkshopOnboardingTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workshop_onboarding_state (
        owner_user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        organization_id TEXT NOT NULL REFERENCES organizations(id),
        status TEXT NOT NULL CHECK(status IN ('PENDING', 'COMPLETED')),
        backup_choice TEXT CHECK(backup_choice IN ('open_settings', 'later')),
        updated_at TEXT NOT NULL
      )
    ''');
    // Runs in the bootstrap transaction, including a crash before PIN setup.
    // Existing workshops are deliberately not enrolled during migration.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_owner_onboarding_pending
      AFTER UPDATE OF status ON owner_bootstrap_state
      WHEN OLD.status = 'PENDING' AND NEW.status = 'COMPLETED'
      BEGIN
        INSERT OR IGNORE INTO workshop_onboarding_state
          (owner_user_id, organization_id, status, updated_at)
        VALUES (NEW.owner_user_id, NEW.organization_id, 'PENDING', NEW.updated_at);
      END
    ''');
  }
}
