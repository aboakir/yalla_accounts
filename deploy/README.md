# Yalla Accounts production build inputs

`production_defines.example.json` is a non-secret template for Flutter `--dart-define-from-file`. Replace every placeholder before a commercial build.

For production on `yallah.ps`, both `YALLAH_COMMERCIAL_BACKEND_URL` and `YALLA_LICENSING_BASE_URL` must resolve to the same PHP API origin: `https://api.yallah.ps`. The legacy `YALLA_LICENSE_TRUSTED_KEY_SHA256` is optional and is used only by the older signed-license authority when that PHP commercial backend is not enabled. Never place private signing keys, database credentials, Supabase Service Role keys, or passwords in this file.

Cloud Auth uses only the Supabase publishable key. Store builds require HTTPS legal/privacy/account-deletion URLs and `YALLA_STORE_DISTRIBUTION=true`.

Example build shape:

`flutter build apk --release --dart-define-from-file=deploy/production_defines.json`

Keep the real `production_defines.json` outside source control or generate it from the approved release secret/configuration system. Phase 12 owns CI/CD automation; Phase 11 only defines the production infrastructure contract.

Before any release build, validate the real file:

`dart run tools/validate_production_defines.dart deploy/production_defines.json`

The validator rejects missing keys, placeholder values, non-HTTPS origins, malformed signing-key pins, service-role/private/database secret material, and a Cloud Auth configuration that is not marked release-ready. A release build must not proceed after validator failure.

## Official Control authority
For V1, the official PHP backend/API origin is `https://api.yallah.ps`. Flutter Web is intended for `https://app.yallah.ps`, while the PHP Control is intended for `https://control.yallah.ps`. Both Flutter backend URL defines must use the API origin. Legacy Flutter Yalla Control projects are archive-only and must not be used as a second production authority.
