# C06 Codemagic environment variables

أدخل القيم الست الموجودة في:
`%USERPROFILE%\Downloads\YALLA_C06_TEST_CONTEXT.txt`

داخل Codemagic Environment Variables:

- YALLA_LICENSING_BASE_URL
- YALLA_LICENSE_TRUSTED_KEY_SHA256
- YALLA_STORE_DISTRIBUTION
- YALLA_PRIVACY_URL
- YALLA_TERMS_URL
- YALLA_ACCOUNT_DELETION_URL

ثم اجعل خطوة البناء تستدعي:

```bash
chmod +x ci/c06_build_ios.sh
./ci/c06_build_ios.sh
```

Artifact:
`build/ios/Yalla_Accounts_C06_Unsigned_iPhone.ipa`

مهم: اترك Windows PC الذي يشغّل C06 test server + Quick Tunnel متصلًا طوال build والاختبار.
