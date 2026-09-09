# Stage 46 — Subscription and license enforcement

Status: PASS for implemented application behavior and automated acceptance (2026-09-09).

## Implemented
- One SubscriptionAccessPolicy governs the authenticated commercial gate and local/server license runtime projections.
- ACTIVE, TRIAL and GRACE permit writes within signed validity and offline-validation windows. EXCEPTION is time-limited by the same signed windows.
- EXPIRED is read-only even when its expires_at timestamp is in the future. FROZEN/SUSPENDED and CANCELLED/REVOKED are read-only.
- DEMO is explicitly read-only for real workshop data; it does not create a synthetic authenticated owner or an unsigned trial.
- Unknown statuses fail closed. Absent/invalid activation cannot pass requireOperationalWrite.
- Sensitive service authorization checks the signed license before operational writes. Read/report/export/backup permissions remain available subject to the user's existing role. Restore is a mutation and requires a writable licensed session in addition to Owner authorization.
- Current subscription screen shows Arabic state, expiry and effective write/read-only access, loading/error/retry states, with an entry under sidebar Settings.
- Ed25519 verification remains mandatory; no private license-signing key was added to the application. The envelope schema documents all accepted states.

## Verification
- 72 tests passed in .dart_tool/stage46-final-tests.log.
- Covers each state through the real commercial gate with canonical owner/organization records, runtime projection, SQL write enforcement, retained read/backup metadata access, timestamp boundaries, offline grace, missing activation, and state normalization.
- Existing Ed25519 activation test now signs each state, verifies it and rejects payload tampering with an unchanged signature.
- Arabic subscription screen tested at 430x932, 390x844 and 844x390 without layout exceptions.
- Owner restore regressions now enforce credentials and a licensed writable restore session instead of obsolete username-only demo login.
- dart format and flutter analyze completed. No analyzer errors; repository warnings/info remain. See .dart_tool/stage46-analyze.log.

## Files changed for Stage 46
- lib/core/licensing/lifecycle/subscription_access_policy.dart (new)
- lib/core/licensing/lifecycle/license_runtime_service.dart
- lib/core/licensing/activation/license_envelope_verifier.dart
- lib/features/auth/services/commercial_access_gate_service.dart
- lib/features/auth/services/authorization_guard.dart
- lib/features/subscription/screens/current_subscription_screen.dart
- lib/core/widgets/sidebar/yalla_sidebar.dart
- server/yalla_licensing_server/crypto/license_envelope.schema.json
- test/commercial/stage46_subscription_access_test.dart (new)
- test/commercial/sec_006_activation_flow_test.dart
- test/commercial/stage_04_subscription_lifecycle_entitlements_test.dart
- test/regression/owner_restore_permission_test.dart

## Boundaries and remaining release risks
- No schema migration/reset, financial calculation changes, real workshop database mutation, phone installation, or IPA build in this stage.
- No live licensing-server deployment or billing-provider acceptance. Production endpoint/key reconciliation remains a deployment prerequisite from the prior audit.
- Administrative organization suspension and invalid signed entitlements retain their existing denial behavior. They are distinct from a valid signed FROZEN subscription. The previously implemented owner export recovery path remains available.
- Automatic approval review rejected a proposed exception for administratively suspended organizations/invalid entitlements; that exception was not applied. It also rejected making the new write check conditional on interactive mode; that exception was not applied.
- Physical iPhone/share-sheet acceptance is still a later device acceptance task; this stage's layout evidence is automated.
- Stage 47 has not started.
