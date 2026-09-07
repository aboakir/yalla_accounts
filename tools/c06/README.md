# C06 test tools

1. طبّق Patch `YALLA_C06_FINAL_PREP_FIX1`.
2. شغّل:
   `powershell -ExecutionPolicy Bypass -File .\tools\c06\prepare_c06_test.ps1`
3. سيظهر `YALLA_C06_TEST_CONTEXT.txt` في Downloads.
4. أبقِ الكمبيوتر متصلًا بالإنترنت أثناء Codemagic واختبار iPhone.
5. بعد انتهاء الاختبار:
   `powershell -ExecutionPolicy Bypass -File .\tools\c06\stop_c06_test.ps1`

Quick Tunnel مخصص للاختبار فقط وليس للإطلاق التجاري.
