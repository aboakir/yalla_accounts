import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/reset_password_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  ConsumerState<AccountSecurityScreen> createState() =>
      _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends ConsumerState<AccountSecurityScreen> {
  bool _busy = false;

  Future<void> _changePassword() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ResetPasswordScreen(
          authenticatedUserId: user.id,
        ),
      ),
    );
  }

  Future<String?> _promptOwnerPassword() async {
    final controller = TextEditingController();
    var visible = false;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('إعادة التحقق من هوية المالك'),
            content: TextField(
              controller: controller,
              obscureText: !visible,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية',
                helperText: 'مطلوبة قبل تغيير وسائل استعادة الحساب.',
                suffixIcon: IconButton(
                  tooltip: visible ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
                  icon: Icon(
                    visible ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setDialogState(() => visible = !visible),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text;
                  if (value.isNotEmpty) {
                    Navigator.of(dialogContext).pop(value);
                  }
                },
                child: const Text('تحقق'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _generateRecoveryCode() async {
    final user = ref.read(currentUserProvider);
    if (user == null || !user.isOwner || _busy) return;

    final currentPassword = await _promptOwnerPassword();
    if (currentPassword == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final code = await ref
          .read(userServiceProvider)
          .generateOwnerRecoveryCode(currentPassword: currentPassword);
      if (!mounted || code == null) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('كود استعادة جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'الكود السابق أصبح غير صالح. هذا الكود يُعرض مرة واحدة فقط.',
              ),
              const SizedBox(height: 16),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('نسخ وإغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('تعذر إنشاء كود الاستعادة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgetSavedLogin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authSessionServiceProvider).forgetSavedLoginData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم نسيان بيانات الدخول المحفوظة. ستحتاج لتسجيل الدخول عند تشغيل البرنامج لاحقًا.',
          ),
        ),
      );
    } catch (e) {
      _showError('تعذر نسيان بيانات الدخول المحفوظة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logoutAll() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج من جميع الجلسات'),
        content: const Text(
          'سيتم إلغاء كل جلسات هذا الحساب، بما فيها الجلسة الحالية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(authSessionServiceProvider).revokeAllForUser(user.id);
      ref.read(currentUserProvider.notifier).state = null;
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (e) {
      _showError('تعذر إنهاء الجلسات: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حسابي وأمان الحساب')),
        body: user == null
            ? const Center(child: Text('لا توجد جلسة مستخدم نشطة.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(user.name),
                      subtitle: Text(
                        user.email.trim().isEmpty
                            ? 'لا يوجد بريد إلكتروني محفوظ'
                            : user.email,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.password),
                          title: const Text('تغيير كلمة المرور'),
                          subtitle: const Text(
                            'يتطلب كلمة المرور الحالية، ثم يلغي الجلسات السابقة.',
                          ),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: _busy ? null : _changePassword,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.phonelink_erase),
                          title: const Text(
                            'نسيان بيانات الدخول المحفوظة على هذا الجهاز',
                          ),
                          subtitle: const Text(
                            'يمسح اسم المستخدم المتذكر والجلسة الدائمة، ولا يحفظ كلمة المرور أصلًا.',
                          ),
                          onTap: _busy ? null : _forgetSavedLogin,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('تسجيل الخروج من جميع الجلسات'),
                          onTap: _busy ? null : _logoutAll,
                        ),
                      ],
                    ),
                  ),
                  if (user.isOwner) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.key_outlined),
                        title: const Text('إنشاء كود استعادة جديد'),
                        subtitle: const Text(
                          'يتطلب كلمة المرور الحالية، ويُعرض مرة واحدة فقط '
                          'ويُبطل الكود السابق.',
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: _busy ? null : _generateRecoveryCode,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Yalla Accounts لا يعرض كلمة المرور القديمة ولا يخزنها كنص على الكمبيوتر.',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
