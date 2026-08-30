# SEC.015 - Control Center Authentication / Recovery / Sessions / Audit Contract

## Authentication boundary

All `/v1/control-center/auth/*` endpoints are licensing-server endpoints. Customer organization identity storage never authenticates a Yalla administrator. Browser JavaScript never receives HttpOnly admin-cookie bytes. The unified native desktop transport may hold opaque Yalla admin session cookies in process memory only; it never persists them or receives password hashes, MFA secret bytes, recovery-code digests, refresh-token digests, or signing secrets.

### Password verification

The authentication service verifies Argon2id PHC hashes and applies a server-side pepper loaded only from KMS/HSM/approved secret storage. Recommended initial deployment floor: Argon2id with at least 64 MiB memory, 3 iterations, parallelism 1, and a unique random salt; production values must be benchmarked and may be strengthened without changing the database contract.

The server returns a generic authentication failure and must not disclose whether the submitted email exists. Per-account and per-IP throttling applies; the canonical policy throttles after 5 failures and locks an enrolled admin credential after 10 failures in the bounded failure window for 30 minutes.

## Enrollment / first YALLA_SUPER_OWNER credential

Existing `yalla_admin_users` identities remain identities only until enrolled. A deployment administrator creates a one-time ENROLLMENT challenge for the already-authorized admin identity. The enrollment secret is delivered out-of-band, persisted only as a digest, expires, and is consumed once. Enrollment sets the first Argon2id password and requires MFA enrollment before the Super Owner obtains a privileged session.

No default username/password is seeded by migrations or source code.

## Login and MFA

- `POST /v1/control-center/auth/login` accepts email + password over TLS.
- A correct password for a role requiring MFA returns `MFA_REQUIRED` and a short-lived challenge id; it does not create a privileged session yet.
- `POST /v1/control-center/auth/mfa/verify` verifies TOTP or WebAuthn and creates the authenticated session.
- `GET /v1/control-center/auth/session` returns safe session metadata and a CSRF token; it never returns access/refresh token bytes.

`YALLA_SUPER_OWNER` and `YALLA_BREAK_GLASS` require MFA.

## Browser session transport

Authenticated browser state is transported using Secure, HttpOnly, SameSite=Strict cookies. Tokens are never placed in URLs, JavaScript localStorage, or JavaScript sessionStorage. PostgreSQL stores only token digests.

Canonical defaults:
- access window: 15 minutes
- idle window: 30 minutes
- absolute session lifetime: 12 hours
- refresh token: rotated on every refresh
- refresh reuse: mark session family COMPROMISED and revoke family

State-changing requests require a server-issued anti-CSRF value in `X-Yalla-CSRF`.

## Session endpoints

- `POST /v1/control-center/auth/refresh`
- `POST /v1/control-center/auth/logout`
- `POST /v1/control-center/auth/logout-all`
- `GET /v1/control-center/auth/sessions`

Session lists expose metadata only: session id, times, status, IP/device descriptors. They never expose token digests or token bytes.

## Step-up reauthentication

`POST /v1/control-center/auth/re-auth` requires current password + MFA while the existing session is active. For `BREAK_GLASS`, the resulting reauth context is tied to the same admin/session and is valid for at most 5 minutes. `POST /v1/control-center/break-glass` must reject requests without a fresh valid reauth context.

## Recovery

- `POST /v1/control-center/auth/recovery/start` always returns the same public response shape, whether or not the email exists.
- Recovery secrets are one-time, expire after the configured window, and are stored only as digests.
- Super Owner recovery requires a valid out-of-band recovery challenge plus a single-use recovery code or an approved equivalent MFA recovery ceremony.
- `POST /v1/control-center/auth/recovery/complete` invalidates the challenge, rotates the credential version, and revokes all prior sessions.

No recovery endpoint returns an existing password, password hash, MFA secret, recovery-code digest, or session token.

## Audit integrity

Privileged/authentication security events are written to `audit_logs` or `yalla_admin_security_events` as appropriate. `audit_logs` and `yalla_audit_chain_seals` reject UPDATE and DELETE. Control Center audit events are canonicalized with RFC8785-JCS, SHA-256 hashed, and appended to the `CONTROL_CENTER_ADMIN` chain in the same server transaction as the event where applicable.

The chain is tamper-evident. Protected backups/external anchor publication remain operational controls outside the client application.

## Unified desktop entry extension (SEC.015 UX completion)

Yalla Accounts uses one executable and one first login screen for both identity realms. The realms remain cryptographically and operationally isolated:

- customer users authenticate against the customer organization identity store;
- Yalla administrative identities authenticate only against `/v1/control-center/auth/*` on the licensing server;
- a successful `YALLA_SUPER_OWNER` / Yalla-admin session routes the same desktop executable into the native Control Center module;
- a successful customer identity routes into the customer accounting application.

The native desktop transport may receive the server's opaque session cookies because it is the HTTP user-agent itself. Those cookie values are process-memory only: they MUST NOT be written to SharedPreferences, FlutterSecureStorage, SQLite, URLs, logs, crash reports, or customer data. Browser JavaScript still never receives HttpOnly cookie bytes.

### Native first-admin enrollment

The unified login screen may expose an administrative enrollment flow only when `YALLA_LICENSING_BASE_URL` is configured. It is not a self-registration endpoint and does not create a Yalla administrator from client authority.

- `POST /v1/control-center/auth/enrollment/start` requires an already-authorized admin email plus a one-time server-issued enrollment secret. The secret is consumed/validated server-side and is never persisted by the desktop client.
- The server returns a bounded `challenge_id` and may return a TOTP provisioning URI for that enrollment ceremony.
- `POST /v1/control-center/auth/enrollment/complete` accepts `challenge_id`, the new password, and MFA proof. It consumes the challenge, stores only the Argon2id credential verifier / MFA server material defined by this contract, and does not return credential or session secret bytes.
- Enrollment never seeds a default password, universal owner password, or customer-client backdoor.

The deployment administrator or protected server bootstrap remains responsible for authorizing the first `yalla_admin_users` identity and issuing the one-time enrollment secret.
