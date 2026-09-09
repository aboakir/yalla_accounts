import 'package:yalla_accounts/features/cloud_auth/cloud_auth_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/features/auth/screens/manage_users_screen.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/settings/screens/audit_trail_screen.dart';
import 'package:yalla_accounts/features/settings/services/backup_key_store.dart';
import 'package:yalla_accounts/features/settings/services/weekly_backup_guardian_service.dart';
import 'package:yalla_accounts/features/settings/services/windows_migration_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SecurityDataScreen extends StatefulWidget {
  const SecurityDataScreen({super.key});

  @override
  State<SecurityDataScreen> createState() => _SecurityDataScreenState();
}

class _SecurityDataScreenState extends State<SecurityDataScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _weekly = true;
  bool _hasPassword = false;
  final _email = TextEditingController();
  BackupGuardianStatus? _status;
  EncryptedBackupResult? _latest;
  DateTime? _lastRestore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await WeeklyBackupGuardianService.load();
    final latest = await BackupService.latestEncryptedBackup();
    final hasPassword = await BackupKeyStore.hasPassword();
    final lastRestore = await BackupService.lastRestoreAt();
    if (!mounted) return;
    setState(() {
      _status = status;
      _weekly = status.weeklyEnabled;
      _email.text = status.backupEmail ?? '';
      _latest = latest;
      _hasPassword = hasPassword;
      _lastRestore = lastRestore;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    await WeeklyBackupGuardianService.savePreferences(
      weeklyEnabled: _weekly,
      backupEmail: _email.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات الحماية والنسخ.')),
    );
    await _load();
  }

  Future<String?> _passwordDialog({String title = 'كلمة حماية النسخ'}) async {
    final a = TextEditingController();
    final b = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'هذه الكلمة لا تُرسل مع النسخة. احتفظ بها خارج الجهاز؛ '
                'ستحتاجها على الهاتف/الكمبيوتر الجديد.',
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: a,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة الحماية')),
              const SizedBox(height: 8),
              TextField(
                  controller: b,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'تأكيد الكلمة')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final value = a.text.trim();
                if (value.length < 10 || value != b.text.trim()) return;
                Navigator.pop(ctx, value);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
    } finally {
      a.dispose();
      b.dispose();
    }
  }

  Future<String?> _restorePasswordDialog() async {
    final c = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title: const Text('فك النسخة الاحتياطية'),
          content: TextField(
            controller: c,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'كلمة حماية النسخة'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
    } finally {
      c.dispose();
    }
  }

  Future<void> _setPassword() async {
    final value = await _passwordDialog(
      title: _hasPassword ? 'تغيير كلمة حماية النسخ' : 'إنشاء كلمة حماية النسخ',
    );
    if (value == null) return;
    await BackupKeyStore.savePassword(value);
    await _load();
  }

  Future<void> _createBackup({bool share = false}) async {
    var password = await BackupKeyStore.readPassword();
    if (password == null) {
      password = await _passwordDialog();
      if (password == null) return;
      await BackupKeyStore.savePassword(password);
    }
    await _runBusy(() async {
      final result = await BackupService.createEncryptedBackup(
        password: password!,
        kind: 'manual',
      );
      await WeeklyBackupGuardianService.recordLocalBackup(result.createdAt);
      if (share) {
        await BackupService.shareEncryptedBackup(
          result.path,
          targetEmail: _email.text,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إنشاء وفحص نسخة مشفرة (${result.sizeMb.toStringAsFixed(1)} MB).',
          ),
        ),
      );
    });
  }

  Future<void> _shareLatest() async {
    final latest = await BackupService.latestEncryptedBackup();
    if (latest == null) {
      _message('لا توجد نسخة مشفرة بعد.');
      return;
    }
    await _runBusy(() => BackupService.shareEncryptedBackup(
          latest.path,
          targetEmail: _email.text,
        ));
  }

  Future<void> _restoreEncrypted() async {
    final allowed =
        await PermissionService().canCurrent(PermissionKeys.backupRestore);
    if (!allowed) {
      _message('الاستعادة متاحة للمالك فقط.');
      return;
    }
    if (!mounted) return;
    String? selectedPath;
    try {
      selectedPath = await BackupService.pickEncryptedBackup();
    } catch (e) {
      if (mounted) _message('تعذر اختيار النسخة: $e');
      return;
    }
    if (!mounted || selectedPath == null) return;
    final password = await _restorePasswordDialog();
    if (password == null || password.isEmpty) return;
    final confirm = await _confirmDanger(
      'استعادة نسخة كاملة',
      'ستستبدل هذه العملية بيانات الورشة الحالية ومرفقاتها بمحتويات النسخة المختارة. '
          'سيتم حفظ نسخة أمان كاملة أولًا. عند فشل العملية تُعاد البيانات والملفات السابقة. '
          'بعد النجاح ستحتاج إلى تسجيل الدخول مجددًا.',
    );
    if (!confirm) return;
    await _runBusy(() async {
      await BackupService.restoreEncryptedFromPath(selectedPath!,
          password: password);
      if (!mounted) return;
      ProviderScope.containerOf(context)
          .read(currentUserProvider.notifier)
          .state = null;
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    });
  }

  Future<void> _importWindowsDb() async {
    final confirm = await _confirmDanger(
      'استيراد بيانات Windows',
      'هذا ليس Merge عشوائيًا. سيتم أخذ Safety Backup ثم استبدال قاعدة Mobile '
          'بقاعدة Windows المختارة وتشغيل مسار Migration الرسمي.',
    );
    if (!confirm) return;
    await _runBusy(() async {
      final path = await WindowsMigrationService.importDatabaseFromPicker();
      if (path != null) {
        _message('تم استيراد قاعدة Windows وتشغيل Migration بنجاح.');
      }
    });
  }

  Future<void> _importWindowsFolder() async {
    final confirm = await _confirmDanger(
      'استيراد مجلد Windows كامل',
      'سيبحث Yalla عن yalla_accounts.db داخل المجلد ويستورد قاعدة البيانات '
          'ثم ينسخ مجلدات الصور/المستندات المعروفة. سيتم أخذ Safety Backup أولًا.',
    );
    if (!confirm) return;
    await _runBusy(() async {
      final path = await WindowsMigrationService.importFolderFromPicker();
      if (path != null) _message('تم استيراد قاعدة Windows والملفات المتاحة.');
    });
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      _message('فشلت العملية: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<bool> _confirmDanger(String title, String body) async =>
      (await showDialog<bool>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('متابعة')),
          ],
        ),
      )) ??
      false;

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _fmt(DateTime? value) => value == null
      ? 'لا يوجد'
      : DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final status = _status!;
    final sizeWarning =
        (_latest?.sizeBytes ?? 0) > BackupService.emailAttachmentAdvisoryBytes;

    return Scaffold(
      appBar: AppBar(title: const Text('الأمان وحماية البيانات')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const CloudAccountLinkTile(),
            if (_busy) const LinearProgressIndicator(),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الحماية الأسبوعية',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: _weekly,
                      onChanged: (v) => setState(() => _weekly = v),
                      title:
                          const Text('تذكير أسبوعي إلزامي ما لم يرفض المستخدم'),
                      subtitle: const Text(
                          'إنشاء نسخة مشفرة كاملة محليًا ثم طلب حفظ/إرسال نسخة خارج الجهاز.'),
                    ),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'البريد المخصص للنسخ',
                        hintText: 'owner@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('حفظ الإعدادات')),
                    const Divider(height: 28),
                    Text(
                        'آخر نسخة محلية: ${_fmt(_latest?.createdAt ?? status.lastLocalBackupAt)}'),
                    Text('آخر استعادة ناجحة: ${_fmt(_lastRestore)}'),
                    Text(
                        'آخر تسليم خارج الجهاز: ${_fmt(status.lastExternalHandoffAt)}'),
                    Text('الموعد القادم: ${_fmt(status.nextDueAt)}'),
                    Text(
                        'كلمة حماية النسخ: ${_hasPassword ? 'مضبوطة ✓' : 'غير مضبوطة ⚠️'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('النسخ والاستعادة',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'تشمل النسخة قاعدة البيانات والإعدادات وبيانات الورشة والشعار وصور الإصلاحات وسجلات التدقيق والتغييرات.'),
                    const SizedBox(height: 8),
                    const Text(
                        'اختر الملفات أو Drive أو iCloud من نافذة مشاركة النظام؛ لا تُرفع النسخة تلقائيًا.'),
                    if (_latest != null)
                      Text(
                          'مكان الحفظ: ${_latest!.path}\nالحجم: ${_latest!.sizeMb.toStringAsFixed(1)} MB'),
                    if (sizeWarning)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '⚠️ النسخة أكبر من 20MB؛ بعض خدمات البريد قد ترفضها كمرفق. استخدم Drive/OneDrive/iCloud من نافذة المشاركة.',
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                            onPressed: () => _createBackup(),
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('نسخة مشفرة الآن')),
                        OutlinedButton.icon(
                            onPressed: () => _createBackup(share: true),
                            icon: const Icon(Icons.outgoing_mail),
                            label: const Text('نسخة + مشاركة خارج الجهاز')),
                        OutlinedButton.icon(
                            onPressed: _shareLatest,
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('مشاركة أحدث نسخة')),
                        OutlinedButton.icon(
                            onPressed: _setPassword,
                            icon: const Icon(Icons.password),
                            label: Text(_hasPassword
                                ? 'تغيير كلمة الحماية'
                                : 'ضبط كلمة الحماية')),
                        FilledButton.tonalIcon(
                            onPressed: _restoreEncrypted,
                            icon: const Icon(Icons.restore),
                            label: const Text('استعادة نسخة .yab')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('المستخدمون والصلاحيات'),
                    subtitle: const Text(
                        'Owner / Manager / Accountant / Employee / Technician'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ManageUsersScreen())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('سجل التدقيق'),
                    subtitle: const Text(
                        'من غيّر ماذا ومتى ولماذا — سجل append-only'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AuditTrailScreen())),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('نقل بيانات Windows',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                        'يعمل كـMigration/Replacement آمن مع Safety Backup. لا ينفذ Merge مالي أعمى بين قاعدتين.'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                            onPressed: _importWindowsDb,
                            icon: const Icon(Icons.storage_outlined),
                            label: const Text('اختيار قاعدة Windows')),
                        if (Platform.isWindows ||
                            Platform.isMacOS ||
                            Platform.isLinux)
                          OutlinedButton.icon(
                              onPressed: _importWindowsFolder,
                              icon: const Icon(Icons.folder_copy_outlined),
                              label: const Text('اختيار مجلد Windows كامل')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
