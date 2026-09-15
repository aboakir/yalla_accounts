# CR1 Phase 7 — Offline + Secure Sync

Status: PASS (implementation Gate 7).
Reviewed 2026-09-15. Phase 8 is not executed by this evidence.
No production Supabase mutation, push, reset, clean, or historical backup deletion was performed.

## Proven revision pair

- Phase 6 base — Control: `30a6016a3f979d02c39a4b0026a7575388ee0fa7`
- Phase 6 base — Accounts: `b7031729624cbf3d4f19a861c557d55acd85eab1`
- Tested Phase 7 Control code: `3386196325839fd992a2943ba2871d3e808caa09`
- Tested Phase 7 Accounts code: `e3900eb71640c32121a96057bd25642bddc2cb4d`
- Final evidence-commit pair is recorded with `git notes --ref=cr1-phase7-review show HEAD`.

## Implemented boundary

Accounts remains local-first and accounting-authoritative. Control Server is the authenticated central sync journal only.
The official Phase-7 path is `verified customer bearer → bound installation/device → Ed25519 challenge/proof → idempotent remote journal`.
Client-supplied customer/organization/plan/role values never grant authority.
## Gap closure

1. Upgraded the transitional Sync v1 contract to version 2 with explicit request/response schemas.
2. Added approved Control migration 7: durable sync challenges, append-only remote journal, entity heads, conflict quarantine, RLS/runtime grants, and immutable-history triggers.
3. Added real `/v1/sync/challenge` and `/v1/sync/complete` server implementation with bearer identity, installation binding, device binding, Ed25519 proof, commercial-state checks, bounded rate limiting, and exact completion replay.
4. Added payload and immutable snapshot SHA-256 verification plus closed entity-type and operation sets.
5. Added server idempotency on both `idempotency_key` and immutable `change_id`; same identity with changed semantic request is denied.
6. Added revision heads. Concurrent/stale base revisions are journaled as `CONFLICT`; they never advance the accepted entity head.
7. Accounts now attaches the exact immutable local change metadata linked to each outbox row rather than rebuilding a historical mutation from the latest document state.
8. Local changes captured by Sync Foundation but lacking a feature-specific outbox are materialized once into durable outbox messages.
9. Sync production wiring now uses the same network-verified Supabase bearer boundary as commercial licensing. Device proof alone is never customer authority.
10. Remote financial proposals remain candidates/conflicts only. They do not create, alter, delete, reverse, or duplicate GL postings.
## Gate 7 matrix

- Offline local mutation commit: PASS.
- App/database restart with unsent mutation: PASS.
- Reconnect and retry: PASS.
- Timeout/lost acknowledgement then retry: PASS.
- Duplicate send / exact replay: PASS — one accepted remote mutation only.
- Changed payload with reused idempotency/change identity: DENY VERIFIED.
- Server/database restart between challenge and completion: PASS.
- Forged device proof: DENY VERIFIED.
- Wrong installation: DENY VERIFIED.
- Suspended device: DENY VERIFIED.
- Concurrent revision: CONFLICT QUARANTINED; accepted head unchanged.
- Financial remote candidate: QUARANTINED; GL row count unchanged.
- Duplicate financial posting: 0.

## Verification

- Control Server full suite: `npm test` — 139 passed, 0 failed, 0 skipped.
- Control Flutter full suite: `flutter test --no-pub` — 327 passed, 0 failed.
- Control analyzer: `flutter analyze --no-pub` — no issues.
- Accounts Phase-7 + Sync Foundation regression: 16 passed, 0 failed.
- Accounts analyzer for every Phase-7 modified/new Dart file: no issues.
- `git diff --check`: PASS before code commits.
## Deployment truth

The Gate is isolated implementation evidence using PGlite, SQLite, loopback HTTP, actual Ed25519 keys/proofs, persistent restart fixtures, and the real application/server code paths.
It does not claim deployed HTTPS, physical-device acceptance, production PostgreSQL, or live workshop acceptance; those remain later CR1 phases.

Production Supabase changes: NONE.
Production Control database changes: NONE.
Live acceptance: `BLOCKED_EXTERNAL_LIVE_ACCEPTANCE`.
Implementation blockers: NONE.

Gate 7: PASS.
Next phase: 8 — DO NOT EXECUTE from this evidence commit.
