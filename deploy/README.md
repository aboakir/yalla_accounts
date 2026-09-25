# Yalla Accounts production build inputs

`production_defines.example.json` is a non-secret template for Flutter `--dart-define-from-file`. Replace every placeholder before a commercial build.

The licensing/control URL must be the exact HTTPS `CONTROL_PUBLIC_ORIGIN` exposed by Yalla Control. `YALLA_LICENSE_TRUSTED_KEY_SHA256` pins the approved Ed25519 signing public key set. Never place private signing keys, database credentials, Supabase Service Role keys, or passwords in this file.

Cloud Auth uses only the Supabase publishable key. Store builds require HTTPS legal/privacy/account-deletion URLs and `YALLA_STORE_DISTRIBUTION=true`.

Example build shape:

`flutter build apk --release --dart-define-from-file=deploy/production_defines.json`

Keep the real `production_defines.json` outside source control or generate it from the approved release secret/configuration system. Phase 12 owns CI/CD automation; Phase 11 only defines the production infrastructure contract.

Before any release build, validate the real file:

`dart run tools/validate_production_defines.dart deploy/production_defines.json`

The validator rejects missing keys, placeholder values, non-HTTPS origins, malformed signing-key pins, service-role/private/database secret material, and a Cloud Auth configuration that is not marked release-ready. A release build must not proceed after validator failure.

## Official Control authority
For V1, `YALLA_LICENSING_BASE_URL` must point to the HTTPS origin of the official PHP Backend/Web Control deployment (`D:\YALLAH_BACKEND`, `public/admin` + `public/api`). Legacy Flutter Yalla Control projects are archive-only and must not be used as a second production authority.
