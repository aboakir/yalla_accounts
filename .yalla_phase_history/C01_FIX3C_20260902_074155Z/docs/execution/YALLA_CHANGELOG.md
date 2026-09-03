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
