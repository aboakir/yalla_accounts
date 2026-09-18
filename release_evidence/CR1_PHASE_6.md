# CR1 — Phase 6 final review and gap closure

Status: PASS (implementation Gate 6). Phase 7 is not authorized.
Reviewed 2026-09-15. No production Supabase changes, push, reset, clean or backup deletion.

## Proven revision pair

- Control code: 13394de2bc1902829cd4548ff59ff1e1b7d3fff3
- Accounts code: c58138aa0009881cad98152de8b58af40d51f8c9
- Initial reviewed HEADs: fb2a31b84a7aa09189d21986ea724f3f64043a3f / 6e0e538746a69bf0303e77d62932398029a97b87.
- This evidence commit follows the tested code commits. Exact final evidence-commit
  pair is attached to each final HEAD as `git notes --ref=cr1-phase6-review show HEAD`.

## Gap closure

1. Audited all Control subscription INSERT/UPDATE paths. Creation starts PENDING;
   activation redemption, administrative lifecycle changes and expiry maintenance
   assert declared transitions inside their transactions. Billing, plan, start-date
   and grace-extension actions cannot exploit Cartesian from/to sets to change
   lifecycle state. Renewal/expiry-date changes do not silently clear suspension.
2. PAST_DUE was deliberately not added. UNPAID describes billing independently of
   lifecycle; marking paid/unpaid neither renews dates nor revives access. There is
   no configured dunning/due-date state contract justifying a new lifecycle state.
   The exhaustive transition tests and billing tests pass. No server schema change.
3. Added a shared signed capability operation boundary, wired to existing mutation
   authorization. ACCOUNTING_CORE protects financial operations;
   WORKSHOP_REPAIRS protects repair mutations. The real runtime re-verifies the
   current bound signed receipt; missing/false/wrong-typed capability fails closed.
   Versioned SQLite guards also deny legacy/direct mutations. Reads/export/backup
   retain the established RBAC/read-only policy. No local plan/trial upgrade.
4. Exact V2 completion replay now checks current effective revision/entitlements
   and expiry before returning a cached envelope. Accounts atomically rejects
   lower-revision or older-issued refreshes. The production verifier is unchanged.
5. Signed temporary grants cannot outlive the earliest active override expiry.
   Expiry recomputes the *current* baseline, including changes made during the
   override. Cryptographic tests prove the before/after envelopes and stale denial.
6. MAX_USERS remains signed authority; new/reactivated seats fail at capacity and
   restrictive states cannot grant seats. MAX_DEVICES is enforced server-side;
   a valid proof at full capacity creates no device and does not consume activation.
   Below-usage plan downgrade rejects atomically with LIMIT_BELOW_USAGE; records
   are unchanged. A lower signed local seat quota retains existing users and
   prevents additional/reactivated seats rather than deleting data.

## Gate matrix

Every listed transition passed with Control DB status compared to server effective
entitlements, actual HTTP response, Ed25519-verified envelope and Accounts operation
authorization. No commercial-record mock replaces the E2E business flow.

- FREE → PRO: PASS
- PRO → FREE: PASS
- TRIAL → ACTIVE: PASS
- TRIAL → EXPIRED: PASS
- ACTIVE → SUSPENDED: PASS
- SUSPENDED → ACTIVE: PASS
- ACTIVE → EXPIRED: PASS
- EXPIRED → RENEWED: PASS

ACTIVE → CANCELLED → ACTIVE also passes. Restricted signed states deny both
financial and repair callbacks, and renewal/restoration opens operations only after
fresh verification. SQL guard tests preserve rows, reads and backup settings.
Reopening the isolated existing workshop preserves data and feature enforcement.

## Verification

- Control server: `npm test` — 134 passed, 0 failed, 0 skipped.
- Control Flutter: `flutter test --no-pub` — full suite 327 passed.
- Control analyzer: `flutter analyze --no-pub` — no issues.
- Accounts final regression set below: 41 passed, 0 failed.
- Accounts analyzer: all 15 Phase-6 changed/new Dart files — no issues.
- Final explicit state-machine rerun: 4 passed.
- Git whitespace checks: PASS.
- No unresolved Phase-6 regression; test-fixture setup mistakes and four lint
  notes encountered while adding tests were corrected and rerun.
- Verifier blob unchanged: 3f1471b1c4e005539e2285efbbfdfc5fa7e5f834.

Accounts command (set YALLA_CR1_CONTROL_ROOT to this Control control_server first):

```text
flutter test --no-pub test/commercial/cr1_phase6_subscription_entitlements_e2e_test.dart test/commercial/cr1_phase6_signed_feature_authorization_test.dart test/commercial/stage_04_subscription_lifecycle_entitlements_test.dart test/commercial/stage46_subscription_access_test.dart test/commercial/sec_009_licensed_user_seats_test.dart test/commercial/sec_011_lifecycle_contract_test.dart test/commercial/sec_011_read_only_enforcement_test.dart test/commercial/sec_012_validation_window_test.dart test/commercial/sec_012_db_enforcement_test.dart test/commercial/cr1_phase5_first_activation_e2e_test.dart
```

Logs are stored alongside this report as phase6_final_*.log (repository-specific).

## Scope and deployment truth

PGlite/SQLite and loopback HTTP are isolated. Auth/catalog initialization is fixture
setup; licensing uses actual server business operations and Ed25519 signatures.
The feature SQL projection unit test intentionally initializes a local projection;
it is not presented as cryptographic E2E evidence. Occupied-capacity adversarial
fixtures are likewise separate negative tests.

New capability keys require explicit ACTIVE server catalog entries and plan
assignments in a deployed environment. Missing configuration denies operations;
this review does not silently assign paid rights or mutate production catalogs.
See Control `control_server/contracts/accounts-commercial-features-v2.md`.

Fresh validation cannot preserve removed features. Offline devices cannot learn
an unscheduled server change instantly; existing signed validity/validation windows
still apply. After temporary-grant expiry, access stays closed until fresh current
authority is verified. No physical/live deployment acceptance is claimed here.

The Supabase skill guided isolated-only verification; no Auth/RPC/schema production
mutation was performed. PostgreSQL review retained transactional locking and
avoided unnecessary migrations.

Blockers: NONE for isolated implementation Gate 6.
Next phase: 7 — DO NOT EXECUTE.
