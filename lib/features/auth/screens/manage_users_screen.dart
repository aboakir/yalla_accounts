import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/widgets/add_user_dialog.dart';
import 'package:yalla_accounts/features/auth/widgets/edit_user_dialog.dart';

class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> {
  bool _loading = true;
  List<AppUser> _users = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final users = await ref.read(userServiceProvider).getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('تعذر تحميل المستخدمين: $e');
    }
  }

  Future<void> _addUser() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddUserDialog(),
    );
    if (changed == true) {
      await _reload();
    }
  }

  Future<void> _editUser(AppUser user) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => EditUserDialog(user: user),
    );
    if (changed == true) {
      await _reload();
    }
  }

  Future<void> _toggleStatus(AppUser user) async {
    if (user.isOwner) return;
    final next = user.status == 'active' ? 'frozen' : 'active';
    try {
      await ref.read(userServiceProvider).updateStatus(user.id, next);
      await _reload();
    } catch (e) {
      _showError('تعذر تغيير حالة المستخدم: $e');
    }
  }

  Future<void> _resetPassword(AppUser user) async {
    if (user.isOwner) {
      _showError(
        'كلمة مرور المالك لا تُعاد من إدارة المستخدمين. استخدم استعادة حساب المالك.',
      );
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetUserPasswordDialog(user: user),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تعيين كلمة مرور مؤقتة. سيُطلب من المستخدم تغييرها عند أول دخول.',
          ),
        ),
      );
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
    final actor = ref.watch(currentUserProvider);

    if (actor == null || !actor.isOwner) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Text('إدارة المستخدمين متاحة لمالك المنشأة فقط.'),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المستخدمون والصلاحيات'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : _addUser,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('إضافة مستخدم'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _users.isEmpty
                ? const Center(child: Text('لا يوجد مستخدمون.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final active = user.status == 'active';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              user.isOwner
                                  ? Icons.workspace_premium
                                  : Icons.person_outline,
                            ),
                          ),
                          title: Text(
                            user.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (user.email.trim().isNotEmpty)
                                Text(user.email),
                              Text(RoleKeys.displayNameAr(user.role)),
                              Text(
                                active ? 'نشط' : 'مجمّد',
                                style: TextStyle(
                                  color: active
                                      ? Colors.green.shade700
                                      : Colors.orange.shade800,
                                ),
                              ),
                              if (user.mustChangePassword)
                                const Text(
                                  'مطلوب تغيير كلمة المرور عند الدخول القادم',
                                  style: TextStyle(color: Colors.deepOrange),
                                ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              switch (value) {
                                case 'edit':
                                  await _editUser(user);
                                  break;
                                case 'reset':
                                  await _resetPassword(user);
                                  break;
                                case 'status':
                                  await _toggleStatus(user);
                                  break;
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('تعديل المستخدم'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (!user.isOwner)
                                const PopupMenuItem(
                                  value: 'reset',
                                  child: ListTile(
                                    leading: Icon(Icons.password),
                                    title: Text('تعيين كلمة مرور مؤقتة'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (!user.isOwner)
                                PopupMenuItem(
                                  value: 'status',
                                  child: ListTile(
                                    leading: Icon(
                                      active
                                          ? Icons.pause_circle_outline
                                          : Icons.play_circle_outline,
                                    ),
                                    title: Text(
                                      active
                                          ? 'تجميد المستخدم'
                                          : 'إعادة تفعيل المستخدم',
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _ResetUserPasswordDialog extends ConsumerStatefulWidget {
  const _ResetUserPasswordDialog({required this.user});

  final AppUser user;

  @override
  ConsumerState<_ResetUserPasswordDialog> createState() =>
      _ResetUserPasswordDialogState();
}

class _ResetUserPasswordDialogState
    extends ConsumerState<_ResetUserPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);

    try {
      await ref.read(userServiceProvider).resetUserPasswordByOwner(
            userId: widget.user.id,
            temporaryPassword: _password.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إعادة تعيين كلمة المرور: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration({
    required String label,
    required bool obscure,
    required VoidCallback toggle,
  }) {
    return InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: obscure ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
        icon: Icon(
          obscure ? Icons.visibility_off : Icons.visibility,
        ),
        onPressed: toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('كلمة مرور مؤقتة — ${widget.user.name}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'لن تظهر كلمة المرور القديمة. أنشئ كلمة مؤقتة جديدة، '
                'وسيُجبر المستخدم على تغييرها عند أول دخول.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: _decoration(
                  label: 'كلمة المرور المؤقتة',
                  obscure: _obscurePassword,
                  toggle: () {
                    setState(
                      () => _obscurePassword = !_obscurePassword,
                    );
                  },
                ),
                validator: (value) =>
                    UserService.validatePasswordPolicy(value ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscureConfirm,
                autocorrect: false,
                enableSuggestions: false,
                decoration: _decoration(
                  label: 'تأكيد كلمة المرور',
                  obscure: _obscureConfirm,
                  toggle: () {
                    setState(
                      () => _obscureConfirm = !_obscureConfirm,
                    );
                  },
                ),
                validator: (value) {
                  if (value != _password.text) {
                    return 'كلمتا المرور غير متطابقتين';
                  }
                  return UserService.validatePasswordPolicy(value ?? '');
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ كلمة المرور المؤقتة'),
        ),
      ],
    );
  }
}
