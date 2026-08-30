# SEC.013 - Yalla Control Center invariants

1. Yalla Control Center is a separate Yalla-only control-plane application; it is not a hidden route or master password inside the customer desktop client.
2. Client SQLite remains v69 and customer accounting/operational rows are not uploaded or exposed by SEC.013.
3. PostgreSQL server model advances to v8.
4. The canonical sections are Dashboard, Organizations, Subscriptions, Licenses, Devices, Plans, Features, Entitlements, Activations, Renewals, Overrides, Security Events, Audit Logs, and Yalla Admin Users.
5. SEC.013 read models expose only server-side licensing/commercial/control metadata.
6. The Yalla Admin Users read model never exposes a password, password hash, recovery secret, session token, signing key, or other authentication secret.
7. SEC.013 API surface is read-only. The browser shell issues GET requests only.
8. YALLA_SUPER_OWNER authorization and YALLA_BREAK_GLASS privileged mutations are not implemented in SEC.013; they are SEC.014.
9. Authentication, recovery, session lifecycle, session revocation, and immutable audit enforcement are hardened in SEC.015.
10. Production private signing key material remains KMS/HSM/secret-store only and is not present in this repository or patch.
11. Historical accounting data rewrite is NONE.
