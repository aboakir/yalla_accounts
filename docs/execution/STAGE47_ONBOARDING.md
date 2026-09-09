# Stage 47 — Workshop onboarding

Implemented an Arabic setup path through the existing, verified activation and owner-bootstrap services.

- `AppRoutes.register` must point to `WorkshopOnboardingScreen`. It detects an existing workshop, offers its login, or requires a usable device-bound license before new owner creation.
- The existing activation challenge, device proof, signature verification and activation receipt are retained. Activation routes existing workshops back to login and new installations to onboarding.
- Account registration retains the server SMS challenge, verification and single-use consumption. Name, city and phone are required; logo is optional and copied through `WorkshopLogoService` to portable application storage before bootstrap.
- The current plan is displayed from signed entitlements, including user/device limits, operational status and expiry. The app does not invent plan names, prices or upgrades.
- Currency selection uses `CommercialSettingsService`, preserving country/tax configuration and its prohibition on changing the currency after financial transactions. There is no existing fiscal-year-start model or service, so no unused fiscal-year control was introduced.
- First-owner bootstrap creates a pending onboarding record in the same transaction via `trg_owner_onboarding_pending`. Existing completed workshops are not enrolled during migration. This requires `WorkshopOnboardingTables.ensure(db)` after the owner-bootstrap tables in database creation/upgrades.
- The recovery code is shown before attempting PIN setup. A PIN failure or cancellation does not repeat bootstrap or consume SMS proof again. After a restart, password/PIN authentication plus the commercial gate resume the pending owner setup before creating a new session.
- PIN setup includes confirmation, Arabic-digit normalization, read-back verification, retry and explicit cancellation. Leaving bootstrap during its transaction is blocked. No PIN, password, recovery code or license grant is stored in the progress table.
- Backup is suggested with two explicit choices: open the existing Security and Data screen, or defer and enter the dashboard. This choice is not represented as a completed backup.
- Finalization repeats the canonical owner/commercial checks. Denial creates no session. Read-only subscription access remains read-only and skips currency writes. Failed session/progress persistence leaves onboarding pending and clears the attempted session.

## Verification

`test/commercial/stage47_onboarding_test.dart` covers plan eligibility, atomic progress rollback/restart, existing-workshop routing, activation rejection/retry, PIN save failure/cancel on 390px and 1280px surfaces, both backup choices, commercial revocation between steps, expired read-only completion, non-owner denial, session/progress failures, currency preservation/financial-history lock, authenticated login resume, and the complete owner/SMS/workshop/PIN retry path.

The real activation service is exercised by the existing `sec_006_activation_flow_test.dart` cryptographic fixtures. The onboarding UI tests substitute the transport/service boundary; they do not claim a live server activation or real SMS delivery. Live first-install acceptance still requires a configured licensing endpoint, trusted verification key and an issued activation code; backup creation itself runs only when the user chooses it in Security and Data.

Final local verification: all 58 tests passed across `stage47_onboarding_test.dart`, `stage43_login_flow_test.dart`, `sec_006_activation_flow_test.dart`, `stage44_45_identity_offline_test.dart`, and `stage46_subscription_access_test.dart` (2m38s). Targeted Flutter analysis of all Stage 47 source files and its tests reported no issues. `git diff --check` passed for the modified pre-existing screens. No real workshop database, installation or deployment was changed.
