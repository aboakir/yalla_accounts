# CR1 Phase 3 — Accounts authenticated licensing wiring

Base: 59737bc740dd6f9509a89cd594c11b9c757509f4.
Branch: commercial/CR1-phase-03. Date: 2026-09-15.

Production activation screen and app-root periodic validation use Riverpod
commercial_licensing_providers.dart. Both HTTP transports obtain a freshly
validated access token from the existing SupabaseIdentityProvider, not a local
customer ID. The provider validates getUser over the network, refreshes expired
sessions, rejects missing/recovery/changed sessions and returns no raw SDK errors.
Recovery denial is securely persisted before recovery exchange and survives
provider recreation. Current token expiry must be known and valid.

Both challenge and complete carry X-Yalla-Installation-Id from the captured
DeviceIdentity. This header is an untrusted target, checked by Control against
proof and persisted binding. Ed25519 proofs, V2 JSON bodies and the existing
license_envelope_verifier.dart remain unchanged.

The production server implementation and Migration 5 live in the matching Control
Phase-3 commit. Real commercial mappings are intentionally created in Phase 4,
not inferred from email and not seeded during this phase.

## Verification

Set YALLA_CR1_CONTROL_ROOT=D:/yalla_control_cr1_phase3/control_server, after npm ci
there. Run flutter test --no-pub with:
- test/cloud_auth/cloud_auth_test.dart
- test/cloud_auth/cr1_phase3_identity_test.dart
- test/commercial/cr1_v2_http_contract_test.dart
- test/commercial/sec_006_activation_flow_test.dart
- test/commercial/sec_008_regression_activation_flow_test.dart
- test/commercial/sec_011_lifecycle_contract_test.dart
- test/commercial/sec_012_periodic_validation_contract_test.dart

Targeted suite and final rerun: 29 PASS, 0 failed, 0 skipped.
All eight modified/new Dart files: analyzer PASS, no issues.
HTTP 1.6.0 is an explicit dev dependency for SDK boundary tests; its locked
version did not change. Tests are isolated, not production Auth acceptance.

No production Supabase access/mutation, RPC removal, backup deletion, reset,
push or Phase 4. Pre-existing untracked backups/editor/output files preserved.
