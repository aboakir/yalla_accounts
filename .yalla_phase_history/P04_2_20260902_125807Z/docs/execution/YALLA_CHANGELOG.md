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
