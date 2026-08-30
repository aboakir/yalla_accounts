# Yalla Accounts Stage 04 — Subscription Lifecycle & Entitlements

## Authority

The Yalla Licensing Server is the commercial source of truth for subscription lifecycle, billing state, plans and entitlements. Customer SQLite is not authoritative for trial, paid status, subscription expiry, plan assignment or entitlement values.

## Signed client projection

The desktop client accepts commercial state only through a cryptographically authentic `VerifiedLicense` bound to the organization, device and installation. The signed license carries:

- `subscription_id`
- `operational_status`
- `expires_at`
- `entitlement_revision`
- effective `entitlements`
- periodic validation window

The writable lifecycle states are `ACTIVE` and `GRACE` while the signed expiry and validation grace windows remain current. `SUSPENDED`, `EXPIRED`, `REVOKED` and `CANCELLED` are read-only states. Customer accounting data is never deleted because of lifecycle state.

## Entitlement gate

Stage 04 validates the signed commercial core entitlements fail-closed:

- `ACCOUNTING_CORE` must be boolean `true`.
- `MAX_USERS` must be an integer >= 1.
- `MAX_DEVICES` must be an integer >= 1.
- Reserved boolean feature entitlements must be boolean when present.
- Missing or malformed required entitlement data denies commercial access.

Feature-specific enforcement can consume the same signed policy. Stage 05 remains responsible for full device activation and license enforcement semantics.

## Legacy local authority

Legacy local trial/subscription paths are compatibility shims only and fail closed. They cannot:

- create a local trial;
- create/update/delete a customer-side subscription as authority;
- read local plans to decide access;
- use `freeTrialEnd`, `subscriptionEndDate`, `paymentStatus`, SharedPreferences activation flags or a local activation code to bypass the signed commercial gate.

The subscription UI reads signed license state or directs the user to canonical activation. Administrative lifecycle mutations remain server-side through Yalla Control Center.

## Database

Customer database migration: **NO**.

Customer database reset: **NO**.

The customer SQLite byte hash must remain unchanged during the Stage 04 patch gate.
