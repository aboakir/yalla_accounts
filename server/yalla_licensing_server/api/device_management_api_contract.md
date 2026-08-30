# SEC.010 device management API contract v1

## Device lifecycle

Canonical statuses: ACTIVE, SUSPENDED, REVOKED, REPLACED.

Allowed lifecycle transitions:
- ACTIVE -> SUSPENDED
- SUSPENDED -> ACTIVE (RESUME / approved REACTIVATION)
- ACTIVE or SUSPENDED -> REVOKED
- ACTIVE or SUSPENDED -> REPLACED

REVOKED and REPLACED are terminal. A revoked/replaced device cannot grant itself
ACTIVE status. New identity/authorized replacement is required.

## Capacity

`MAX_DEVICES` comes only from SEC.003 `yalla_effective_entitlements()`.
ACTIVE and SUSPENDED devices consume a slot. REVOKED and REPLACED do not.
Replacement is slot-neutral only when the old device and new device transition in
the same server transaction.

## Control-plane actions

A device management action has one of:
ADD_DEVICE, REACTIVATE, SUSPEND, RESUME, REVOKE, REPLACE.

Lifecycle: REQUESTED -> APPROVED -> APPLIED, or REQUESTED -> REJECTED/CANCELLED.
Every action requires reason and idempotency key. SEC.013 supplies UI; SEC.014
supplies YALLA_SUPER_OWNER / Break Glass authorization. This contract never
trusts a desktop customer as a control-plane administrator.

ADD_DEVICE / REACTIVATE / REPLACE can issue one-time activation grants whose
plaintext is shown once and whose SHA-256 only is persisted. The client later
uses the SEC.006/010 proof-of-possession activation protocol.

## Revocation and replacement

Revoking a device revokes its active device license(s). Replacing a device marks
the old device REPLACED, links `replaced_by_device_id`, revokes the old active
license, and activates/issues the new device license atomically.
