# Stage 48 — Backup / Restore

Date: 2026-09-09. Desktop implementation and automated acceptance complete; native mobile acceptance remains pending.

## Delivered behavior

- New archives use the exact basename `yalla_backup_YYYY_MM_DD.yab`. Distinct per-run folders prevent same-day overwrites. Existing `.yallabackup` files remain discoverable, selectable and restorable. The encrypted container version remains compatible.
- Snapshot covers the entire SQLite database, including workshop/settings records, audit events and future change-log/sync tables, plus canonical media, legacy media directories and referenced external attachments. The live DB and its sidecars/journal are excluded from media traversal to avoid a second changing database copy.
- Files have mandatory sizes and SHA-256 digests. Archive paths, duplicate entries, links, undeclared files, external references, SQLite integrity/foreign keys and actual database schema version are validated. Corrupt/missing/truncated data fails before replacement. Excessive codec work factors and chunk sizes are rejected.
- Only a validated encrypted candidate is published; partial publication files are hidden from latest-backup discovery. Temporary plaintext staging is removed in `finally`.
- Mobile SQLCipher uses a temporary plaintext SQLite export inside the password-encrypted archive, avoiding dependence on the source installation's private SQLCipher key. Destination startup uses its existing encryption migration. Native SQLCipher execution was not available on this Windows host and must be verified on iOS/Android.
- Arabic settings show the latest backup date, size, location and latest successful restore. Restore explicitly warns about replacing workshop data and signing in again. Password dialogs await closure before disposing controllers.
- Existing OS picker/share APIs handle Files / Drive / iCloud. No direct connector upload or automatic email is performed. Existing optional target-email labeling applies only within the 20 MiB advisory size; larger files are directed to the OS share/cloud choices.
- Restore remains Owner-only and requires the Stage46 operational-write check. Expired Owner sessions can create/export backups but cannot restore.
- Full safety backup, durable file journal, migration validation, rollback and session revocation are retained. Successful-restore audit is written inside the rollback boundary. Failed snapshot reopening logs only against the captured open database handle; it never opens a canonical fallback for error logging.

## Verification

Focused acceptance and regression command uses an isolated process-level database directory and the test-only Ed25519 pin. The public RFC8032 fixture key is used only in the test command; no production trust configuration was changed.

```powershell
$previousStage48DbDir = $env:YALLA_ACCOUNTS_DB_DIR
$env:YALLA_ACCOUNTS_DB_DIR = Join-Path (Get-Location).Path ('tmp/stage48_isolated_' + [DateTime]::UtcNow.Ticks)
try {
  C:/dev/flutter/bin/flutter.bat test --no-pub test/stage48 test/phase16/yalla_p16_backup_codec_test.dart test/phase16/yalla_p16_security_backup_test.dart test/reliability/interrupted_restore_test.dart --dart-define=YALLA_LICENSE_TRUSTED_KEY_SHA256=21fe31dfa154a261626bf854046fd2271b7bed4b6abe45aa58877ef47f9721b9 --reporter expanded
} finally {
  $env:YALLA_ACCOUNTS_DB_DIR = $previousStage48DbDir
}
```

The acceptance file refuses to run unless the fallback directory basename starts with `stage48_isolated_`. Every fixture DB and media root is disposable; lifecycle hooks retain production authorization and validation. Tests use `DatabaseConstants.dbVersion`, including the v73 integration.

Acceptance coverage:

1. Nonempty database, customer, repair, workshop, logo, repair PNG, audit event and unknown future change table survive archive creation.
2. Canonical live database is not duplicated as media; every archive file has a digest and declared size.
3. Same-day creation preserves both archives; legacy extension validates and restores.
4. Ciphertext corruption, incorrect manifest checksum, undeclared archive file and truncated/invalid codec headers are rejected.
5. Real licensed Owner restore returns original DB/media, records restore time and invalidates restored sessions.
6. Injected failure after database/media replacement rolls both back and preserves the pre-restore login.
7. Expired Owner creates/exports but cannot restore.
8. Failed snapshot reopen cannot create a canonical fallback database or failure-log rows there.
9. Existing killed-process journal recovery still restores the previous database and attachments.

Results: focused suite **29 passed**; targeted analyzer **no issues found**. Logs: `tmp/stage48_final_test.log`, `tmp/stage48_analyze.log`.

Manual acceptance still required: iOS/Android SQLCipher export and destination re-encryption, native picker visibility for Files/iCloud/Drive, OS sharing targets and physical-device screen rendering. No external handoff or deployment was performed.

## Test isolation incident — explicit disclosure

An initial unsuccessful Stage48 acceptance run did not have a process-level `YALLA_ACCOUNTS_DB_DIR` fallback override. Its temporary owner fixture failed reopen because bootstrap status was still PENDING. The existing `createEncryptedBackup` catch then called `DBService.database` and opened `D:/YallaAccounts/yalla_accounts.db`. This **did write to the real database**: normal migrations 70/71/72 ran and five FAILED backup-run metadata rows were inserted. It was not a restore, reset or replacement operation.

Read-only inspection at 2026-09-09T12:40Z (using Python SQLite `mode=ro&immutable=1`) found:

- Main database `user_version = 72`.
- `schema_migrations`: versions 70, 71 and 72 recorded at 2026-09-09T12:36:29Z.
- Five manual `backup_runs` rows with status FAILED at approximately 12:36:27–32Z.
- No BACKUP_CREATED or BACKUP_RESTORED audit events.
- Main database size 3,948,544 bytes; last-write time 12:36:33Z; no WAL/SHM files found at inspection.
- Counts: 26 clients, 115 repairs, 113 invoices, 61 purchase invoices, 209 purchase lines, 79 payments, 55 vouchers, 445 GL entries and 1,040 GL lines. The parent task confirmed the main business counts match the earlier inventory screenshots. Counts alone do **not** prove unchanged financial values.

No usable pre-run financial snapshot was identified. The nearby audit-copy files had version 0 and no financial tables; the workspace-root database was empty. Therefore unchanged financial values cannot be established from a baseline. The read-only counts/totals and unusable snapshot findings are retained in [incident evidence](evidence/STAGE48_INCIDENT_READONLY_COMPARISON.json).

No attempt was made to repair, roll back or otherwise write to the real database after discovering this incident. The parent task was informed immediately and disclosed it to the user. Subsequent tests used an explicit disposable process directory. The production failure logger was fixed to use only its captured open handle, lifecycle hooks now require complete configuration, and a regression test proves the failing-reopen path cannot create a fallback database.
