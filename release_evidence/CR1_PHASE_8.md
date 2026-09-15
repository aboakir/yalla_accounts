# CR1 Phase 8 — Accounting + Operational Regression

Status: PASS (implementation Gate 8).
Reviewed 2026-09-15.
No production Supabase mutation, push, reset, clean, or historical backup deletion was performed.

## Proven revision pair

- Phase 7 Control base: `1ec9dd7946900fc33f2049c308e787abf10ca4ef`
- Phase 7 Accounts base: `21e2165d6be4b167d2cc3bc93e461c5ec2debd40`
- Tested Phase 8 Accounts code: `b12d4f4900bad11ecd30ecad512dd89c025e7c7c`
- Phase 8 Control code: unchanged from Phase 7 code; Phase 8 Control worktree was regression-verified only.

## Phase 8 closure

1. Upgraded the Accounts database contract from v75 to v76.
2. Added `raw_materials` to the versioned schema and core-table contract.
3. Added an explicit v75→v76 raw-material migration regression test.
4. Made canonical Party backfill a trusted migration operation while preserving READ_ONLY business-write enforcement.
5. Restored all commercial write guards immediately after trusted migration backfill.
6. Centralized remaining payroll GL posting through `PostingEngine`.
7. Removed remaining hardcoded ILS usage from changed payment/payroll presentation paths.
8. Restored Store Distribution onboarding gating and public legal links on login.
9. Added async mounted protection to supplier statement PDF export.
10. Updated stale source-contract tests to the current CR1 architecture without weakening functional assertions.
## Gate 8 verification

- Accounts full suite: `flutter test --no-pub --concurrency=1` — **679 passed, 0 failed, 21 skipped**.
- Accounts modified production files: `flutter analyze --no-pub <10 Phase-8 files>` — **No issues found**.
- Accounts `git diff --check`: PASS.
- Control Server: `npm test` — **139 passed, 0 failed, 0 skipped**.
- Control Flutter: `flutter test --no-pub` — **327 passed, 0 failed**.
- Control analyzer: `flutter analyze --no-pub` — **No issues found**.
- Control generated Windows files were stat/line-ending noise only; worktree hashes matched the index and code diff was empty.

## Regression truth

The original Phase-8 baseline was 643 PASS / 21 SKIP / 35 FAIL. During remediation, a later mixed/stale run showed additional source-contract and timeout noise. Every known failure cluster was isolated, classified, and either fixed in product code or updated where the test was pinned to obsolete architecture such as DB v69, deprecated SMS onboarding, or the old embedded Control login.

The final clean, sequential Accounts run finished with 679 PASS / 21 SKIP / 0 FAIL. The skipped cases are pre-existing environment/live acceptance gates; they are not implementation failures.

Global project analyzer debt remains outside Phase 8: 0 errors, 98 warnings, 282 infos across legacy/unmodified files. No new analyzer issue remains in any Phase-8 modified production file.

## Deployment truth

This Gate proves implementation and local regression closure. It does not claim deployed HTTPS, production PostgreSQL acceptance, physical-device acceptance, App Store/Play Store acceptance, or real-workshop Pilot acceptance; those remain later CR1 phases.

Production Supabase changes: NONE.
Production Control database changes: NONE.
Codex usage for Phase 8: NONE.
Live acceptance: `BLOCKED_EXTERNAL_LIVE_ACCEPTANCE`.
Implementation blockers: NONE.

Gate 8: PASS.
Next phase: 9 — DO NOT EXECUTE from this evidence commit.