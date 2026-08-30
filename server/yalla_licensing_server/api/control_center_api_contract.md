# Yalla Control Center API Contract - SEC.015

## Boundary

`/v1/control-center` remains an independent licensing-server control plane. It never reads the customer accounting SQLite database and never functions as a customer-client backdoor.

SEC.015 replaces manually supplied browser bearer tokens with server authentication, MFA, Secure/HttpOnly/SameSite session cookies, CSRF protection, recovery, session rotation/revocation, fresh reauthentication, and tamper-evident administrative audit sealing.

## Authentication routes

- `POST /v1/control-center/auth/login`
- `POST /v1/control-center/auth/mfa/verify`
- `GET /v1/control-center/auth/session`
- `POST /v1/control-center/auth/refresh`
- `POST /v1/control-center/auth/logout`
- `POST /v1/control-center/auth/logout-all`
- `GET /v1/control-center/auth/sessions`
- `POST /v1/control-center/auth/re-auth`
- `POST /v1/control-center/auth/recovery/start`
- `POST /v1/control-center/auth/recovery/complete`

No auth route returns password hashes, TOTP secret bytes, recovery-code digests, cookie/token bytes, private signing keys, or customer credentials.

## Read routes

All prior Control Center read routes remain. SEC.015 adds safe metadata views for admin sessions and admin security events.

## Mutations

The SEC.014 typed action and break-glass endpoints remain. Every state-changing request requires an authenticated MFA-capable session and `X-Yalla-CSRF`. Emergency Break Glass additionally requires an unexpired same-session MFA reauthentication context no older than the configured 5-minute policy.

The server derives actor/session identity from authenticated server state. Browser-supplied actor ids are never authoritative.

## Unified native desktop presentation (SEC.015 UX completion)

The Control Center **server control plane remains separate from customer SQLite**, but its presentation is also available as a native module inside the same `yalla_accounts` desktop executable. This supersedes the earlier assumption that the operator must open a separate application/browser to reach the Control Center.

The first screen is shared. The desktop gateway determines the realm from successful authentication, not from a master password:

- Yalla admin email + server authentication + required MFA -> native Yalla Control Center;
- customer organization user -> customer application dashboard.

The native module uses the same `/v1/control-center` read routes, typed `/actions`, Break Glass, session, recovery, and audit contracts. It never reads or exposes customer accounting SQLite through the Control Center server boundary.

Native admin session cookies remain in process memory only and are cleared on logout/application exit. No Yalla admin session secret is persisted into customer storage.

## SEC.015C1 operational lifecycle extension

The native module now exposes direct lifecycle controls instead of requiring
operators to manually compose generic action codes for routine work.

Supported operational actions include:

- `SUBSCRIPTION.ACTIVATE`
- `SUBSCRIPTION.EXTEND` / `SUBSCRIPTION.TRIAL_EXTEND`
- `SUBSCRIPTION.MARK_PAID` / `SUBSCRIPTION.MARK_UNPAID`
- `SUBSCRIPTION.SUSPEND` / `SUBSCRIPTION.REACTIVATE`
- `SUBSCRIPTION.RENEW` / `SUBSCRIPTION.RESTORE`
- `DEVICE.DEACTIVATE` / `DEVICE.ACTIVATE`
- organization activate/suspend/resume

The server returns the applied before/after state and the subscriptions view
returns server-derived remaining-period fields. A request is never reported as
applied merely because the UI accepted it; unsupported actions are rejected.

This extension does not expose or mutate customer accounting SQLite.

