# CR1 Phase 12 — CI/CD and Release Engineering

Status: PASS
Date: 2026-09-17
Release train: CR1-P12
Version Matrix SHA256: `199f379b0c6fe78541e34aaa86aea9fb3e6312198de335888ffa697cb205e167`

## Compatibility matrix
- Yalla Accounts: `1.0.0+18`
- Yalla Control: `1.0.0+1`
- Control Server: `0.1.0`
- Commercial contract: v2
- Sync contract: v3
- Accounts DB schema: v82

## Release gates
- Accounts Phase 12/11 focused gate: 9/9 PASS.
- Accounts accounting + sync + Phase12 gate: 101/101 PASS.
- Accounts Windows release build: PASS.
- Yalla Control full suite: 326/326 PASS.
- Yalla Control Windows release build: PASS.
- Control cross-repository contracts: 4/4 PASS.
- Backend standalone suite: 164/164 PASS.
- Backend contract suite: 18/18 PASS.
- Backend dependency audit: 0 vulnerabilities.
## Release engineering guarantees
- Flutter is pinned to 3.44.8 in active Flutter CI.
- Node is pinned to major 24 in backend CI.
- Production configuration is supplied from protected CI secrets, not source.
- Android release signing is fail-closed and materialized only during release jobs.
- Unsigned iOS remains a verification artifact and is not labeled production release.
- Quick Tunnel/test endpoints and hardcoded pins are absent from active CI.
- Every artifact carries source commit, Version Matrix hash and SHA256 provenance.
- A deliberate version mismatch was rejected by the release matrix validator.
- All active GitHub, GitLab and Codemagic YAML files parse successfully.
- Production backend preflight is manual/protected and requires real production secrets/database.

No production deployment was performed in Phase 12.
