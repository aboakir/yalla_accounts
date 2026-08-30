# SEC.015C1 — Lifecycle, Billing & Device Administration Contract

## Boundary

SEC.015C1 converts the native Yalla Control Center from a mostly read-oriented
administrative console into an operational control plane. All lifecycle,
billing and device mutations cross the authenticated `/v1/control-center`
server boundary and require the existing MFA session + CSRF protection.

The customer SQLite database is not modified by SEC.015C1. Accounting and
operational customer rows remain local. The licensing/control server remains
the server-side source of truth for commercial lifecycle state.

## Subscription operations

The Control Center exposes direct operations for:

- Activate.
- Suspend / Freeze.
- Reactivate.
- Extend trial.
- Extend current period.
- Mark Paid.
- Mark Unpaid.
- Renew.
- Restore a cancelled subscription.
- Display remaining period from the server-side expiry timestamp.

The local development harness persists these values in its own server state.
It never projects an administrative button press directly into customer SQLite.

## Billing projection

`billing_status` is an operational commercial projection used by SEC.015C1
with values `TRIAL`, `PAID`, or `UNPAID`. Changing billing status does not
rewrite historical accounting data and does not by itself create an accounting
receipt.

## Device operations

The Devices section lists server-known devices and exposes Activate/Deactivate
for non-terminal device states. Deactivate maps to `SUSPENDED`; Activate maps
to `ACTIVE`. `REVOKED` and `REPLACED` remain terminal and cannot be reactivated
by the Control Center.

Device creation/cryptographic registration remains governed by the existing
SEC.006/SEC.010 activation and proof-of-possession contracts.

## Closure proof

The gated integration self-test must prove the lifecycle sequence:

Trial → Active → Extended → Paid/Unpaid → Frozen → Reactivated

It must also prove renewal, remaining-period projection, device deactivation
and device reactivation against isolated local server state.

## Database policy

- Client DB migration: NONE.
- Client DB reset: NO.
- Customer SQLite data mutation by Control Center: NONE.
- Existing SEC.015 authentication/session/security contracts: PRESERVED.
