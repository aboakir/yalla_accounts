# Yallah Accounts — Commercial RC, 24 September 2026

Version: 1.0.3+22. Database schema: 85.
Canonical RC source: F:\YALLAH_ACCOUNTS_COMMERCIAL_RC_20260924.
Branch: release/commercial-rc-20260924.
Code gate commit: 747e1fe2012be650e8ad5fef8d74dfc1e301f15c.

## Scope
This RC adds activity-aware experience profiles, Simple/Advanced modes, first-use onboarding, a real notification center, profile-aware search/navigation, and the commercial dashboard work while keeping insurance hidden in pilot builds by default.
No Yalla Control source or production customer database was modified.

## Validation completed
- flutter analyze --no-pub: 0 issues on the final RC code.
- Final focused RC gate: 35/35 passed.
- Auth/license commercial gate: 79/79 passed.
- Stage 15–18 gate: 97 passed, 2 diagnostic skips requiring an external DB path.
- Stage 12–14 responsive/mobile gate: 55/55 passed.
- Stage 11 backup/restore gate: 49 passed, 1 intentional skip.
- Stage 9–10 financial/integrity gate: 64/64 passed.
- Android API 36 emulator: install and launch passed with no fatal exception.
- Windows release build: passed.

## Production release boundaries
Android production signing is ready using the pre-existing private keystore outside Git; android/key.properties was recovered locally without replacing the key.
The remaining Android commercial-build blocker is the verified production licensing HTTPS origin and approved public signing-key SHA; Supabase URL/publishable key were recovered from the live Yalla Accounts Supabase project.
production_defines.json and production secrets remain intentionally absent from source control.
iOS production output requires Apple signing/Codemagic; no unsigned result is to be represented as a production IPA.
Owner-local access builds remain separate from customer commercial builds.

## Release truth
The source constant kTemporaryAuthBypass is false.
Insurance code/data remain present for later activation, but pilot UI is hidden unless YALLA_INSURANCE_PILOT_VISIBLE is explicitly enabled.
The authoritative evidence file is release/COMMERCIAL_RC_ACCEPTANCE_20260924.json.
