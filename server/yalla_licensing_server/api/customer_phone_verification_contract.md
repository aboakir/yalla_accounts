# Yalla Accounts — Customer Phone Verification Contract (P02)

## Boundary

Customer phone verification is a server-authoritative ceremony and is separate
from Yalla Control Center administrator MFA.

Endpoints:

- `POST /v1/customer-phone-verification/start`
- `POST /v1/customer-phone-verification/verify`
- `POST /v1/customer-phone-verification/consume`

The Flutter client never generates an OTP, never receives the OTP in a start
response, and never persists OTP or verification-token material to SQLite,
SharedPreferences, FlutterSecureStorage, URLs, or logs.

## Start

Request: `{ "phone": "+970..." }`.

The server normalizes and validates the phone, creates a cryptographically
random six-digit OTP, stores only a salted slow verifier, and sends the code
through the configured SMS delivery adapter.

Canonical windows:

- OTP lifetime: 5 minutes.
- resend minimum: 60 seconds per phone.
- maximum verification attempts: 5.

Production SMS delivery is supplied through the server-side
`YALLA_SMS_WEBHOOK_URL` HTTPS adapter. `YALLA_SMS_WEBHOOK_TOKEN`, when present,
is an environment secret and is never shipped to the client.

The loopback-only SEC.015A development harness may print an OTP diagnostic to
its server console only when no SMS adapter is configured. That diagnostic is
LOCAL DEVELOPMENT ONLY and is never returned over the public OTP API.

## Verify

A correct OTP invalidates its verifier and returns a cryptographically random,
short-lived verification token. The server stores only a salted verifier of
that token.

Verification-token lifetime: 10 minutes.

## Consume

First-owner setup must consume the verification token against the same
normalized phone before local bootstrap continues. Consumption is one-time.
The server clears the token verifier after successful consumption.

## Security invariants

1. OTP plaintext is never persisted server-side.
2. OTP plaintext is never returned by the API.
3. Verification-token plaintext exists only in process/client memory until use.
4. Attempt, expiry, resend, phone-binding, and one-time-consumption checks fail closed.
5. Admin TOTP/WebAuthn factors are not reused for customer verification.
6. Customer SQLite schema/version remains unchanged.
7. Production deployment must configure an HTTPS SMS adapter; a development
   console diagnostic is not a production delivery mechanism.
