# Periodic Online Validation Contract - SEC.012

SEC.012 reuses the SEC.011 `VALIDATE` challenge/device-proof flow.

For every successful validation the licensing server MUST:

1. evaluate current subscription/license/device/suspension state;
2. call `yalla_record_periodic_validation`;
3. compute the next window using `yalla_license_validation_window`;
4. mint a fresh Yalla-signed license containing:
   - `validation_required_at`
   - `validation_grace_until`
5. return the fresh signed license plus verification keyset and server time.

Default policy is 30 validation days plus 7 offline grace days. These are
server-side subscription policy values and are not client-authoritative.

If validation cannot be completed while the client is before the signed grace
end, the client may continue operational writes. At/after the signed grace end,
operational writes fail closed into READ ONLY while view/report/print/export/
backup/auth/recovery/licensing-network operations remain available.

Clock rollback/tamper detection is hardened separately in SEC.016.
