# Yalla Control Center

Yalla's administrative control plane remains server-side and independent from every customer's accounting SQLite database.

## SEC.015 unified desktop entry

The Control Center now has two presentation surfaces backed by the same server contracts:

1. the hardened web operator UI; and
2. a native Control Center module inside the same `yalla_accounts` desktop executable used by customers.

The desktop application starts on one login screen. A Yalla administrative email is authenticated only by the licensing server; after password + required MFA the executable routes to the native Control Center. Customer owner/employee identities route to the customer application. There is no owner button, universal password, or customer-database admin row for Yalla staff.

The native desktop HTTP session is process-memory only. Yalla admin cookies/tokens are never written to SharedPreferences, FlutterSecureStorage, customer SQLite, URLs, or logs.

## Security posture

- Argon2id credential verification on the server
- MFA mandatory for `YALLA_SUPER_OWNER` and `YALLA_BREAK_GLASS`
- bounded server sessions, refresh rotation and reuse detection
- CSRF enforcement for state-changing requests
- login throttling / lockout
- recovery challenges plus single-use recovery codes
- 5-minute MFA step-up before Break Glass
- immutable audit logs plus RFC8785-JCS / SHA-256 audit-chain seals
- no customer password visibility
- no private signing-key exposure
- no master password or customer-client backdoor

## First Yalla administrator enrollment

The desktop screen may start enrollment only with a one-time secret issued by protected server/deployment administration for an already-authorized Yalla admin identity. The operator chooses the password and completes MFA. No default credentials are shipped in source or migrations.
