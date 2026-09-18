import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/settings/services/backup_key_store.dart';
import 'package:yalla_accounts/features/settings/services/weekly_backup_guardian_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class WeeklyBackupGuardianDialog {
  WeeklyBackupGuardianDialog._();

  static bool _shownThisSession = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (_shownThisSession || !context.mounted) return;
    final canBackup =
        await PermissionService().canCurrent(PermissionKeys.backupCreate);
    if (!canBackup || !context.mounted) return;
    final status = await WeeklyBackupGuardianService.load();
    if (!status.isDue(DateTime.now()) || !context.mounted) return;
    _shownThisSession = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('حان وقت حماية بيانات الورشة'),
        content: Text(
          'مر أسبوع على موعد النسخة الاحتياطية.\n\n'
          'Yalla سينشئ نسخة مشفرة كاملة تشمل قاعدة البيانات والصور والمرفقات. '
          'بعد حفظ النسخة محليًا سنفتح مشاركة النسخة خارج الجهاز'
          '${(status.backupEmail ?? '').trim().isEmpty ? '' : ' إلى ${status.backupEmail}'}.'
          '\n\nيمكنك الرفض أو التأجيل، لكن بقاء النسخة على جهاز واحد فقط يعرض البيانات للفقد عند تلف الجهاز.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await WeeklyBackupGuardianService.skipThisWeek();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('تخطي هذا الأسبوع'),
          ),
          TextButton(
            onPressed: () async {
              await WeeklyBackupGuardianService.snoozeOneDay();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('ذكرني غدًا'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (!context.mounted) return;
              await _createNow(context, status.backupEmail);
            },
            icon: const Icon(Icons.shield_outlined),
            label: const Text('إنشاء النسخة الآن'),
          ),
        ],
      ),
    );
  }

  static Future<void> _createNow(BuildContext context, String? email) async {
    var password = await BackupKeyStore.readPassword();
    if (!context.mounted) return;
    if (password == null) {
      password = await _requestPassword(context);
      if (password == null) return;
      await BackupKeyStore.savePassword(password);
    }
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AdaptiveAlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('يتم إنشاء وفحص النسخة المشفرة بكل الصور...')),
          ],
        ),
      ),
    );

    try {
      final result = await BackupService.createEncryptedBackup(
        password: password,
        kind: 'weekly',
        targetEmail: email,
      );
      await WeeklyBackupGuardianService.recordLocalBackup(result.createdAt);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final share = await showDialog<bool>(
        context: context,
        builder: (_) => AdaptiveAlertDialog(
          title: const Text('تم حفظ النسخة المحلية ✓'),
          content: Text(
            'الحجم: ${result.sizeMb.toStringAsFixed(1)} MB\n'
            'النسخة مشفرة وتم التحقق منها.\n\n'
            '${result.sizeBytes > BackupService.emailAttachmentAdvisoryBytes ? 'الحجم قد يتجاوز حد مرفقات البريد؛ اختر Drive/OneDrive/iCloud من نافذة المشاركة إذا رفض البريد.\n\n' : ''}'
            'هل تريد إرسال/حفظ النسخة خارج هذا الجهاز الآن؟',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ليس الآن')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('مشاركة خارج الجهاز')),
          ],
        ),
      );
      if (share == true) {
        await BackupService.shareEncryptedBackup(result.path,
            targetEmail: email);
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إنشاء النسخة الاحتياطية: $e')),
      );
    }
  }

  static Future<String?> _requestPassword(BuildContext context) async {
    final first = TextEditingController();
    final confirm = TextEditingController();
    try {
      return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AdaptiveAlertDialog(
          title: const Text('كلمة حماية النسخ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ضع كلمة لا تقل عن 10 أحرف واحفظها خارج الجهاز. '
                'ستحتاجها إذا تلف الهاتف/الكمبيوتر واستعدت النسخة على جهاز جديد.',
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: first,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة الحماية')),
              const SizedBox(height: 8),
              TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'تأكيد كلمة الحماية')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final a = first.text.trim();
                if (a.length < 10 || a != confirm.text.trim()) return;
                Navigator.pop(ctx, a);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
    } finally {
      first.dispose();
      confirm.dispose();
    }
  }
}
