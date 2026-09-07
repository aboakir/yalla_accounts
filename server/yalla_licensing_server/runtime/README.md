# Yalla C06 Licensing Test Authority

هذا Runtime مخصص فقط لاختبار C06 على جهاز حقيقي. لا يستخدم كخادم Production.

## ما الذي يفعله
- Ed25519 signing authority محلي.
- Activation challenge + device proof verification.
- Signed license envelope مطابق لعقد العميل الحالي.
- VALIDATE / RENEW lifecycle challenge flow.
- صفحات Privacy / Terms / Account Deletion.
- تخزين JSON محلي للاختبار فقط.

## الأمن
- المفتاح الخاص وكود التفعيل داخل `runtime/secrets/` وهي git-ignored.
- لا يوجد أي bypass داخل تطبيق العميل.
- Quick Tunnel يستخدم للاختبار فقط؛ Production يحتاج خادم HTTPS ثابت ومخزن أسرار فعلي.

## التشغيل
من PowerShell داخل جذر المشروع:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\c06\prepare_c06_test.ps1
```

سيولد ملفًا في Downloads باسم `YALLA_C06_TEST_CONTEXT.txt` يحتوي:
- HTTPS URL المؤقت.
- Trusted key SHA256.
- Activation code.
- متغيرات البناء اللازمة لـ Codemagic.
