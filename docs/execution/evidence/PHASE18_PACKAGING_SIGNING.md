# Phase 18 — Packaging / Signing Evidence

Status: PARTIAL_PASS / WINDOWS_AND_APPLE_SIGNING_EXTERNAL
Date: 2026-09-18

- Windows Release executable and internal ZIP candidate remain built and packaged.
- Windows publisher signature is still external and the unsigned Windows candidate is not production accepted.
- Android production keystore is present outside the repository at the private per-user signing location; the existing key was reused and was not replaced.
- `android/key.properties` was recovered locally from the private signing material and remains excluded from Git.
- Signed Android App Bundle produced: `build/app/outputs/bundle/release/app-release.aab`.
- AAB size: 93,080,407 bytes.
- AAB signature verification: `jarsigner -verify -strict` PASS (exit 0).
- AAB SHA-256: `85B1825A5811895C593AEA133E32EF518A7BFDB2E7F5FDBD450BEDA32002B969`.
- Signed Android APK produced: `build/app/outputs/flutter-apk/app-release.apk`.
- APK size: 108,258,945 bytes.
- APK signature verification: `apksigner verify --verbose` PASS (exit 0).
- APK SHA-256: `6E3F2CC65913BC1C950C0E2EC33487D367D0B3C3334F72739EABE37717C6878D`.
- iOS verification flow remains unsigned on Windows; Apple Distribution identity/provisioning remains external.
- Package tooling continues to exclude databases, backups, logs, source secrets, private keys, certificates and environment secrets.
- No unsigned artifact is classified as production accepted.

Remaining external blockers for Phase 18:
1. Trusted Windows publisher/code-signing certificate and signed Windows artifacts.
2. Apple Distribution identity, provisioning and final signed iOS/TestFlight artifact.
