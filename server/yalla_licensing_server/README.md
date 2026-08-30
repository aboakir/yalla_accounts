# Yalla Licensing Server

Canonical server-side commercial and licensing model for Yalla Accounts.

## Implemented stages

- SEC.002: core licensing server data model.
- SEC.003: feature catalog, typed plan entitlements, subscription overrides, deterministic evaluation, and entitlement revisions.
- SEC.004: cryptographic license authority model, Ed25519/JCS signing contract, signing-key lifecycle, signed-license persistence contract, and public verification-keyset contract.
- SEC.005: client installation/device cryptographic identity contract.
- SEC.006: first-online-activation grant/challenge model, HTTP API contract, device proof-of-possession, signed license delivery, and client activation gate.
- SEC.010: server-authoritative device lifecycle, MAX_DEVICES capacity accounting, add/reactivate/suspend/resume/revoke/replace contracts, and replacement-safe activation grants.

## Current database model version

10

## Cryptographic boundary

The server is the signing authority. Production private signing-key bytes never belong in this repository, a ZIP patch, PostgreSQL, client SQLite, or the desktop application. PostgreSQL stores the public verification key plus an opaque reference to a server-side KMS/HSM/secret-store key.

SEC.004 intentionally does not generate a production private key on the developer/client workstation. Production key provisioning happens only inside the deployed server secret boundary.

## Client/server boundary

The desktop client is on database v69 after SEC.012. SEC.013 does not change the client SQLite schema. Accounting and operational data stay local in phase one. The licensing server and Yalla Control Center remain the commercial/control source of truth.

## Not implemented yet

- SEC.016: client anti-tamper/device protection hardening.


## SEC.006 client build trust anchors

Commercial client builds must define both values at build time:

- `YALLA_LICENSING_BASE_URL=https://...`
- `YALLA_LICENSE_TRUSTED_KEY_SHA256=<sha256 of approved Ed25519 public key>`

Multiple approved key hashes may be comma-separated during a controlled key rotation.
The client refuses first activation if the HTTPS endpoint or trusted signing-key hash is absent.


## SEC.011 - Expiry / Read Only / Renewal / Suspension

Server model v6 adds a proof-of-possession lifecycle refresh protocol and
suspension-aware operational-state calculation. Renewal updates the subscription
source-of-truth and requires minting a fresh signed license; existing signed
payload bytes are never edited.

## SEC.012 - Periodic Online Validation + Grace Period

Server model v7 adds a default 30-day validation cadence and 7-day offline grace window. New signed licenses carry concrete validation deadlines; clients fail closed to READ ONLY after grace while preserving data access/export/backup.


## SEC.013 - Yalla Control Center

Server model v8 adds the independent Yalla Control Center server control plane.
The control plane remains separate from customer SQLite and exposes no SQLite accounting
data. SEC.015 UX completion also exposes a native Control Center presentation inside the
same yalla_accounts desktop executable after Yalla-admin server authentication + MFA. The Control Center contains Dashboard, Organizations, Subscriptions,
Licenses, Devices, Plans, Features, Entitlements, Activations, Renewals,
Overrides, Security Events, Audit Logs, and Yalla Admin Users.

SEC.013 established the independent read/control-plane shell.

## SEC.014 - YALLA_SUPER_OWNER + Break Glass

Server model v9 adds Yalla administrative RBAC, the YALLA_SUPER_OWNER role, scoped short-lived YALLA_BREAK_GLASS authorization, a canonical privileged-action catalog, one-time super-owner ownership binding, and license-issuance authorization requests. No master password or customer-password visibility is introduced. Session/MFA/recovery and broader tamper-evident audit hardening remain SEC.015.

## SEC.015 - Security / Recovery / Sessions / Audit

Server model v10 adds Control Center credential enrollment, Argon2id password-verification storage, mandatory MFA for Super Owner / Break Glass, Secure+HttpOnly+SameSite session cookies, CSRF, rotating refresh-token digests with reuse detection, recovery challenges/codes, 5-minute MFA step-up for Break Glass, session revocation, and immutable hash-chain audit seals. No browser bearer token is stored in localStorage/sessionStorage.


## SEC.015 unified login gateway

The first desktop screen is shared by customer users and Yalla administrators. Customer
identities continue to authenticate in the organization realm. Yalla administrator emails
authenticate only against `/v1/control-center/auth/*`; successful Yalla admin sessions route
the same executable to the native Control Center module. Native admin session cookies are
process-memory only and are never persisted in customer storage. First Yalla administrator
enrollment requires a one-time server-issued enrollment secret and MFA; no default owner
password or customer-client backdoor is shipped.
