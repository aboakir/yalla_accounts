# CR1 Phase 5 — direct implementation checkpoint
Date: 2026-09-15
Status: IMPLEMENTATION CHECKPOINT — not final Gate 5 sign-off
Accounts branch: commercial/CR1-phase-05
Accounts base: f7b742c1b6e12adaa6fcc97f4766301d6f73cb25
Control worktree: D:\yalla_control_cr1_phase5
Control branch: cr1-phase05-licensing
Control base: e8829bc16b78275dccae985d5f964c639612d09f

## Direct implementation completed
- Added the missing Phase-4-to-Phase-5 bridge from approved onboarding to real activation.
- Live onboarding status is revalidated before any local commercial identity binding.
- The fresh local placeholder organization is rebound atomically to the canonical Control organization before DeviceIdentity creation.
- Rebinding is fail-closed if local users, workshop settings, device identity, activation receipt, active sync history, queued sync baseline, remote sync candidate, or other scoped operational state exists.
- Staged request/customer organization must match the fresh server response; a cache mismatch performs no identity mutation.
- Fresh baseline sync registry rows are rebound only after proving they are revision 0 historical baseline and have never been queued.
- Onboarding UI now exposes an explicit "متابعة إلى تفعيل الجهاز" action only after APPROVED state.
- Activation continues through the existing V2 challenge -> Ed25519 proof -> complete -> signed envelope flow.
- No activation code is persisted by Accounts; no private device key is written to SQLite.
- First Owner remains blocked until a cryptographically verified activation receipt exists.

## Anti-fraud / lifecycle hardening
- Reused initial activation code on a second device is denied.
- Forged proof, wrong device, wrong installation, cross-customer scope, expired challenge and replay behavior remain covered by Control V2 tests.
- Missing secure Ed25519 key after a bound activation raises DeviceIdentityRecoveryRequired; silent key rotation is blocked.
- Reinstall/cloned unbound metadata rotates to a fresh identity; bound identity cannot silently rotate.
- Added explicit local-clock rollback defense: local time earlier than the latest trusted licensing/server time fails closed into READ_ONLY_VALIDATION_REQUIRED.
- SQLite operational write triggers independently deny business writes when trusted licensing time is materially ahead of the local clock.
- A later fresh server lifecycle decision can restore the trusted time projection after the clock is corrected.

## Verification already executed
- Control Server full suite: 124 PASS / 0 FAIL.
- Control Flutter focused device/license/lifecycle/customer suite: 69 PASS / 0 FAIL.
- Control Flutter analyze after dependency restore: PASS / no issues.
- Accounts Phase-5 real isolated E2E: PASS.
- Accounts clock rollback application + DB enforcement tests: PASS.
- Accounts modified/new Dart analyzer: PASS / no issues.
- license_envelope_verifier.dart is unchanged from Phase 4.
- git diff --check: PASS for Accounts and Control.

No Production Supabase changes, no push, no RPC deletion, no backup deletion, and no Phase 6 work were performed.

## Final direct regression rerun
After the final canonical-binding, server-time and clock-rollback refinements, the combined Accounts Phase-5 regression command completed with 32 PASS / 0 FAIL. It covered the new first-activation E2E, Phase-4 onboarding regression, device identity, V2 HTTP contract, activation, First Owner bootstrap, activation/owner regressions, lifecycle, validation DB enforcement/window and subscription-access/clock rollback tests.
