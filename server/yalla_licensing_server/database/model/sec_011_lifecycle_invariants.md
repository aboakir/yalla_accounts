# SEC.011 lifecycle invariants

1. Customer accounting data is never deleted on expiry or suspension.
2. Expired/suspended/revoked authorization becomes READ ONLY.
3. View/report/print/export/backup remain available.
4. Operational writes are blocked at the database boundary.
5. Authentication/recovery/license-refresh technical writes remain available.
6. A desktop cannot self-declare subscription state.
7. Lifecycle authorization is accepted only from a Yalla-signed envelope.
8. Renewal produces a new signed license; old signed bytes are immutable.
9. Client SQLite is not the authority for subscription status or expiry.
10. Periodic validation cadence and grace-window enforcement are layered by SEC.012 on top of this lifecycle protocol.
