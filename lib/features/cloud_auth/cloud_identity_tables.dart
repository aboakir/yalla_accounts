import 'package:sqflite/sqflite.dart';

/// External identity is a binding, never a source of workshop roles or money.
class CloudIdentityTables {
  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS cloud_identity_links (
      issuer TEXT NOT NULL,
      subject TEXT NOT NULL,
      identity_account_id TEXT NOT NULL REFERENCES identity_accounts(id) ON DELETE RESTRICT,
      organization_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
      linked_at TEXT NOT NULL,
      PRIMARY KEY (issuer, subject),
      UNIQUE (issuer, identity_account_id)
    )''');
    await db
        .execute('''CREATE TRIGGER IF NOT EXISTS cloud_identity_links_no_replace
      BEFORE INSERT ON cloud_identity_links WHEN EXISTS (
        SELECT 1 FROM cloud_identity_links WHERE issuer = NEW.issuer AND
          (subject = NEW.subject OR identity_account_id = NEW.identity_account_id))
      BEGIN SELECT RAISE(ABORT, 'Existing cloud identity cannot be replaced'); END''');
    await db
        .execute('''CREATE TRIGGER IF NOT EXISTS cloud_identity_links_no_delete
      BEFORE DELETE ON cloud_identity_links BEGIN
      SELECT RAISE(ABORT, 'Audited unlink is required'); END''');
    await db
        .execute('''CREATE TRIGGER IF NOT EXISTS cloud_identity_links_immutable
      BEFORE UPDATE ON cloud_identity_links BEGIN
      SELECT RAISE(ABORT, 'Cloud identity cannot be reassigned'); END''');
  }
}
