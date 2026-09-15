# CR1 Phase 11 — Production Infrastructure

Status: PASS (implementation Gate 11).
Reviewed 2026-09-15. Phase 12 is not executed by this evidence.
No production Supabase mutation, production PostgreSQL mutation, push, reset, clean, or protected historical-file deletion was performed.

## Proven revision pair

- Phase 10 base — Control: `5ae9ca277c59a88280f72e1db42c79cffa4026a2`
- Phase 10 base — Accounts: `763010eeabf3a2d039198fd2347270a7c035128e`
- Tested Phase 11 Control code: `fe789db29c2d552dce7d6f1a8d4c14f64a9a0fbc`
- Tested Phase 11 Accounts code: `69016ac128196f9b522b4a66b1af1ec24ed5cc24`
- Final evidence-commit pair is recorded with `git notes --ref=cr1-phase11-review show HEAD`.

## Control production infrastructure delivered

1. Production requires explicit `CONTROL_PUBLIC_ORIGIN` as an HTTPS origin; Host and Origin are checked against it.
2. Public socket binding remains denied unless production mode and `CONTROL_ALLOW_PUBLIC_BIND=true` are both explicit.
3. Production HTTP requests fail closed unless TLS is active.
4. Added `/health/live` and DB-aware `/health/ready`; readiness returns 503 while draining.
5. SIGTERM initiates drain, closes idle connections, bounds shutdown, and closes the DB pool.
6. Added production preflight for config, PostgreSQL runtime role, schema checksums, DB connectivity, and audit-chain integrity without automatic DDL.7. Added hardened systemd service, production env templates, TLS reverse-proxy reference, verified PostgreSQL backup timer, and disposable restore drill.
8. Backup jobs use `PGSERVICE`/`PGPASSFILE`, `pg_dump` custom format, `pg_restore --list`, and SHA-256 sidecars; passwords are not placed on the command line.
9. Normal server startup does not initialize or migrate the schema; database changes remain an explicit maintenance operation.

## Accounts production-build contract

- Added `deploy/production_defines.example.json` and a deployment runbook.
- Added `tools/validate_production_defines.dart`; incomplete, placeholder, non-HTTPS, invalid signing-pin, or secret-bearing configs fail validation.
- The real `deploy/production_defines.json` is excluded from Git.
- Activation, lifecycle validation, sync, onboarding, and legacy admin transport all use the same `YALLA_LICENSING_BASE_URL` contract.
- Only the Supabase publishable key is accepted in the public build contract; Service Role/private/database credentials are forbidden.

## Gate 11 verification

- Accounts full regression: `flutter test --no-pub --concurrency=1` — 687 passed, 21 skipped, 0 failed.
- Accounts Phase 11 infrastructure gate — 4/4 passed.
- Accounts validator + gate analyzer — no issues.
- Production-defines CLI: example placeholders rejected; complete contract accepted.
- Android debug APK with validated `--dart-define-from-file` — BUILD PASS.
- Control Flutter full regression — 327 passed, 0 failed.
- Control analyzer — no issues.
- Control Server full regression — 143 passed, 0 failed, 0 skipped.
- Control Phase 11 infrastructure gate — 4/4 passed.
- `npm audit --omit=dev` — 0 vulnerabilities.
- `git diff --check` — PASS on both repositories.## Deployment truth

This Gate proves the production infrastructure contract, deployment artifacts, preflight behavior, health/readiness behavior, validated Accounts build configuration, and regression safety in isolated/local test environments. It does not claim that a public production host, DNS, TLS certificate, production PostgreSQL instance, off-host backup target, or live workshop traffic has been deployed.

Production Supabase changes: NONE.
Production Control database changes: NONE.
Production public deployment performed: NONE.
Codex usage: NONE.
Live acceptance: `BLOCKED_EXTERNAL_LIVE_ACCEPTANCE`.
Implementation blockers: NONE.

Gate 11: PASS.
Next phase: 12 — CI/CD and release engineering; DO NOT EXECUTE from this evidence commit.
