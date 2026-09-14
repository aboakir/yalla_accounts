# CR1 Phase 4 — Accounts signup and pending onboarding
Date: 2026-09-15
Branch: commercial/CR1-phase-04
Base: 3b81af31385c8dcdc604bacad9aedbe9d871b8e2
Gate 4 implementation: PASS. Phase 5 is NOT authorized/executed.

## User flow
Empty-install Login -> Create new workshop -> Cloud signup -> email OTP ->
normal password sign-in -> owner/workshop form -> server PENDING -> restart and
revalidate session/status -> admin approval -> server APPROVED.

The post-OTP password sign-in is deliberate: Supabase signup/recovery both use
OTP AMR. Normal password or configured OAuth AMR + fresh getUser validation is
required for onboarding and commercial bearer supply. No email/metadata role
or local customer/org ID is commercial authority.

Pending owner details and canonical approved response are staged in
pending_customer_onboarding, keyed by verified auth UUID. This is not a users,
roles, auth_sessions, organization_identity or license table. It creates no active
owner or operational permission. APPROVED_AWAITING_ACTIVATION remains blocked
until the next commercial activation phase; existing FirstOwnerBootstrapService
checks were not removed. The cached response is display/storage only; refresh and
restart always require verified session + a fresh server response.

Logout securely records local revocation before remote signout, removes persisted
session and denies stale local/restarted tokens even if remote logout fails.
Recovery password completion uses the same signout path. Remote logout failure
does not imply remote revocation succeeded. Successful logout and old-bearer denial
were exercised against the Auth HTTP fixture.

## Executed tests
Environment: YALLA_CR1_CONTROL_ROOT=D:/yalla_control_cr1_phase4/control_server
Command: flutter test --no-pub followed by:
- test/cloud_auth
- test/commercial/cr1_v2_http_contract_test.dart
- test/commercial/cr1_phase4_onboarding_e2e_test.dart
- test/commercial/sec_006_activation_flow_test.dart
- test/commercial/sec_007_first_owner_bootstrap_test.dart
- test/commercial/sec_008_regression_activation_flow_test.dart
- test/commercial/sec_011_lifecycle_contract_test.dart
- test/commercial/sec_012_periodic_validation_contract_test.dart
- test/commercial/stage_02_login_subscription_roles_activation_completion_test.dart
- test/commercial/stage_03_first_owner_account_security_test.dart
- test/commercial/stage47_onboarding_test.dart
- test/phase02/yalla_phase02_auth_workshop_test.dart
- test/regression/workshop_identity_persistence_test.dart

Final broad result: 65 PASS, 3 PRE-EXISTING failures, zero Phase-4-caused failures.
Fresh E2E is not skipped. New session safety tests: 3 PASS.
E2E exercises real SDK HTTP signup/OTP/password reset/logout/login, isolated fresh
SQLite, real Control HTTP admin review/provisioning and PostgreSQL persistence.
No mocked or manually inserted commercial records are used in this E2E.
Other auth user cannot read the approved request. Trial is unstarted; license
PENDING_ACTIVATION; no local user, license receipt, financial entry or repair is
created by onboarding. First Owner operational creation still throws before activation.

## PRE-EXISTING (not repaired)
1. stage47_onboarding_test: new owner verifies phone once, saves workshop, then
   safely retries failed PIN — expects the old SMS button absent in the base UI.
2. yalla_phase02_auth_workshop_test: first owner activation/phone OTP source markers.
3. yalla_phase02_auth_workshop_test: old four-step registration source markers.

The old registration screen, bootstrap service and these test files are unchanged.
Base/current normalized Git blobs are identical:
- register_user_screen.dart: 24111a723a53c0d4badbf77df8a7249886195d60
- first_owner_bootstrap_service.dart: 89d4667c40c2f9af2cb0c3f8ed412ddbce55f505
The missing SMS/four-step markers are also absent in the specified base commit.
No tests were deleted, skipped or weakened to hide these failures.

## Static analysis and preserved files
All 11 modified/new Dart files: analyzer PASS, no issues.
Whole-repository analyzer was run: 379 historical findings (0 errors, 98 warnings,
281 infos), including old audit artifacts. None are in the changed Phase 4 paths.
No unrelated historical lint cleanup was performed.

An initial E2E exposed an empty-activation check reaching the default device provider.
activation_state_repository.dart now checks for a receipt before touching device
identity; final E2E uses only the temp database. This does not weaken verification.
license_envelope_verifier.dart, V2 wire bodies, FirstOwnerBootstrapService and
existing register-user operational checks remain unchanged.

No production Supabase modifications, RPC deletion, fake production accounts,
backup deletion, reset/discard, push, or Phase 5. All pre-existing untracked Accounts
backups/editor/output files are preserved.

LIVE ACCEPTANCE: BLOCKED_EXTERNAL_LIVE_ACCEPTANCE (deployed HTTPS Control, Supabase
email-confirmation/OTP delivery and physical-device acceptance still required).
See matching Control CR1_PHASE_4.md and accounts-onboarding-v2.md for server contract.
