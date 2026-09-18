# C06 Codemagic environment variables

القيم المطلوبة لبناء نسخة التحقق:

- YALLA_LICENSING_BASE_URL
- YALLA_LICENSE_TRUSTED_KEY_SHA256
- YALLA_STORE_DISTRIBUTION

وثائق Phase 17 القانونية أصبحت مضمّنة داخل حزمة Yallah Accounts،
لذلك لا يحتاج البناء إلى روابط Privacy / Terms / Account Deletion خارجية.

خطوة البناء:

```bash
chmod +x ci/c06_build_ios.sh
./ci/c06_build_ios.sh
```

Artifact:
`build/ios/Yalla_Accounts_C06_Unsigned_iPhone.ipa`
