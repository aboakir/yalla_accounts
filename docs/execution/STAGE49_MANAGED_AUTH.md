# Stage 49 — Managed identity implementation; live acceptance pending

## Status
Code implemented under the current explicit Stage47–51 authorization. Cloud identity remains **hidden** in ordinary builds. Live acceptance is **FAIL / pending configuration**, not a claimed completed cloud deployment.

## Implemented
- Supabase official Flutter SDK 2.17.2; lazy initialization only after choosing cloud login. Local password/PIN and offline startup never wait for the provider.
- Arabic RTL sign-in, sign-up, reset email and recovered-password form. Google and Apple OAuth share an explicit disabled-by-default flag.
- Android/iOS `yallaaccounts://auth/callback` and `/recovery` callbacks, PKCE only, explicit initial-link + running-link handling, exact callback allowlist. Cloud identity is accepted only after successful code exchange and a fresh server `getUser` response.
- Secure session and PKCE storage, namespaced by issuer, with mandatory write/read-back verification. SDK logging is disabled. No password, refresh token or provider secret is saved in SQLite.
- Immutable issuer+subject -> existing person/user/workshop binding after re-entering the local password. Email matching, remote roles and stale session claims cannot grant workshop access. Binding and audit commit atomically; no delete, replace or reassignment path exists.
- The existing canonical commercial gate remains mandatory; cloud identity does not change subscription rights or financial storage. Mandatory local password changes must be completed locally before cloud access. Persistent local login still requires the existing PIN setup/consent flow; offline password/PIN remains available when cloud verification cannot reach the network.
- Signup creates no local owner, license or workshop. An unlinked user is directed to existing local setup/login, then settings account linking.

## Configuration needed before live PASS
1. A Supabase project URL and **public `sb_publishable_...` key**. Never put secret/service-role keys in the app.
2. Configure email confirmations, SMTP/reset, and exact redirect allowlist: `yallaaccounts://auth/callback`, `yallaaccounts://auth/recovery`.
3. Configure Google and Apple in the provider console. Enable Apple alongside Google for iOS. Verify actual native return/cancel/cold-start/recovery behavior on target devices.
4. Build with `YALLA_SUPABASE_URL` and `YALLA_SUPABASE_PUBLISHABLE_KEY`; set `YALLA_CLOUD_AUTH_RELEASE_READY=true` only for the controlled validation build, and leave it false for ordinary commercial builds until accepted. `YALLA_CLOUD_OAUTH_ENABLED=true` only after both social providers are ready.
5. Verify email/password, reset, Google/Apple, account binding, logout, restart and offline PIN on the licensed workshop. Cloud data tables/RLS are not used for financial data.

## Files
- `lib/features/cloud_auth/cloud_auth_config.dart`
- `lib/features/cloud_auth/cloud_secure_storage.dart`
- `lib/features/cloud_auth/supabase_identity_provider.dart`
- `lib/features/cloud_auth/cloud_identity_tables.dart`
- `lib/features/cloud_auth/cloud_auth_service.dart`
- `lib/features/cloud_auth/cloud_auth_screen.dart`
- `lib/features/auth/screens/login_screen.dart`
- `test/cloud_auth/cloud_auth_test.dart`
- `pubspec.yaml`, `pubspec.lock`, generated desktop plugin registration files
- `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`
- Parent integration: additive v74 migration and settings tile. Existing authorization route gate unchanged.

## Verification
Targeted tests use in-memory SQLite only, with every Flutter process also receiving a unique isolated `YALLA_ACCOUNTS_DB_DIR`; no real workshop database is opened. Tests cover configuration hidden-by-default, callback restrictions, secure storage/PKCE failures, no email-based linking, local credential requirement, audited idempotent link, cross-account/issuer rejection, fresh verification offline failure, disabled/cross-workshop users, canonical role reread, commercial denial, immutable bindings and audit rollback.

Final isolated run: **17/17 passed**, including immutable binding and mandatory-password-change denial. An intermediate failed immutable-binding test exposed a missing trigger; the trigger was added and the complete suite passed. `dart format` completed for all owned Dart files. Root aggregate `flutter analyze` is the authoritative final analyzer result; initial targeted analyzer had no errors and only style/dependency infos subsequently addressed. Actual cloud/provider/native acceptance cannot be verified without the project and device setup above.

Official references: https://supabase.com/docs/guides/auth/social-login/auth-google ; https://supabase.com/docs/guides/auth/social-login/auth-apple ; https://supabase.com/docs/guides/getting-started/api-keys ; https://supabase.com/docs/reference/dart/auth-signinwithoauth
