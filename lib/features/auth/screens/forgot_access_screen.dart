// 📁 lib/features/auth/screens/forgot_access_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

enum ForgotMode {
  username,
  password,
  recovery,
}

class ForgotAccessScreen extends ConsumerStatefulWidget {
  const ForgotAccessScreen({super.key});

  @override
  ConsumerState<ForgotAccessScreen> createState() => _ForgotAccessScreenState();
}

class _ForgotAccessScreenState extends ConsumerState<ForgotAccessScreen> {
  ForgotMode? _mode;

  final _formKey = GlobalKey<FormState>();

  final _usernameCtrl = TextEditingController();

  // أسئلة الأمان
  final _q1Ctrl = TextEditingController();
  final _q2Ctrl = TextEditingController();
  final _q3Ctrl = TextEditingController(); // اختياري

  // كود الطوارئ
  final _recoveryCodeCtrl = TextEditingController();

  // كلمة المرور الجديدة
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _loading = false;
  bool _verified = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _q1Ctrl.dispose();
    _q2Ctrl.dispose();
    _q3Ctrl.dispose();
    _recoveryCodeCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // ===========================================================================
  // SUBMIT
  // ===========================================================================
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final userService = ref.read(userServiceProvider);
    setState(() => _loading = true);

    try {
      // ---------------------------------------------------------
      // 🆘 كود الطوارئ – مرحلة التحقق
      // ---------------------------------------------------------
      if (_mode == ForgotMode.recovery && !_verified) {
        final ok = await userService.verifyRecoveryCode(
          _recoveryCodeCtrl.text.trim(),
        );

        if (!ok) {
          _showError('كود الطوارئ غير صحيح أو مستخدم مسبقًا');
          return;
        }

        setState(() => _verified = true);
        return;
      }

      // ---------------------------------------------------------
      // 1️⃣ استرجاع اسم المستخدم
      // ---------------------------------------------------------
      if (_mode == ForgotMode.username) {
        final ok = await userService.verifySecurityAnswers(
          answer1: _q1Ctrl.text,
          answer2: _q2Ctrl.text,
        );

        if (!ok) {
          _showError('إجابات أسئلة الأمان غير صحيحة');
          return;
        }

        final owner = await userService.getOwner();
        if (owner == null) {
          _showError('لم يتم العثور على المستخدم');
          return;
        }

        _showUsernameDialog(owner.name);
        return;
      }

      // ---------------------------------------------------------
      // 2️⃣ نسيت كلمة المرور – مرحلة التحقق بالأسئلة
      // ---------------------------------------------------------
      if (_mode == ForgotMode.password && !_verified) {
        final user =
            await userService.getUserByUsername(_usernameCtrl.text.trim());
        if (user == null) {
          _showError('اسم المستخدم غير موجود');
          return;
        }

        final ok = await userService.verifySecurityAnswers(
          answer1: _q1Ctrl.text,
          answer2: _q2Ctrl.text,
        );

        if (!ok) {
          _showError('إجابات أسئلة الأمان غير صحيحة');
          return;
        }

        setState(() => _verified = true);
        return;
      }

      // ---------------------------------------------------------
      // 3️⃣ تغيير كلمة المرور (نهائي)
      // ---------------------------------------------------------
      if (_newPassCtrl.text != _confirmPassCtrl.text) {
        _showError('كلمتا المرور غير متطابقتين');
        return;
      }

      final user =
          await userService.getUserByUsername(_usernameCtrl.text.trim());
      if (user == null) {
        _showError('حدث خطأ غير متوقع');
        return;
      }

      await userService.resetPassword(
        userId: user.id,
        newPassword: _newPassCtrl.text.trim(),
      );

      if (_mode == ForgotMode.recovery) {
        await userService.consumeRecoveryCode();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم تحديث كلمة المرور بنجاح')),
      );

      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===========================================================================
  // UI
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استعادة بيانات الدخول')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildModeSelector(),
              const SizedBox(height: 24),
              if (_mode != null) _buildForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'ماذا نسيت؟',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            RadioListTile<ForgotMode>(
              value: ForgotMode.username,
              groupValue: _mode,
              title: const Text('نسيت اسم المستخدم'),
              onChanged: (v) => setState(() {
                _mode = v;
                _verified = false;
              }),
            ),
            RadioListTile<ForgotMode>(
              value: ForgotMode.password,
              groupValue: _mode,
              title: const Text('نسيت كلمة المرور'),
              onChanged: (v) => setState(() {
                _mode = v;
                _verified = false;
              }),
            ),
            RadioListTile<ForgotMode>(
              value: ForgotMode.recovery,
              groupValue: _mode,
              title: const Text('الدخول باستخدام كود الطوارئ'),
              onChanged: (v) => setState(() {
                _mode = v;
                _verified = false;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_mode == ForgotMode.password)
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _usernameCtrl,
                  enabled: !_verified,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                  validator: (v) => v == null || v.isEmpty ? 'حقل مطلوب' : null,
                ),
              if (_mode == ForgotMode.recovery && !_verified) ...[
                const SizedBox(height: 16),
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _recoveryCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'كود الطوارئ',
                    hintText: 'YA-XXXX-XXXX',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => v == null || v.isEmpty ? 'حقل مطلوب' : null,
                ),
              ],
              if (_mode != ForgotMode.recovery && !_verified) ...[
                const SizedBox(height: 16),
                _securityField(
                  controller: _q1Ctrl,
                  label: 'ما أول اسم لورشتك بالعربية؟',
                ),
                _securityField(
                  controller: _q2Ctrl,
                  label: 'ما رقم هوية صاحب الورشة؟',
                  keyboard: TextInputType.number,
                ),
                _securityField(
                  controller: _q3Ctrl,
                  label: 'ما نوع أول سيارة قمت بإصلاحها في الورشة؟ (اختياري)',
                  required: false,
                ),
              ],
              if (_verified) ...[
                const SizedBox(height: 16),
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _newPassCtrl,
                  decoration:
                      const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                  obscureText: true,
                  validator: (v) =>
                      v == null || v.length < 6 ? 'كلمة المرور قصيرة' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _confirmPassCtrl,
                  decoration:
                      const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                  obscureText: true,
                  validator: (v) => v == null || v.isEmpty ? 'حقل مطلوب' : null,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _verified ? 'حفظ كلمة المرور' : 'تحقق',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _securityField({
    required TextEditingController controller,
    required String label,
    bool required = true,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        inputFormatters: const [YallaDigitNormalizer()],
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (v) => v == null || v.isEmpty ? 'حقل مطلوب' : null
            : null,
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================
  void _showUsernameDialog(String username) {
    showDialog(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('اسم المستخدم'),
        content: SelectableText(
          username,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: username));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ اسم المستخدم')),
              );
            },
            child: const Text('نسخ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }
}
