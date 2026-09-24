# ابدأ من هنا — Yallah Accounts Commercial RC

الإصدار: 1.0.3+22 | بنية قاعدة البيانات: DB85.

## المصدر المعتمد
F:\YALLAH_ACCOUNTS_COMMERCIAL_RC_20260924
الفرع: release/commercial-rc-20260924
مرجع الكود الذي اجتاز بوابات المراحل: 747e1fe2012be650e8ad5fef8d74dfc1e301f15c.
هذه النسخة منشأة من GOLD MASTER المعتمد وليست من Clean أو QA أو Worktree أقدم.

## حالة الإطلاق
- Analyzer على RC: صفر أخطاء.
- بوابات المراحل 6–18 اجتازت الاختبارات المسجلة في release/COMMERCIAL_RC_ACCEPTANCE_20260924.json.
- Windows Release بُني بنجاح من RC.
- Android debug تم تثبيته وتشغيله على Emulator API 36 بدون Fatal Exception.
- Android production signing جاهز باستخدام الـkeystore الحقيقي الموجود مسبقًا خارج Git؛ تم استعادة android/key.properties محليًا دون استبدال المفتاح.
- Android commercial build النهائي ينتظر فقط YALLA_LICENSING_BASE_URL وYALLA_LICENSE_TRUSTED_KEY_SHA256 الحقيقيين؛ بيانات Supabase العامة تم التحقق منها من المشروع الحقيقي.
- iOS production يحتاج Apple Distribution/provisioning عبر macOS/Codemagic.
- production_defines.json والأسرار لا تُخزن في المصدر.

## قواعد الأمان
لا تُنشئ مفاتيح أو أسرار إنتاج وهمية ولا تستخدم owner-local bypass في حزمة العملاء.
الكود الفعلي يثبت أن kTemporaryAuthBypass = false.
لا تُعدّل GOLD MASTER؛ أي عمل لاحق يبدأ من هذا RC أو من فرع جديد مشتق منه بعد اعتماد الإصدار.
لا تُجرّب ترقية على قاعدة بيانات عميل حقيقية قبل Backup واختبار نسخة منفصلة.

## المخرجات
Windows: build\windows\x64\runner\Release\yalla_accounts.exe
Android commercial: التوقيع جاهز؛ يلزم فقط إدخال licensing production URL + trusted key SHA الحقيقيين ثم validation/build release.
iOS commercial: يحتاج بيئة Apple signing/Codemagic ومفاتيح الإنتاج الحقيقية.
