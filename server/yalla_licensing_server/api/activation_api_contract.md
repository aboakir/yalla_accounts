# SEC.006/SEC.010 activation API contract v2

## Authority boundary

The API is server-authoritative. The activation code identifies a hashed one-time
server grant. The client MUST NOT choose or override the activation kind. The
server infers `FIRST`, `ADD_DEVICE`, `REACTIVATION`, `DEVICE_REPLACEMENT`, or
`LICENSE_REFRESH` from the persisted grant after hashing the submitted code.
Production endpoints MUST use HTTPS.

## 1. POST /v1/activations/challenge

Request API version is 2. The client sends the activation code, request
idempotency UUID, and SEC.005 device registration payload. It sends no trusted
`activation_kind` field.

The server atomically verifies the grant, organization, subscription, device
binding and active suspensions. New SEC.010-managed grants are persisted with
`management_protocol_version = 2`; historical v1 grants remain readable for
upgrade compatibility but do not gain new management authority. It then applies grant-specific rules:

- FIRST: ownerless first installation; normal MAX_DEVICES capacity check.
- ADD_DEVICE: management action must be APPROVED; MAX_DEVICES capacity check.
- REACTIVATION: grant must target the same known SUSPENDED device.
- DEVICE_REPLACEMENT: management action must be APPROVED and bind the old device;
  capacity is checked excluding the old device because replacement is slot-neutral.
- LICENSE_REFRESH: same active device identity; no extra device slot.

`ACTIVE` and `SUSPENDED` devices both consume MAX_DEVICES. `REVOKED` and
`REPLACED` devices do not. A terminal device is never silently reactivated.

The server creates a single-use short-lived challenge bound to the grant,
organization, subscription, installation, device, public key and idempotency key.
Recommended challenge lifetime remains 5 minutes.

## 2. POST /v1/activations/complete

Request API version is 2. The client signs the exact challenge bytes with its
SEC.005 Ed25519 private key. The server verifies proof-of-possession and executes
one transaction appropriate to the authoritative grant kind.

For ADD_DEVICE it creates/activates the new device and issues a signed license.
For REACTIVATION it returns the targeted SUSPENDED device to ACTIVE after proof.
For DEVICE_REPLACEMENT it activates the new device, marks the old device
REPLACED, revokes the old active license, links the replacement, consumes the
grant/action and issues the new signed license atomically.

Idempotent retries return the same completed result; they never consume a second
grant or create a duplicate device/license.

## Device-management control plane

Creation/approval of device-management actions is defined by SEC.010. SEC.013
will provide Yalla Control Center UI and SEC.014 will enforce YALLA_SUPER_OWNER /
Break Glass authorization. Until those stages exist, no customer client is a
trusted control-plane actor.

## Secrets

- Production signing private key: KMS/HSM/secret store only.
- Device private key: client secure storage only.
- Activation code plaintext: never persisted server-side or client-side.
- MAX_DEVICES: resolved from SEC.003 effective signed/server entitlements only.
