# Yalla Accounts Mobile V2 — Acceptance Matrix

## Universal gate for every phase

- The project guard confirms `pubspec.yaml` contains `name: yalla_accounts`.
- The resolved project path exactly matches the approved Yalla Accounts project path.
- Payload hashes match `manifest.json` before copying.
- A targeted backup exists before overwriting any target.
- `dart format` verification passes for changed Dart files.
- `flutter analyze` passes.
- Phase-targeted tests pass.
- The required platform build passes.
- Rollback can restore the exact pre-phase files.
- Execution memory and changelog are updated.
- No unrelated file is changed by the installer.

## P01 acceptance criteria

1. Five permanent execution-memory files exist under `docs/execution`.
2. The state JSON records the real Git branch/commit/status plus Flutter and Dart versions.
3. The project contains isolated, compiling design tokens and breakpoint helpers.
4. Shared components compile without modifying existing screens.
5. The breakpoint test validates phone `<600`, tablet `600..1023`, desktop `>=1024`.
6. The minimum interactive dimension is at least 48 logical pixels.
7. The installer refuses any path or project not matching Yalla Accounts.
8. Analyzer, targeted test, and Windows debug build complete successfully.
9. The terminal prints exactly `YALLA P01 RESULT: PASS` at the end.

## P01 does not do

- It does not redesign a user-facing screen.
- It does not change navigation.
- It does not change the database or business logic.
- It does not remove or rename an existing feature.
- It does not push to GitHub.


## P02 acceptance — current status
- [x] Mobile-first login / existing-account entry foundation.
- [x] First-owner four-step workshop setup flow.
- [x] PIN stored via platform secure storage using canonical password hashing.
- [x] Biometric / Windows Hello integration when supported.
- [x] Offline unlock only for a previously valid persisted local session.
- [x] Account recovery paths preserved.
- [x] Commercial access and activation authority preserved.
- [ ] Authoritative customer phone SMS OTP start/verify integration. **BLOCKER — required before P02 PASS.**
