# Stage 43 follow-up — Local login remediation

Status: PASS for the tested login remediation; the full identity/licensing/cloud/sync plan is NOT complete.

## Implemented
- Removed the username-only owner/user login from LoginScreen. Credentials go through UserService.authenticateUser; roles come from AppUser, never the entered username.
- CommercialAccessGateService is checked before a session is granted UI access, including PIN/biometric unlock.
- Startup always routes to login/unlock rather than opening the dashboard from a stored session.
- Persisted login requires device PIN setup; existing secure sessions are re-read at unlock so a revoked/changed session is not accepted from cached screen state.
- AuthenticatedRouteGate revalidates the real session and commercial chain and rejects mismatched in-memory identity. Existing per-route restrictions are retained. Required password change is no longer cleared by preview login.
- PIN has a persistent five-attempt, 15-minute lockout using secure storage.
- No schema migration, accounting posting changes, production DB changes, server configuration changes, or device installation performed.

## Verification
- 36 tests passed: login widget scenarios, protected routes, PIN lockout, commercial identity chain, password/session regression and accounting/session regression.
- 3 responsive matrix tests passed: 51 route constructors including LoginScreen at 430x932, 390x844 and 844x390. Existing legacy raw-material load diagnostics remain unrelated.
- dart format completed on the eight changed Dart files.
- flutter analyze run; see .dart_tool/stage43-auth-analyze.log. Repository-wide warnings/info remain; this is not a lint-clean release claim.
- Tests use synthetic/in-memory/disposable data, not the real workshop database.

## Files
- lib/features/auth/screens/login_screen.dart
- lib/features/startup/startup_screen.dart
- lib/features/auth/services/device_unlock_service.dart
- lib/features/auth/widgets/authenticated_route_gate.dart
- test/commercial/stage43_login_flow_test.dart (new behavioral tests)
- test/commercial/p1_002_auth_hardening_test.dart
- test/commercial/stage_02_login_subscription_roles_activation_completion_test.dart
- test/regression/startup_persisted_session_test.dart

## Remaining work and deployment constraints
- Confirm one authoritative licensing server and its pinned key. Codemagic and GitHub iOS currently target different endpoints/keys; no arbitrary choice was made.
- Implement/read-test a data-export/recovery path for valid local owners without usable activation before deploying this stricter login to an existing workshop. Current CommercialAccessGate denies unactivated access. Do not silently install this build over the user's working installation.
- Complete Account/User/Organization mapping and role-route policy in their dedicated stages. Existing non-owner route whitelist remains restrictive.
- Close default-disabled service enforcement and ACTIVATION_REQUIRED DB write semantics separately with bootstrap/recovery tests; those were not changed here.
- Explicitly invalidate/rebind identity after restore and handle device-bound licenses on a new phone.
- Cloud customer auth, production license configuration, sync transport, universal change identity and conflict resolution remain unimplemented/unverified.
- No claim of physical iOS biometric testing or full commercial release readiness. No IPA generated.
## Follow-up batch — owner data export and restore identity (2026-09-09)

Implemented:
- Added an Arabic owner-credential export screen reachable from login without license activation. It uses the existing encrypted backup/share implementation.
- Added a process-local recovery session that permits backup creation/export only. Restore and all other permission checks are denied during this session; financial attribution also rejects it.
- Sessions are cleared after export, including failure. Logout clears local authority even if database revocation fails.
- Successful restore invalidates imported session tokens and device PIN/biometric configuration before committing the restore journal. The encrypted restore screen returns to login; stale UI identity cannot authorize postings.
- Production service authorization is enabled from application startup and is not disabled on logout.
- Non-destructive schema v71 removes only license read-only triggers on backup metadata and audit events. Append-only audit protection and financial read-only triggers remain. A v70-only upgrade avoids replaying unrelated seed writes under an expired license.

Validation:
- 46 tests passed; one legacy-v55 snapshot test skipped because no isolated fixture was supplied.
- Tests cover every role denied export except Owner, recovery permission allowlist, failed credentials, failed backup, session invalidation, expired-license metadata writes, audit immutability, v70 upgrade preserving business rows, login guards, and accounting attribution.
- Backup creation/sharing is injected in the new export service tests; this is NOT a physical iPhone full-file export/restore acceptance claim.
- dart format run. Full flutter analyze run: no compiler errors; repository lint warnings/info remain (see .dart_tool/stage43-export-analyze.log).
- Real workshop database and installed mobile app were not replaced. No IPA built.

Files in this batch:
- lib/features/auth/screens/owner_data_export_screen.dart (new)
- lib/features/auth/services/owner_data_export_service.dart (new)
- lib/features/auth/screens/login_screen.dart
- lib/features/auth/services/auth_session_service.dart
- lib/features/auth/services/authorization_guard.dart
- lib/features/auth/services/permission_service.dart
- lib/features/auth/screens/logout_screen.dart
- lib/main.dart
- lib/core/services/current_user_context.dart
- lib/core/services/backup_service.dart
- lib/features/settings/screens/security_data_screen.dart
- lib/core/services/db/database_constants.dart
- lib/core/services/db/database_migration.dart
- lib/core/services/db/tables/license_runtime_tables.dart
- test/commercial/stage43_owner_export_test.dart (new)
- test/reliability/database_reliability_test.dart
- test/accounting/preview_session_posting_test.dart

Still outstanding before deploying strict login over an existing workshop:
- Physical-device encrypted export/import acceptance, including key portability and share cancellation/retry.
- Confirm authoritative production licensing endpoint and pinned public key (existing CI configurations disagree).
- Complete activation-required financial DB write policy with bootstrap tests; this batch preserves existing policy.
- Full identity/roles, cloud authentication and sync work remain in their dedicated stages; this is not a PASS for the entire release plan.
