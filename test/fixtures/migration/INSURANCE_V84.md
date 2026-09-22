# Synthetic insurance v84 fixture

`insurance84.db.gz` is a synthetic, customer-data-free migration fixture. It
is **not** a copy of a production database and must not be described as one.

Its lineage is:

1. `commercial83.db.gz`, whose source and logical packaging provenance are in
   `PROVENANCE.json`.
2. A byte copy of that fixture was migrated by the exact DB84 release source,
   commit `eef3d1b96263d3a1ac72429f3d1788f6c958805c`.
3. The builder added one legacy v84 insurance company, policy, and installment
   using only columns available in v84. The installment intentionally has no
   receipt or GL posting.
4. The database was checkpointed into rollback-journal mode and gzip-packed.

The source fixture is never opened for writing. The v85 regression test
decompresses it into a fresh system temporary directory and migrates only that
copy. It verifies the packaged hashes, v84 and v85 integrity, foreign keys,
balanced and unchanged GL facts, row preservation, insurer Party/Supplier
normalization, Phase 10 columns, document sequencing, and idempotent reopen.

The builder source is
`tool/migration/build_synthetic_insurance_v84_fixture_test.dart`. To rebuild,
export commit `eef3d1b` into a disposable directory, copy the builder to that
export's `test` directory, and run it there with:

```powershell
$env:YALLA_COMMERCIAL83_FIXTURE = '<current-repo>\test\fixtures\migration\commercial83.db.gz'
$env:YALLA_INSURANCE84_OUTPUT = '<current-repo>\test\fixtures\migration\insurance84.db.gz'
flutter test test\build_synthetic_insurance_v84_fixture_test.dart
```

The packaged raw SHA-256 is
`79efedd3328a076a78b25e662ed37889e174d3c411e8bb53bf487e8eadd39816`;
the gzip SHA-256 is
`d3e371d9648c39ccae371ab3252b5adb1f94e6a9f29b35a3aacb05ce549ed4db`.

Passing this fixture gate proves the historical synthetic lineage migrates
copy-only. A separately supplied, approved v84 production-copy fixture is
still required before claiming production-data migration equivalence.
