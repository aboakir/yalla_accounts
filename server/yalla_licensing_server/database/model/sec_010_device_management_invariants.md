# SEC.010 device management invariants

1. Server device state is authoritative; client SQLite cannot add/revoke/replace a server device.
2. MAX_DEVICES is resolved from SEC.003 effective entitlements only.
3. ACTIVE and SUSPENDED devices consume capacity; REVOKED and REPLACED do not.
4. REVOKED and REPLACED are terminal and never silently return to ACTIVE.
5. Replacement must bind an ACTIVE replacement device in the same organization.
6. Device revoke/replace revokes active licenses for the old device.
7. Activation kind is inferred from the hashed server grant; the client does not choose it.
8. ADD_DEVICE and DEVICE_REPLACEMENT require approved server management context.
9. Replacement is slot-neutral only inside one atomic server transaction.
10. Customer client is not a trusted management actor; Control Center is SEC.013 and Super Owner authorization is SEC.014.
11. No private signing/device key is introduced by SEC.010.
12. Historical activation grants remain protocol v1; new managed grants use protocol v2 with strict action/device binding.
13. Client DB remains v67; historical accounting data rewrite is NONE.
