# CR1 — Phase 2 Accounts transport evidence

Date: 2026-09-15. Contract version: 2. Phase 3 not started.

Both activation/lifecycle HTTP transports now accept an injectable bearer-token
provider, send Authorization and X-Yalla-Contract-Version: 2, reject absent
identity, disable redirects and reject incompatible response versions.
Activation codes remain opaque and case-sensitive. No local customer ID is
used as commercial authority. No credential is hardcoded.

The production identity/session provider is intentionally deferred to Phase 3,
as requested. This commit establishes and tests that clean boundary only.

## Verified

- Targeted Flutter suite: 8 PASS, 0 failed, 0 skipped.
- dart analyze on the two transports, provider typedef and new test: no issues.
- Existing license_envelope_verifier.dart: unchanged.
- git diff --check: clean.

Set YALLA_CR1_CONTROL_ROOT to D:/yalla_control_cr1_phase2/control_server after
running npm ci there. Run:

    flutter test --no-pub test/commercial/cr1_v2_http_contract_test.dart test/commercial/sec_006_activation_flow_test.dart test/commercial/sec_008_regression_activation_flow_test.dart test/commercial/sec_011_lifecycle_contract_test.dart test/commercial/sec_012_periodic_validation_contract_test.dart

The cross-repository test validates actual Dart request bytes against the
official JSON Schemas, forwards those bytes to the real isolated Control server,
validates its response, signs challenges using Dart Ed25519, and verifies returned
licenses with the unchanged Accounts verifier. Its token and signing keys are
fresh ephemeral test fixtures, not production credentials.

Control holds the matching contracts, migration 4 and full server test evidence
in release_evidence/CR1_PHASE_2.md. No production database/RPC, backup, historical
test failure or unrelated existing untracked file was modified. No push.
