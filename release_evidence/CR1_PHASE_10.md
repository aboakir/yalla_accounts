# CR1 Phase 10 — Security Hardening

Status: PASS (implementation Gate 10).
Reviewed 2026-09-15. Phase 11 is not executed by this evidence.
No production Supabase mutation, push, reset, clean, or protected historical-file deletion was performed.

## Proven revision pair

- Phase 9 base — Control: `47ecc193f1e857fe45f746f7d9094626dfca49f1`
- Phase 9 base — Accounts: `2e8d02856abb337139b49e977b20582060da92a4`
- Tested Phase 10 Control code: unchanged from Phase 9 (`47ecc193f1e857fe45f746f7d9094626dfca49f1`)
- Tested Phase 10 Accounts code: `93485d39582483301ba61482d5c85c99014a1d5d`
- Final evidence-commit pair is recorded with `git notes --ref=cr1-phase10-review show HEAD`.

## Accounts hardening delivered

1. Added a single `ReleaseDiagnostics` boundary: raw exceptions, stack traces and local paths are emitted only in debug mode.
2. Startup/bootstrap no longer exposes raw errors to release users; the public failure text is a stable safe code.
3. All direct `debugPrint` calls under production `lib/` were routed through the release-safe diagnostics boundary.
4. Android now rejects cleartext traffic at the manifest level.
5. Android cloud backup/device-transfer extraction is explicitly disabled for app data, including database/files/preferences.
6. Existing iOS configuration contains no ATS arbitrary-load exception; HTTPS remains the default transport policy.
## Security verification

- Accounts full regression: `flutter test --no-pub --concurrency=1` — 683 passed, 21 skipped, 0 failed.
- Phase 10 targeted security regression — PASS.
- Accounts analyzer for every Phase-10 modified/new Dart file — no issues.
- Android debug build after manifest hardening — PASS (`app-debug.apk`).
- Direct `debugPrint` outside `ReleaseDiagnostics` in production `lib/` — 0.
- `git diff --check` — PASS.
- Control Flutter full regression — 327 passed, 0 failed.
- Control analyzer — no issues.
- Control Server full regression — 139 passed, 0 failed, 0 skipped.
- `npm audit` (production and complete dependency tree) — 0 vulnerabilities at info/low/moderate/high/critical.
- Tracked-source secret scan found no hard-coded private key, API-key, or service-role secret material.

## Gate 10 matrix

- Authentication/session/MFA/recovery regression: PASS.
- CSRF and session rotation: PASS.
- RBAC / privilege revocation / Break Glass scope: PASS.
- Signed licensing/device authority and forged-identity denial: PASS.
- Sync proof/idempotency/conflict quarantine: PASS.
- Audit immutability and rollback behavior: PASS.
- Release diagnostic leakage: CLOSED.
- Android cleartext transport: DENIED BY PLATFORM.
- Android automatic app-data backup/transfer: DENIED BY PLATFORM.
- Dependency vulnerability audit: CLEAN.
## Deployment truth

This Gate proves application/server security hardening and isolated implementation behavior. It does not claim deployed HTTPS infrastructure, production PostgreSQL, production secret rotation, physical-device penetration testing, or live-workshop acceptance; those belong to later CR1 phases.

Production Supabase changes: NONE.
Production Control database changes: NONE.
Codex usage: NONE.
Live acceptance: `BLOCKED_EXTERNAL_LIVE_ACCEPTANCE`.
Implementation blockers: NONE.

Gate 10: PASS.
Next phase: 11 — production infrastructure; DO NOT EXECUTE from this evidence commit.