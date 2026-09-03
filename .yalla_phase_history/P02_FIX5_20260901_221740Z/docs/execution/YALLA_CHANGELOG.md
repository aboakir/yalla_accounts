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
