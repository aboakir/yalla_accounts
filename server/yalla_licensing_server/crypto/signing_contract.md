# Yalla license signing contract v1

## Wire envelope

A signed license is an envelope with `typ=YALLA-LICENSE`, `alg=EdDSA`, a signing key id (`kid`), the payload object, a lowercase SHA-256 payload hash, and an Ed25519 signature.

## Exact signing bytes

1. Validate the payload against `license_envelope.schema.json` payload rules.
2. Canonicalize the payload using RFC 8785 JSON Canonicalization Scheme (JCS).
3. Encode the canonical JSON as UTF-8 bytes.
4. Compute SHA-256 over those exact bytes and store lowercase hexadecimal as `payload_sha256`.
5. Sign those exact bytes with Ed25519.
6. Encode the 64-byte signature using base64url without `=` padding.

The envelope metadata itself is not signed separately; the payload carries all authorization-bearing facts. `kid` selects the public verification key and must correspond to the server record that produced the signature. `public_key_sha256` is SHA-256 of the raw 32-byte Ed25519 public key. Device public-key hashes use the same raw-key hashing rule for their own algorithm-specific raw public bytes.

## Required binding

The payload binds the license to the organization, subscription, license, device, installation, and SHA-256 of the device public key. It also binds validity timestamps and entitlement revision.

## Secret boundary

This repository contains no production private signing key. Signing implementations must receive signing capability from a server-only KMS, HSM, or secret-store adapter referenced by `key_provider` + `key_provider_reference`. The reference is not the key material.

## Rotation

Only one key is ACTIVE for issuance. Rotation stages a new key, activates it, and retires the old key. Retired public keys remain available for historical verification. Revocation is distinct from retirement and marks a key untrusted when the client/server learns the revocation state. The public verification-key distribution format is `verification_keyset.schema.json`; it contains public material only.


## SEC.011 operational lifecycle extension

`operational_status` is an optional authorization-bearing payload field with
values `ACTIVE`, `GRACE`, `SUSPENDED`, `EXPIRED`, `REVOKED`, or `CANCELLED`.
Old SEC.006/SEC.010 payloads without the field are interpreted as `ACTIVE`
subject to their signed `expires_at`.

A lifecycle validation or renewal response MUST return a newly signed license
envelope. The desktop never accepts an unsigned suspension/renewal decision.
`grace_until`, when present, describes subscription lifecycle grace.
SEC.012 additionally requires every newly minted license to sign concrete
`validation_required_at` and `validation_grace_until` timestamps. The client
may never extend these timestamps locally.

Renewal must never edit an already signed payload in place. The server first
updates the subscription source-of-truth, then mints a fresh signed license
whose entitlement revision and timestamps reflect the new state.
