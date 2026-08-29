import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class AddUserDialog extends ConsumerStatefulWidget {
  const AddUserDialog({super.key});

  @override
  ConsumerState<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _role = RoleKeys.readOnly;
  String _status = 'active';
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final newUser = AppUser(
      id: '',
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      role: _role,
      status: _status,
      createdAt: DateTime.now(),
    );

    try {
      final success = await ref.read(userServiceProvider).registerUser(
            newUser,
            _passwordController.text,
          );

      if (!mounted) {
        return;
      }
      if (success) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إضافة المستخدم: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('إضافة مستخدم'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'اسم المستخدم مطلوب'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration:
                    const InputDecoration(labelText: 'البريد الإلكتروني'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور المؤقتة',
                  helperText:
                      '10 أحرف على الأقل وتحتوي حروفًا وأرقامًا. سيُجبر المستخدم على تغييرها.',
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'إظهار كلمة المرور'
                        : 'إخفاء كلمة المرور',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(
                        () => _obscurePassword = !_obscurePassword,
                      );
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null) {
                    return 'كلمة المرور مطلوبة';
                  }
                  return UserService.validatePasswordPolicy(value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: RoleKeys.assignable
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(RoleKeys.displayNameAr(role)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _role = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('نشط')),
                  DropdownMenuItem(value: 'frozen', child: Text('مجمّد')),
                ],
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _status = value);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('إنشاء المستخدم'),
        ),
      ],
    );
  }
}
