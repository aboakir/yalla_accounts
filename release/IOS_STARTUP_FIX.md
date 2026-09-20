# iPhone startup repair — 1.0.3+22 / DB84

Observed on the physical owner iPhone, build 1.0.2+21:
- Native SQLite repeatedly returned error 8, `attempt to write a readonly database` while probing sqlite_schema.
- The canonical encrypted database had a non-empty rollback journal.
- Both encrypted files were copied to private local backup storage before the fix. No device file was deleted.

Changes:
- Recover an interrupted canonical rollback journal using SQLite's own read-write opener, without version callbacks or application writes.
- Use only the existing installation key for an encrypted database; never rotate/create a key during recovery.
- Keep backup/version inspection read-only after recovery, preserving future-schema refusal.
- Never manually remove the journal or reset/create a replacement database.
- Render a startup progress screen before database work begins.
- Do not turn a still-running migration into a failure with Future.timeout; wait for it to finish or throw.
- Expose only an allowlisted startup phase, retaining release error redaction.

Regression evidence includes an actual hot-journal fixture with SQLITE_READONLY_ROLLBACK (776), committed-row preservation, missing-file no-op and failure preservation.
Private copies of the user's desktop databases are probed locally only and are never committed or uploaded.
A successful build is not confirmation of repair on the physical phone. Install as an update to the same app, without uninstalling or deleting its data, then verify startup and records.
