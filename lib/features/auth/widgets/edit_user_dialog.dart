import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class EditUserDialog extends ConsumerStatefulWidget {
  const EditUserDialog({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late String _role;
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _emailController = TextEditingController(text: widget.user.email);
    _role = widget.user.role;
    _status = widget.user.status;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final updatedUser = widget.user.copyWith(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      role: widget.user.isOwner ? RoleKeys.owner : _role,
      status: widget.user.isOwner ? 'active' : _status,
    );

    try {
      await ref.read(userServiceProvider).updateUser(updatedUser);
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ المستخدم: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: Text(widget.user.isOwner ? 'تعديل المالك' : 'تعديل المستخدم'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'اسم المستخدم مطلوب'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _emailController,
                decoration:
                    const InputDecoration(labelText: 'البريد الإلكتروني'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: widget.user.isOwner ? RoleKeys.owner : _role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: widget.user.isOwner
                    ? const [
                        DropdownMenuItem(
                          value: RoleKeys.owner,
                          child: Text('مالك المنشأة'),
                        ),
                      ]
                    : RoleKeys.assignable
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(RoleKeys.displayNameAr(role)),
                          ),
                        )
                        .toList(growable: false),
                onChanged: widget.user.isOwner || _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _role = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: widget.user.isOwner ? 'active' : _status,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('نشط')),
                  DropdownMenuItem(value: 'frozen', child: Text('مجمّد')),
                ],
                onChanged: widget.user.isOwner || _isSaving
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
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
