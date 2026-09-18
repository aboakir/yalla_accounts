# CR1 — Phase 5 final independent review

Date: 2026-09-15. Implementation Gate 5: **PASS**.
Scope: review existing Phase 5, close demonstrated gaps, retest; no Phase 6.

## Proven flow

Fresh SQLite database → isolated Supabase SDK signup/OTP/password login →
authenticated onboarding → real Control admin approval and commercial records →
fresh APPROVED status → canonical local organization binding before device identity →
V2 activation challenge → device Ed25519 proof → transactional server redemption →
signed license verified by the unchanged Accounts verifier → BOUND device →
exactly one First Owner. Before activation, owner creation and a local auth session
are not granted. Approval reserves the trial; redemption alone starts it.

The E2E uses real application services, HTTP routes and isolated PGlite/SQLite.
Only Auth delivery and physical secure storage are test boundaries. It does not
insert mock commercial tenants/licenses to bypass the approval/activation flow.
Local adversarial unit tests and legacy device-management fixtures are explicitly
separate from this E2E.

## Commit provenance

| Stage | Control | Accounts |
| --- | --- | --- |
| Phase 4 base | e8829bc16b78275dccae985d5f964c639612d09f | f7b742c1b6e12adaa6fcc97f4766301d6f73cb25 |
| Supplied Phase 5 checkpoint | ef81c2e1c58b043108a895cbb3eecebddb907a2e | 0a42f62503f485ce34dfa63500c6bab2ca3bde27 |
| Final tested code | 18b019d2ed1e955ea2daaf6abfd2f217618f67aa | 38015b7dad457315638a68a36887a61147a9895f |

Final evidence commits follow the tested-code commits with documentation only.
The **exact final commit pair** is recorded in Git notes attached to each final
evidence commit, under `refs/notes/cr1-phase5-review`. Read it with:

```text
git notes --ref=cr1-phase5-review show HEAD
```

This avoids inventing a hash for a commit that would need to contain its own hash.

## Gaps closed during independent review

1. **Unscoped legacy data rebind.** The initial guard inspected tables with
   organization_id and accepted revision-zero sync baselines. Legacy single-workshop
   tables can lack that column, and upgrades can baseline actual customer history.
   A new adversarial test reproduced an unauthorized rebind (1 failed / 3 passed
   before correction). The guard now rejects populated non-bootstrap tables,
   including unknown legacy tables, and rejects custom account codes, real supplier/
   Party records, used document sequences and multiple organization rows.
   Only explicit technical metadata and inert installation catalog seeds survive.
   No business data is deleted or moved. Validation now occurs within the rebind
   transaction, before commit.

2. **Clock tolerance eroding effective time.** Local refresh previously evaluated
   expiry against the rolled-back local time even inside tolerance and persisted
   a lower effective time. It now evaluates and persists max(current, trusted floor).
   A 90-second skew remains usable with a current license but cannot reopen expired
   ACTIVE/TRIAL/GRACE licenses or an expired validation window.

3. **Independent SQL protection and safe trigger installation.** Versioned
   `_clock_v5` guards are added with IF NOT EXISTS, without a drop/recreate gap in
   existing guards. They also inspect activation/validation server timestamps before
   a runtime refresh and use the time floor for expiry. Authentication password/
   failure counters, audit and backup metadata remain usable while business writes
   and role changes are denied. A corrected fresh server validation restores
   legitimate operation. No OS clock, production data or migration was modified.

4. **Proof coverage.** Extended real E2E with pre-activation owner denial, no user/
   session/identity side effect, exact receipt binding, duplicate-owner rejection,
   corrupted signature/untrusted key rejection, same-device and second-device code
   reuse denial. Control V2 now asserts trial start within database-observed server
   timestamps, exact duration, one trial ledger row, unchanged dates after retries,
   and denial for SUSPENDED, REVOKED and REPLACED devices, including old completion replay.

## Canonical organization safety

Fresh bearer-authenticated server status is mandatory. The staged auth UUID,
request ID and canonical organization must match; cache only supplies consistency
checks, not authority. Offline or another authenticated user cannot use the cache.
No users/workshop/device/activation receipt may precede binding. Bootstrap stays
PENDING until verified activation. A late injected transaction failure leaves a
full table snapshot unchanged. Repeated prepare is idempotent. Immutable baseline
sync events and entity UUIDs remain byte-for-byte intact; future sync events use
the canonical organization. Tampered cached organization is rejected in real E2E.

## Anti-fraud matrix

| # | Scenario | Result | Executed evidence |
| --- | --- | --- | --- |
| 1 | valid first activation | PASS | Accounts cr1_phase5_first_activation_e2e_test + Control accounts-v2 |
| 2 | reused activation code | DENY VERIFIED | Phase 5 E2E, same original device with new challenge request |
| 3 | same code from second device | DENY VERIFIED | Phase 5 E2E; Control accounts-v2 |
| 4 | forged Ed25519 proof | DENY VERIFIED | Control accounts-v2 forged/wrong device/installation/customer test |
| 5 | wrong device_id | DENY VERIFIED | Control accounts-v2 |
| 6 | wrong installation_id | DENY VERIFIED | Control accounts-v2 |
| 7 | cross-customer access | DENY VERIFIED | Control accounts-v2 parallel/cross-customer and Phase 3 identity tests |
| 8 | expired activation authority | DENY VERIFIED | Control accounts-v2 explicit expired authority: no challenge/device; remains ISSUED |
| 9 | expired challenge | DENY VERIFIED | Control accounts-v2 |
| 10 | replayed completion | NO DUPLICATE MUTATION | Control accounts-v2 concurrent + persisted restart + exact replay |
| 11 | same idempotency key, changed request | DENY VERIFIED | Control accounts-v2 |
| 12 | lost private key after BOUND | FAIL-CLOSED VERIFIED | Phase 5 E2E; Accounts sec_005 |
| 13 | cloned/reinstalled UNBOUND identity | NEW IDENTITY VERIFIED | Accounts sec_005: new install/device/key, generation increments |
| 14 | BOUND silent rotation | DENY / RECOVERY REQUIRED | Accounts sec_005; Control V2 installation/generation/key binding |
| 15 | revoked device | DENY VERIFIED | Control accounts-v2 inactive-state loop; commerce terminal revocation |
| 16 | suspended device | DENY VERIFIED | Control accounts-v2 inactive-state loop |
| 17 | replaced old device | DENY VERIFIED | Control accounts-v2 inactive-state loop + reviewed replacement HTTP test |
| 18 | local clock rollback | READ ONLY VERIFIED | stage46 service/SQL tests; SEC.012 DB enforcement |
| 19 | tampered signed license | DENY VERIFIED | Phase 5 E2E invalid signature; sec_006 payload tampering |
| 20 | wrong signing key | DENY VERIFIED | Phase 5 E2E untrusted signing anchor; Control signing verifier tests |

## Device lifecycle and trial

Control commerce tests prove terminal revocation, organization-scoped reviewed
replacement and rollback. Existing authenticated admin HTTP tests exercise the
break-glass review gate and deny the old installation. V2 tests independently
deny inactive device proof and replay. The prepared-target fixture is not a claim
of physical device enrollment acceptance. Private keys remain outside SQLite;
losing a BOUND key fails closed, while an UNBOUND clone rotates to a new identity.

Trial start is not forced to equal the later response serialization timestamp:
both are server timestamps at different points in the same transaction. The test
uses measured database timestamps to bound start and response time, checks the
exact 14-day duration and verifies no retry/renew-validation/second-device extension.

## Executed commands and results

Environment: Node 26.3.0, Flutter 3.44.8,
Dart 3.12.2; Windows. All final executions returned exit code 0.

Control Server (control_server working directory):

```text
npm test
```

125 PASS, 0 FAIL, 0 skipped.

Control Flutter:

```text
flutter test --no-pub test/device_management_test.dart test/license_activation_management_test.dart test/lifecycle_snapshot_refresh_test.dart test/customer_management_test.dart
flutter analyze --no-pub
```

69 PASS; analyzer NO ISSUES.

Accounts (PowerShell):

```powershell
$env:YALLA_CR1_CONTROL_ROOT='D:/yalla_control_cr1_phase5/control_server'
flutter test --no-pub test/commercial/cr1_phase5_first_activation_e2e_test.dart test/commercial/cr1_phase5_canonical_binding_test.dart test/commercial/cr1_phase4_onboarding_e2e_test.dart test/commercial/sec_005_device_identity_test.dart test/commercial/cr1_v2_http_contract_test.dart test/commercial/sec_006_activation_flow_test.dart test/commercial/sec_007_first_owner_bootstrap_test.dart test/commercial/sec_008_regression_activation_flow_test.dart test/commercial/sec_008_regression_owner_bootstrap_test.dart test/commercial/sec_011_lifecycle_contract_test.dart test/commercial/sec_012_db_enforcement_test.dart test/commercial/sec_012_validation_window_test.dart test/commercial/stage46_subscription_access_test.dart
flutter analyze --no-pub lib/features/onboarding/approved_onboarding_activation_service.dart lib/features/onboarding/customer_onboarding_screen.dart lib/core/licensing/lifecycle/license_runtime_service.dart lib/core/services/db/tables/license_runtime_tables.dart test/commercial/cr1_phase5_first_activation_e2e_test.dart test/commercial/cr1_phase5_canonical_binding_test.dart test/commercial/stage46_subscription_access_test.dart
```

39 PASS, 0 FAIL, 0 skipped. Seven changed/new Phase 5 Dart files: NO ISSUES.
`git diff --check`: PASS in both repositories.

The pre-fix rebind test deliberately failed and is retained as a local log.
During test development, a new test fixture lacked the required owner flag; that
fixture was corrected. A too-strict equality between redemption and response
timestamps was corrected to database-bounded assertions. No unresolved failure or
unrelated historical failure was hidden in these final results.

Machine-readable commands, log names and SHA-256 hashes are in
`CR1_PHASE_5_manifest.json`. Logs remain local generated artifacts and are not
credentials or required source dependencies.

## Verifier, authority and external acceptance

Accounts verifier is **UNCHANGED** relative to Phase 4 and the supplied checkpoint.
Git blob: `3f1471b1c4e005539e2285efbbfdfc5fa7e5f834`.
Commercial identity is still server-resolved from verified Supabase identity, not
client email/metadata/customer IDs. V2 bearer + contract version 2 remain mandatory.
Legacy endpoints remain compatibility-only, disabled by default and forbidden in
production. No Supabase RPCs or Control migrations were changed.

Auth boundary review followed the Supabase skill/security checklist and the
[official network getUser documentation](https://supabase.com/docs/reference/javascript/auth-getuser).
Transaction review followed the PostgreSQL skill: network identity verification
outside mutation transactions, short server transactions, consistent scoped locks,
and rollback/concurrency tests. Neither required a new production schema operation.

Production Supabase changes: **NONE**.
Implementation blockers: **NONE**.
Live acceptance: **BLOCKED_EXTERNAL_LIVE_ACCEPTANCE** — production HTTPS/actual
OTP delivery and physical secure-storage/reinstall/replacement acceptance were not
performed. Isolated PASS is not a production/hardware acceptance claim.

No reset, clean, discard, push, backup deletion or Phase 6 work.
Accounts historical untracked backups, patch, .vscode and output remain untouched.
Next phase: **6 — DO NOT EXECUTE**.
