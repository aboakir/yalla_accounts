# SEC.005 Device Identity Contract

- Client creates a local UUID `installation_id` and UUID `device_id`.
- Client creates an Ed25519 keypair. Only the public key crosses the server boundary.
- Private seed is never stored in SQLite, logs, registration payloads, or server tables.
- `fingerprint_hash` is a SHA-256 risk signal only; it is never authoritative authentication.
- Server device table from SEC.002 remains the canonical remote device record.
- SEC.006 must require proof-of-possession by signing a server challenge before activation.
- A BOUND identity with missing/mismatched private key must require reactivation; silent rotation is forbidden.
- DPAPI/CNG/TPM and stronger anti-cloning hardening remain reserved for SEC.016.
