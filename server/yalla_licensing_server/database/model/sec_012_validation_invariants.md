# SEC.012 Periodic Validation Invariants

1. The default server policy is 30 days between successful online validations.
2. The default offline validation grace is 7 days; both values are server-configurable per subscription.
3. Every newly minted signed license contains concrete `validation_required_at` and `validation_grace_until` timestamps.
4. The client never extends either timestamp locally.
5. Failed connectivity while validation is due does not delete or hide customer data.
6. Writes remain available only until the signed validation grace deadline.
7. After the signed validation grace deadline, operational writes fail closed and the application remains readable/exportable/back-up capable.
8. A successful validation uses the SEC.011 device-proof protocol and returns a fresh Yalla-signed license.
9. Server suspension/revocation discovered during periodic validation immediately follows SEC.011 READ ONLY rules.
10. SQLite values are projections only; editing them cannot create a valid future signed validation window.
11. Clock rollback/tamper hardening beyond these signed deadlines is SEC.016.
