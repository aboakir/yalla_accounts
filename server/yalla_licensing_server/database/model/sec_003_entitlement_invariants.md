# SEC.003 entitlement invariants

1. The server is the commercial source of truth for plan and entitlement state.
2. Client SQLite remains at v63 and receives no subscription/plan/feature tables in SEC.003.
3. Feature values are typed at the database boundary: BOOLEAN, INTEGER, DECIMAL, TEXT, or JSON.
4. MAX_USERS and MAX_DEVICES are integer entitlements with a minimum value of 1.
5. A plan can define at most one value per feature.
6. Subscription overrides are explicit, reasoned, time-bounded when required, and deterministic if overlaps exist.
7. Effective precedence is: active subscription override > plan entitlement > absent/not entitled.
8. Overlapping overrides resolve by priority, then starts_at, created_at, and id in descending order.
9. Plan entitlement changes bump plans.entitlement_revision.
10. Subscription override changes bump subscriptions.entitlement_revision.
11. Relevant feature-definition changes propagate entitlement revisions to affected plans/subscriptions.
12. No commercial plan name or price is invented in SEC.003.
13. The generic SEC.002 overrides table is not used by the normal entitlement evaluator; it remains reserved for later privileged/Break Glass flows.
14. No signing secret, private key, master password, or universal admin credential is stored in the client or this entitlement migration.
15. Cryptographic signing remains SEC.004; activation remains SEC.006.
