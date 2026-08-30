import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  String _status = '';
  bool _busy = false;

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final path = await BackupService.makeBackup();
      if (!mounted) return;
      setState(() => _status = 'تم إنشاء النسخة الاحتياطية: $path');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'فشل النسخ الاحتياطي: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: const Text(
          'سيتم التحقق من النسخة أولًا، ثم أخذ نسخة أمان من القاعدة الحالية '
          'قبل الاستبدال. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final path = await BackupService.restoreFromPicker();
      if (!mounted) return;

      setState(
        () => _status = path == null
            ? 'تم إلغاء اختيار الملف.'
            : 'تمت الاستعادة والتحقق من القاعدة: $path',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'فشل الاسترجاع وتمت الاستعادة الآمنة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _backup,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('إنشاء نسخة احتياطية'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('استعادة من ملف'),
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              SelectableText(_status),
            ],
            const SizedBox(height: 24),
            const Text(
              'الاستعادة لا تستبدل القاعدة قبل التحقق من الملف وأخذ نسخة أمان.',
            ),
          ],
        ),
      ),
    );
  }
}
