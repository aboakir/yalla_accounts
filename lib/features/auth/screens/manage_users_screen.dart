import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/widgets/add_user_dialog.dart';
import 'package:yalla_accounts/features/auth/widgets/edit_user_dialog.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

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
      _showError('طھط¹ط°ط± طھط­ظ…ظٹظ„ ط§ظ„ظ…ط³طھط®ط¯ظ…ظٹظ†: $e');
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
      _showError('طھط¹ط°ط± طھط؛ظٹظٹط± ط­ط§ظ„ط© ط§ظ„ظ…ط³طھط®ط¯ظ…: $e');
    }
  }

  Future<void> _resetPassword(AppUser user) async {
    if (user.isOwner) {
      _showError(
        'ظƒظ„ظ…ط© ظ…ط±ظˆط± ط§ظ„ظ…ط§ظ„ظƒ ظ„ط§ طھظڈط¹ط§ط¯ ظ…ظ† ط¥ط¯ط§ط±ط© ط§ظ„ظ…ط³طھط®ط¯ظ…ظٹظ†. ط§ط³طھط®ط¯ظ… ط§ط³طھط¹ط§ط¯ط© ط­ط³ط§ط¨ ط§ظ„ظ…ط§ظ„ظƒ.',
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
            'طھظ… طھط¹ظٹظٹظ† ظƒظ„ظ…ط© ظ…ط±ظˆط± ظ…ط¤ظ‚طھط©. ط³ظٹظڈط·ظ„ط¨ ظ…ظ† ط§ظ„ظ…ط³طھط®ط¯ظ… طھط؛ظٹظٹط±ظ‡ط§ ط¹ظ†ط¯ ط£ظˆظ„ ط¯ط®ظˆظ„.',
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
            child: Text(
                'ط¥ط¯ط§ط±ط© ط§ظ„ظ…ط³طھط®ط¯ظ…ظٹظ† ظ…طھط§ط­ط© ظ„ظ…ط§ظ„ظƒ ط§ظ„ظ…ظ†ط´ط£ط© ظپظ‚ط·.'),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ط§ظ„ظ…ط³طھط®ط¯ظ…ظˆظ† ظˆط§ظ„طµظ„ط§ط­ظٹط§طھ'),
          actions: [
            IconButton(
              tooltip: 'طھط­ط¯ظٹط«',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : _addUser,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('ط¥ط¶ط§ظپط© ظ…ط³طھط®ط¯ظ…'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _users.isEmpty
                ? const Center(child: Text('ظ„ط§ ظٹظˆط¬ط¯ ظ…ط³طھط®ط¯ظ…ظˆظ†.'))
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
                                active ? 'ظ†ط´ط·' : 'ظ…ط¬ظ…ظ‘ط¯',
                                style: TextStyle(
                                  color: active
                                      ? Colors.green.shade700
                                      : Colors.orange.shade800,
                                ),
                              ),
                              if (user.mustChangePassword)
                                const Text(
                                  'ظ…ط·ظ„ظˆط¨ طھط؛ظٹظٹط± ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ط¹ظ†ط¯ ط§ظ„ط¯ط®ظˆظ„ ط§ظ„ظ‚ط§ط¯ظ…',
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
                                  title: Text('طھط¹ط¯ظٹظ„ ط§ظ„ظ…ط³طھط®ط¯ظ…'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (!user.isOwner)
                                const PopupMenuItem(
                                  value: 'reset',
                                  child: ListTile(
                                    leading: Icon(Icons.password),
                                    title: Text(
                                        'طھط¹ظٹظٹظ† ظƒظ„ظ…ط© ظ…ط±ظˆط± ظ…ط¤ظ‚طھط©'),
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
                                          ? 'طھط¬ظ…ظٹط¯ ط§ظ„ظ…ط³طھط®ط¯ظ…'
                                          : 'ط¥ط¹ط§ط¯ط© طھظپط¹ظٹظ„ ط§ظ„ظ…ط³طھط®ط¯ظ…',
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
        SnackBar(
            content: Text(
                'طھط¹ط°ط± ط¥ط¹ط§ط¯ط© طھط¹ظٹظٹظ† ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط±: $e')),
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
        tooltip: obscure
            ? 'ط¥ط¸ظ‡ط§ط± ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط±'
            : 'ط¥ط®ظپط§ط، ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط±',
        icon: Icon(
          obscure ? Icons.visibility_off : Icons.visibility,
        ),
        onPressed: toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: Text('ظƒظ„ظ…ط© ظ…ط±ظˆط± ظ…ط¤ظ‚طھط© â€” ${widget.user.name}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ظ„ظ† طھط¸ظ‡ط± ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ط§ظ„ظ‚ط¯ظٹظ…ط©. ط£ظ†ط´ط¦ ظƒظ„ظ…ط© ظ…ط¤ظ‚طھط© ط¬ط¯ظٹط¯ط©طŒ '
                'ظˆط³ظٹظڈط¬ط¨ط± ط§ظ„ظ…ط³طھط®ط¯ظ… ط¹ظ„ظ‰ طھط؛ظٹظٹط±ظ‡ط§ ط¹ظ†ط¯ ط£ظˆظ„ ط¯ط®ظˆظ„.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: _decoration(
                  label: 'ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ط§ظ„ظ…ط¤ظ‚طھط©',
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
                  label: 'طھط£ظƒظٹط¯ ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط±',
                  obscure: _obscureConfirm,
                  toggle: () {
                    setState(
                      () => _obscureConfirm = !_obscureConfirm,
                    );
                  },
                ),
                validator: (value) {
                  if (value != _password.text) {
                    return 'ظƒظ„ظ…طھط§ ط§ظ„ظ…ط±ظˆط± ط؛ظٹط± ظ…طھط·ط§ط¨ظ‚طھظٹظ†';
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
          child: const Text('ط¥ظ„ط؛ط§ط،'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ط­ظپط¸ ظƒظ„ظ…ط© ط§ظ„ظ…ط±ظˆط± ط§ظ„ظ…ط¤ظ‚طھط©'),
        ),
      ],
    );
  }
}
