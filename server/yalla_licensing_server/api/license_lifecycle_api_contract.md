# SEC.011 License Lifecycle API Contract

## Purpose

Provides explicit online license validation and renewal without waiting for the
periodic scheduler that will be added in SEC.012.

Every lifecycle decision that changes desktop authorization is returned as a
normal Yalla Ed25519 signed license envelope. HTTPS alone is not treated as the
authorization source.

## POST /v1/license-lifecycle/challenge

Request:

- `api_version = 1`
- `action = VALIDATE | RENEW`
- `license_id`
- `subscription_id`
- current device registration payload

Server requirements:

1. organization/subscription/license/device binding must match;
2. terminal device states are rejected;
3. `RENEW` requires an eligible renewal workflow;
4. challenge bytes are random, short-lived and one-time;
5. challenge hash, not raw proof secrets, is persisted.

Response:

- `challenge_id`
- `proof_bytes`
- `expires_at`

## POST /v1/license-lifecycle/complete

Request:

- `api_version = 1`
- `challenge_id`
- same `action`
- `device_id`
- Ed25519 device proof signature

Server verifies proof-of-possession and computes
`yalla_effective_license_operational_state(...)`.

Response:

- `lifecycle_event_id`
- `server_time`
- `license_envelope`
- `verification_keyset`

The signed payload SHOULD include `operational_status`. A missing field is
legacy-compatible and means ACTIVE subject to signed validity timestamps.

## Renewal

An approved renewal is applied through the server-side renewal transaction.
The old signed license is never edited. A new signed license is minted after
the subscription expiry/revision update.

## Suspension / expiry

`SUSPENDED`, `EXPIRED`, `REVOKED`, and `CANCELLED` produce a signed lifecycle
payload that the client projects into READ ONLY. Read-only mode does not delete,
rewrite, or hide customer data.

## Client permissions in READ ONLY

Allowed:

- login and authentication metadata;
- viewing/searching data;
- reports;
- printing;
- export;
- backup;
- online lifecycle validation/renewal.

Blocked:

- new repair;
- invoice creation/post/reversal;
- receipt/payment/voucher creation or mutation;
- GL posting/reversal/manual financial mutation;
- purchase/inventory/payroll operational mutation;
- business settings mutation;
- new user creation or role/status/workshop mutation.

Periodic validation cadence and signed offline-grace scheduling are implemented by SEC.012 and reuse this VALIDATE flow.
