import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class ForgotCredentialsDialog extends ConsumerStatefulWidget {
  const ForgotCredentialsDialog({super.key});

  @override
  ConsumerState<ForgotCredentialsDialog> createState() =>
      _ForgotCredentialsDialogState();
}

class _ForgotCredentialsDialogState
    extends ConsumerState<ForgotCredentialsDialog> {
  // ----------------------------
  // Controllers (Verification)
  // ----------------------------
  final _ownerPasswordCtrl = TextEditingController();
  final _securityQ1Ctrl = TextEditingController();
  final _securityQ2Ctrl = TextEditingController();
  final _recoveryCodeCtrl = TextEditingController();

  // ----------------------------
  // Controllers (Update)
  // ----------------------------
  final _newPasswordCtrl = TextEditingController();
  final _newUsernameCtrl = TextEditingController();

  bool _loading = false;
  bool _verified = false;

  /// 0 = Owner Password
  /// 1 = Security Questions
  /// 2 = Recovery Code
  int _mode = 0;

  // ==================================================
  // VERIFY
  // ==================================================
  Future<void> _verify() async {
    setState(() => _loading = true);

    final service = ref.read(userServiceProvider);
    bool ok = false;

    try {
      if (_mode == 0) {
        ok = await service.verifyOwnerPassword(
          _ownerPasswordCtrl.text.trim(),
        );
      } else if (_mode == 1) {
        ok = await service.verifySecurityAnswers(
          answer1: _securityQ1Ctrl.text.trim(),
          answer2: _securityQ2Ctrl.text.trim(),
        );
      } else {
        ok = await service.verifyRecoveryCode(
          _recoveryCodeCtrl.text.trim(),
        );
      }
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
      _verified = ok;
    });

    if (!ok) {
      _error('بيانات التحقق غير صحيحة');
    }
  }

  // ==================================================
  // SAVE CHANGES
  // ==================================================
  Future<void> _saveChanges() async {
    final newPass = _newPasswordCtrl.text.trim();
    final newUser = _newUsernameCtrl.text.trim();

    if (newPass.length < 6) {
      _error('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }

    setState(() => _loading = true);

    final service = ref.read(userServiceProvider);
    final owner = await service.getOwner();

    if (owner == null) {
      _error('لا يوجد مستخدم مالك');
      setState(() => _loading = false);
      return;
    }

    // تغيير اسم المستخدم عملية حساسة وتحتاج إعادة تحقق بكلمة المرور
    // الحالية. وسائل الاستعادة الأخرى لا تمنح صلاحية تغيير الاسم.
    if (newUser.isNotEmpty) {
      if (_mode != 0 || _ownerPasswordCtrl.text.isEmpty) {
        _error('تغيير اسم المستخدم يتطلب كلمة مرور المالك الحالية');
        setState(() => _loading = false);
        return;
      }
      final ok = await service.changeOwnerUsername(
        newUser,
        currentPassword: _ownerPasswordCtrl.text,
      );
      if (!ok) {
        _error('اسم المستخدم مستخدم أو غير صالح');
        setState(() => _loading = false);
        return;
      }
    }

    // تغيير كلمة المرور
    await service.resetPassword(
      userId: owner.id,
      newPassword: newPass,
    );

    // استهلاك كود الطوارئ إذا استُخدم
    if (_mode == 2) {
      await service.consumeRecoveryCode();
    }

    if (!mounted) return;

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تحديث بيانات الدخول بنجاح'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ==================================================
  // UI HELPERS
  // ==================================================
  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  @override
  void dispose() {
    _ownerPasswordCtrl.dispose();
    _securityQ1Ctrl.dispose();
    _securityQ2Ctrl.dispose();
    _recoveryCodeCtrl.dispose();
    _newPasswordCtrl.dispose();
    _newUsernameCtrl.dispose();
    super.dispose();
  }

  // ==================================================
  // BUILD
  // ==================================================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('استرجاع بيانات الدخول'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (!_verified) ...[
                  _modePicker(),
                  const SizedBox(height: 12),
                  if (_mode == 0) ...[
                    _sectionTitle('التحقق بكلمة مرور المالك'),
                    TextField(
                      controller: _ownerPasswordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'كلمة مرور صاحب الورشة',
                      ),
                    ),
                  ] else if (_mode == 1) ...[
                    _sectionTitle('التحقق بأسئلة الأمان'),
                    TextField(
                      controller: _securityQ1Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'ما أول اسم لورشتك بالعربية؟',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _securityQ2Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ما هو رقم هوية صاحب الورشة؟',
                      ),
                    ),
                  ] else ...[
                    _sectionTitle('التحقق بكود الطوارئ'),
                    TextField(
                      controller: _recoveryCodeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'كود الطوارئ (YA-XXXX-XXXX)',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _verify,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('تحقق'),
                    ),
                  ),
                ] else ...[
                  _sectionTitle('تحديث بيانات الدخول'),
                  TextField(
                    controller: _newUsernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم الجديد (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPasswordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('حفظ'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // ==================================================
  // WIDGETS
  // ==================================================
  Widget _modePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اختر طريقة التحقق:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('كلمة مرور المالك'),
              selected: _mode == 0,
              onSelected: (_) => setState(() => _mode = 0),
            ),
            ChoiceChip(
              label: const Text('أسئلة الأمان'),
              selected: _mode == 1,
              onSelected: (_) => setState(() => _mode = 1),
            ),
            ChoiceChip(
              label: const Text('كود الطوارئ'),
              selected: _mode == 2,
              onSelected: (_) => setState(() => _mode = 2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
