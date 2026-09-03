# Yalla Accounts Mobile V2 — Changelog

## P01 FIX1 — Formatting sequence corrected

- The first P01 run rolled back safely after `dart format` changed one new file.
- FIX1 now formats the four new Dart files first, then verifies that no formatting
  changes remain before analyzer, tests, and Windows build.
- The official project path is confirmed as `E:\flutter_projects\yalla_accounts`.
- No application, database, or business-logic file remained changed by the failed run.

## P01 — Package prepared; local PASS pending

Planned additions:

- Permanent project execution memory under `docs/execution`.
- Exact project-name and path guards that refuse every non-Yalla project.
- Targeted backup and deterministic rollback for every installed P01 file.
- Payload SHA-256 verification before any project file changes.
- Capturing Git, Flutter, and Dart baseline data in `YALLA_PROJECT_STATE.json`.
- Isolated mobile design tokens, breakpoint helpers, and reusable components.
- A targeted Flutter test for the P01 design foundation.
- Analyzer, targeted tests, and Windows debug build verification.

P01 remains `IN_PROGRESS` until the Windows terminal ends with:

`YALLA P01 RESULT: PASS`


## P02 — IN PROGRESS — Mobile auth/workshop foundation
- Reworked first-owner setup into a four-step mobile-first wizard.
- First-owner bootstrap now writes workshop address, city and primary phone into canonical workshop_settings along with workshop name/logo.
- Added secure device PIN using FlutterSecureStorage + canonical PBKDF2 PasswordHasher.
- Added local biometric/Windows Hello integration via local_auth.
- Added offline unlock path for an already persisted valid local customer session.
- Preserved commercial access gate, owner bootstrap activation authority, recovery, Yalla-admin isolation, and existing database schema.
- No database migration.
- Blocker: customer phone SMS OTP has no authoritative start/verify backend contract in the current source; no fake local OTP was introduced.


## P02 FIX5 — PASS — Server-authoritative customer phone verification
- Added server-authoritative customer phone OTP start / verify / consume endpoints.
- OTP is generated only by the server, stored only as a salted slow verifier, expires after 5 minutes, is rate-limited to one request per 60 seconds per phone, and allows at most 5 attempts.
- Successful verification returns a short-lived random verification token whose server copy is also stored only as a salted verifier; token consumption is one-time and bound to the verified phone.
- Added server-side HTTPS SMS adapter configuration through `YALLA_SMS_WEBHOOK_URL` and optional `YALLA_SMS_WEBHOOK_TOKEN`; no SMS provider secret is shipped to Flutter.
- The SEC.015A loopback-only development harness can expose the OTP only in its server console diagnostic for isolated testing; OTP is never returned by the API.
- Updated the P02 mobile wizard so step 2 sends and verifies SMS before the user can continue; the verification token stays in memory and is consumed immediately before First Owner bootstrap.
- Added an isolated end-to-end P02 OTP integration test proving no plaintext OTP/token persistence and one-time consumption.
- Client database schema/version unchanged; Stage 04 commercial semantics unchanged.
- P02 is complete. Next phase: P03.


## P03 — Home / App Shell / Today Dashboard — PASS
- Rebuilt the phone home around a single Today summary instead of an equal-weight KPI wall.
- Added DB-backed attention items and recent repair files.
- Added a basic notification center using the same authoritative attention snapshot.
- Expanded phone bottom navigation to Home / Repairs / Add / Finance / More.
- The Add destination opens Repair / Receipt Voucher / Client / Cheque actions.
- Preserved tablet/desktop dashboard behavior and existing commercial authority.
- Database migration/reset: NO.
- Stage04 semantics: NOT MODIFIED.
- Next official action: C01 — fresh IPA #1 and iPhone validation.


## P03 FIX1 — TextDirection namespace collision
- The first P03 run reached analyzer differential and rolled back safely.
- Root cause: `package:intl` exposes a `TextDirection` symbol, so three unqualified
  `TextDirection.ltr` references in the new phone Home resolved to the wrong type.
- FIX1 qualifies the Flutter UI enum as `ui.TextDirection.ltr` via
  `import 'dart:ui' as ui;`.
- No P03 data query, navigation behavior, UI hierarchy, database, Stage04 semantics,
  or Desktop behavior changed.
- The P03 targeted test now locks this namespace-safe contract.

## C01 FIX3D — rebuilt from exact live source after guard mismatch
- Source snapshot: `FBB340E3633942D51C843CA4A331A5773E83AF6FD638C7230EBC2C7788961CBC` (read-only; 14 files; DB/AYKA untouched).
- FIX3/FIX3A correctly stopped before mutation because the live `p03_home_service.dart` no longer matched the earlier package source guard.
- Recovered readable UTF-8 Arabic in the legacy `YallaSidebar` while preserving routes, menu hierarchy, commercial gates, and navigation behavior.
- P03 Home now formats stored ISO/SQLite dates as `dd-MM-yyyy` before RTL rendering in overdue/stale/recent items.
- Replaced the visible `آ·` mojibake separator in phone repair cards with the intended middle dot `·`.
- No database migration/reset, accounting change, entitlement change, or P04 work.
- On local PASS: build a fresh C01 IPA and repeat human iPhone validation. C01 remains `RETEST_PENDING` until then.

## C01 FIX4 — PHONE Repair Reports chart responsiveness
- Human iPhone retest after FIX3D confirmed sidebar Arabic recovery but exposed a remaining PHONE-only visual failure in `RepairReportsScreen`: Y-axis values wrapped vertically and right-side titles remained visible.
- The repair is limited to chart presentation: explicit hidden top/right axes, wider reserved Y-axis space, single-line compact K/M labels, LTR numeric chart direction, clipping, and a small phone chart-height increase.
- Repair report filters, totals, source data, exports, accounting values, routes, and permissions are unchanged.
- FIX3D Home `dd-MM-yyyy` presentation remains guarded and unchanged.
- No database migration/reset, accounting change, entitlement change, or P04 work.
- On local PASS: build a fresh C01 IPA and repeat the human iPhone test.


## C01 FIX4A — installer guard correction only
- The first FIX4 attempt stopped **before any mutation** because `yalla_sidebar.dart` was guarded by the raw FIX3D payload hash, while FIX3D had legitimately run `dart format` after copying it.
- FIX4A keeps the same Repair Reports PHONE responsiveness payload.
- Exact byte guards now cover only the source file FIX4A overwrites plus execution-state documents.
- FIX3D sidebar Arabic, Home date formatting, and repair-card separator remain protected by targeted regression tests.
- No database migration/reset, accounting change, entitlement change, or P04 work.


## C01 FIX4B — fl_chart 0.68 API compatibility
- FIX4A passed all pre-apply guards and applied its narrow Repair Reports payload, but the analyzer rejected `clipData` because `BarChartData` in the project's `fl_chart ^0.68.0` API does not define that named parameter.
- FIX4A immediately rolled back its complete payload successfully; the project returned to the exact pre-FIX4A C01/FIX3D state.
- FIX4B preserves the same PHONE chart-axis repair but moves clipping to Flutter's generic `ClipRect` wrapper around the chart instead of passing unsupported configuration to `BarChartData`.
- No database migration/reset, accounting change, entitlement change, route change, or P04 work.
- C01 remains `RETEST_PENDING` until local PASS, fresh IPA build, and human iPhone retest.

## C01 — Human iPhone checkpoint — PASS
- FIX9 iPhone build `87283d769d6fce03a12fed18582fe6e360960e90` / GitHub Actions `33629042501` passed.
- Human iPhone evidence confirmed Repairs Dashboard and Vehicles List without the duplicate/persistent sidebar.
- C01 is closed as PASS. P04 is allowed to start.

## P04.1 — Encrypted local database — IN PROGRESS
- Added SQLCipher as the mobile canonical database engine for iOS/Android while preserving the desktop SQLite/FFI path.
- Database key material is 256-bit random data from `Random.secure()` stored only in `FlutterSecureStorage`.
- Existing mobile plaintext DBs use `sqlcipher_export()` into a separately verified encrypted copy before atomic replacement.
- Migration validates cipher runtime, integrity, foreign keys, table set, and per-table row counts.
- A short-lived plaintext rollback copy exists only until the encrypted canonical DB passes Yalla's existing full validation.
- Crash recovery is fail-closed; no database reset/replacement fallback.
- Backup validation accepts current-key encrypted backups and legacy plaintext backups; portable cross-install backup envelopes remain P16 scope.
- DB schema remains v69. Windows/Desktop DB runtime is unchanged.
- Live customer database touched by Windows installer: NO.

## P04.2 — Offline save + Outbox foundation
- Replaced the legacy technical outbox payload serializer (`Map.toString`) with real JSON encoding.
- Upgraded `outbox_messages` in place without deleting existing rows or rebuilding the table.
- Added durable status, operation, entity identity, idempotency key, retry count, retry schedule, last error, and update timestamp fields.
- Added a unique idempotency index and ready/entity indexes.
- Existing legacy `sent` rows are projected into the new status model and remain preserved.
- Added `OfflineOutboxService` with enqueue, ready, pending-count, sending, sent, failed/backoff, and interrupted-send recovery primitives.
- Repair creation is now the first golden local-first write path: repair data and its Outbox envelope are committed in the same SQLite transaction.
- The repair save path contains no connectivity/network gate; saving remains local even when the internet is unavailable.
- No network transport/drain loop is started in P04.2; that remains later P04 work.
- DB schema version remains 69. The outbox upgrade follows the project's existing idempotent post-init ensure pattern and performs no destructive rebuild.

## P04.2C — Offline save + Outbox completion
- Fresh P04.2B diagnostic proved that the P04.2 source changes were already present in the live project: upgraded `TechnicalTables`, `OfflineOutboxService`, and the repair transaction Outbox write.
- Corrected the Outbox retry exponent to stay an integer for Dart shift arithmetic.
- Corrected Outbox schema compatibility placement: existing installations are already DB v69, so `ensureP04OutboxSchema()` now runs in the normal idempotent `_postInit` path on every open rather than only inside historical `oldV < 68`.
- Added startup recovery for stale `sending` rows through `resetInterruptedSending()`.
- Repair creation remains local-first: the repair and its sync intent commit in the same SQLite transaction with no connectivity prerequisite.
- No network transport/drain is started in P04.2C.
- DB version remains 69; existing rows are preserved and the compatibility upgrade only adds missing Outbox columns/indexes.

## P04.3 — Sync state indicator + coordinated Outbox drain — PASS
- Added a single sync-state service driven by the real local Outbox queue.
- Added a compact phone sync indicator above the existing bottom navigation. It distinguishes checking, local-only, pending, syncing, synced, offline and failed states.
- The indicator never claims cloud sync when no production transport is configured; queued work is shown as saved locally and waiting for sync.
- Added a backend-agnostic `OutboxSyncTransport` contract with explicit idempotency-key acknowledgement.
- Added a serialized Outbox drain coordinator protected by a lock so concurrent lifecycle/manual triggers cannot drain the same queue in parallel.
- A row is marked `sent` only after an accepted acknowledgement carrying the same idempotency key.
- Socket/OS/timeout failures leave the business mutation locally committed, mark the Outbox row failed with the existing bounded retry schedule, and stop the current drain without data loss.
- App resume retries the drain only when a real transport is configured.
- Outbox changes now publish a local stream so the visible indicator refreshes immediately; a low-frequency timer remains as a safety refresh.
- No workshop sync endpoint exists in the current source snapshot, so P04 deliberately does not invent a URL or server contract. The drain/ack/failure engine is complete and transport-pluggable.
- DB schema version remains 69. No database reset, accounting calculation, commercial entitlement or desktop DB behavior is changed.
- P04 local-first/basic-sync foundation is complete; P05 is next. C02 remains after P06.

## P04.3A — P04.1 regression-state alignment
- P04.3 initially rolled back because the older P04.1 regression test asserted that `phases.P04` must remain `IN_PROGRESS`.
- That assertion is chronological rather than an encryption/security invariant and becomes invalid when P04 legitimately reaches PASS.
- The P04.1 encryption/security assertions remain unchanged; only the phase-state assertion now accepts `IN_PROGRESS` while P04 is being built or `PASS` after P04 closes.
- No production database, accounting, sync, entitlement or UI behavior is changed by this regression-test alignment.

## P05 — Clients + Vehicles — PASS
- Kept the existing client list/add/edit flow and hardened client identity checks without deleting or merging historical rows.
- Client add/edit mutations now record local-first Outbox intent in the same SQLite transaction as the client row; existing AR-account behavior is preserved outside that transaction.
- Client edit now preserves the notes field instead of silently dropping it.
- Client deletion is blocked when repair or vehicle history exists, preventing orphaned operational history.
- The existing client details dialog is now the client profile: contact details, vehicle count, repair count, linked vehicle numbers and recent repair history.
- Added canonical `vehicles` master-data table with a unique normalized vehicle number and optional client ownership link.
- Existing repair data is backfilled into the vehicle master table idempotently; repairs are not rewritten or deleted, and later startups do not overwrite user-edited canonical vehicle master data from historical repairs.
- Added real vehicle add/edit, search/list and vehicle-history flow while preserving the C01 phone shell rule that the embedded desktop sidebar appears only at width >= 600.
- Vehicle number identity normalizes Arabic/Persian digits and common separators before duplicate checks.
- A vehicle with repair history keeps its identity number locked in the edit dialog, preventing history from being detached by an accidental plate-number edit.
- Repair creation now upserts both canonical client and vehicle records inside the existing repair transaction.
- DB version remains 69. `vehicles` is ensured from the normal post-init compatibility path before database validation.
- No accounting formulas/posting rules, commercial entitlements, or existing repair financial values are changed.

## P05B — analyzer fix
- P05A isolated exactly one analyzer error introduced by P05: `TextDirection.rtl` in `vehicle_history_dialog.dart` was shadowed by the `intl` package's `TextDirection` symbol.
- The `intl` import is now aliased and `DateFormat` is qualified, leaving Flutter's `TextDirection.rtl` unambiguous.
- Removed one P05-test-only unused import warning.
- No production behavior, DB schema, accounting, entitlements, or repair data semantics changed.

## P06 — Repair list, search, filters, statuses, archive — PASS
- `/repairs/list` now opens the existing approved `RepairsScreen` in show-all mode instead of the minimal overview screen; `/repairs` remains the overview route.
- Added direct sidebar access to `ملفات الإصلاح`.
- Added a pure repair-list filter contract covering text search, payment status, vehicle status, beneficiary type, date range, and archive scope.
- Search now includes repair ID, invoice number, vehicle number/type/model, beneficiary name and beneficiary type.
- Phone and wider layouts use the same archive truth (`Repair.isArchived`) instead of treating every fully paid file as archived.
- Newly created/updated fully paid repairs are no longer auto-archived; archive is an explicit operational action independent of accounting/payment state.
- Added archive and restore actions to the existing repair quick-actions sheet.
- Archive/restore updates only `isArchived` and `updated_at`, and records a local-first Outbox mutation in the same transaction; it does not touch financial values or posting fields.
- Phone list now exposes active/archive/all chips and shows both payment status and vehicle status.
- Desktop/tablet filter bar now includes payment status, vehicle status, beneficiary type and archive scope while preserving date-range behavior.
- Added P06 source/regression tests for archive financial immutability, filter behavior, route accessibility and phone-shell ownership.
- DB schema/version is unchanged at 69. No repair rows are deleted/rebuilt by P06.
- Next mandatory checkpoint is C02 on a real iPhone; P07 remains blocked until C02 PASS.


## 2026-09-02 — P07 repair intake wizard — IMPLEMENTED / LOCAL GATES PENDING
- Replaced the legacy add-repair work/finance wizard with the official P07 intake sequence while preserving the `AddRepairScreen` class and all existing entry points.
- Added customer select/quick-add and customer-scoped vehicle select/quick-add.
- Added reception date, odometer, fuel, previous-damage declaration, persisted intake photos, customer signature, review and save.
- Added `RepairIntakeService`; intake save is `QUOTE` / `بانتظار الإصلاح` and deliberately creates no invoice, approval, payment or GL entry.
- Added additive repair columns (`odometer`, `fuel_level`, `previous_damage`, `customer_signature_path`, `intake_completed_at`) through explicit idempotent current-v69 compatibility migration; DB version remains 69 to preserve the C02/P04 fail-closed encryption contract.
- Added P07 source-contract and database/local-first tests.
- C02 human iPhone checkpoint was still PENDING when Luay explicitly commanded `P07 نفذ`; this is recorded as an owner sequencing override, not as a C02 PASS.
- No Git push is performed by the P07 package.
