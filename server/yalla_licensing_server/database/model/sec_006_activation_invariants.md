# SEC.006 activation invariants

1. A plaintext activation grant is displayed/transmitted only as needed; PostgreSQL stores only `code_sha256`.
2. A grant is bound to exactly one organization and subscription and has an explicit expiry/use limit.
3. A challenge freezes organization, subscription, device, installation, public key and idempotency context.
4. The client signs the exact server-provided proof bytes with its SEC.005 Ed25519 private key.
5. A completed challenge is single-use; idempotent retries return the same completed activation result rather than issue a duplicate license.
6. The server resolves MAX_DEVICES and all other entitlements from SEC.003; the client never authorizes itself.
7. An ACTIVE license is produced only through the SEC.004 signing authority and KMS/HSM/secret-store boundary.
8. The client accepts a license only when its Ed25519 signature validates and the signing public-key SHA-256 is pinned by the client build.
9. The signed payload must bind organization, subscription, license, device, installation and device-public-key hash.
10. First Owner creation on an ownerless installation is denied until the verified activation receipt is committed locally.
11. SEC.006 does not retroactively block databases that already contain users; expiry/read-only enforcement is SEC.011.
12. Client DB migration v64 -> v65 performs no historical accounting rewrite.
