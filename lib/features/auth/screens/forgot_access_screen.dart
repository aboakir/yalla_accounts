import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_environment.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/screens/recover_access_dialog.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

class ForgotAccessScreen extends StatefulWidget {
  const ForgotAccessScreen({super.key});

  @override
  State<ForgotAccessScreen> createState() => _ForgotAccessScreenState();
}

class _ForgotAccessScreenState extends State<ForgotAccessScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _dialogOpen = false;
  bool _busy = false;
  int _step = 0;
  PasswordResetChallengeResult? _challenge;
  String? _resetGrant;
  String? _emailMasked;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (!CommercialBackendEnvironment.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openLegacyRecovery());
    }
  }

  Future<void> _openLegacyRecovery() async {
    if (!mounted || _dialogOpen) return;
    setState(() => _dialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => const RecoverAccessDialog(),
      );
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _requestEmailReset() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final challenge =
          await createCommercialBackendService()!.requestPasswordReset();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _challenge = challenge;
        _emailMasked = challenge.emailMasked;
        _step = 1;
        _message = 'تم إرسال رمز استعادة من 6 أرقام.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_busy || _challenge == null) return;
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _message = 'أدخل رمز الاستعادة المكوّن من 6 أرقام.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final grant = await createCommercialBackendService()!.verifyPasswordReset(
        challengeId: _challenge!.challengeId,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _resetGrant = grant.resetGrant;
        _step = 2;
        _message = 'تم التحقق من البريد. اختر كلمة مرور جديدة.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _saveNewPassword() async {
    if (_busy || _resetGrant == null) return;
    if (_password.text != _confirmPassword.text) {
      setState(() => _message = 'كلمتا المرور غير متطابقتين.');
      return;
    }
    final policyError = UserService.validatePasswordPolicy(_password.text);
    if (policyError != null) {
      setState(() => _message = policyError);
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final authorized = await createCommercialBackendService()!
          .consumePasswordReset(_resetGrant!);
      if (!authorized) {
        throw const CommercialBackendException(
          'RESET_NOT_AUTHORIZED',
          'Password reset was not authorized.',
        );
      }

      final changed = await UserService().resetOwnerPasswordAfterVerifiedEmail(
        newPassword: _password.text,
        backendAuthorized: true,
      );
      if (!changed) {
        throw const CommercialBackendException(
          'LOCAL_PASSWORD_RESET_FAILED',
          'Local password could not be reset.',
        );
      }

      _password.clear();
      _confirmPassword.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تغيير كلمة المرور بنجاح. سجّل الدخول بكلمتك الجديدة.'),
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.login,
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is CommercialBackendException) {
      switch (error.code) {
        case 'VERIFIED_EMAIL_REQUIRED':
          return 'لا يوجد بريد إلكتروني موثق لهذا الحساب. تواصل مع دعم Yallah.';
        case 'PASSWORD_RESET_CODE_INVALID':
          return 'رمز الاستعادة غير صحيح.';
        case 'PASSWORD_RESET_EXPIRED':
          return 'انتهت صلاحية رمز الاستعادة. اطلب رمزًا جديدًا.';
        case 'PASSWORD_RESET_LOCKED':
          return 'تم تجاوز عدد المحاولات. اطلب رمزًا جديدًا.';
        case 'RESET_GRANT_EXPIRED':
          return 'انتهت مهلة تغيير كلمة المرور. ابدأ الاستعادة من جديد.';
        case 'DEVICE_NOT_AUTHORIZED':
          return 'استعادة كلمة المرور متاحة فقط من جهاز Yallah مرخص.';
        case 'EMAIL_DELIVERY_FAILED':
          return 'تعذر إرسال البريد حاليًا. أعد المحاولة لاحقًا.';
        default:
          return error.message;
      }
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? 'كلمة المرور غير مقبولة.';
    }
    return 'تعذر إكمال الاستعادة بأمان. أعد المحاولة.';
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!CommercialBackendEnvironment.enabled) {
      return _legacyView();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استعادة كلمة المرور')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _commercialStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _commercialStep() {
    if (_step == 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 64),
          const SizedBox(height: 16),
          const Text(
            'استعادة آمنة عبر البريد الموثق',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'سنرسل رمزًا مؤقتًا إلى البريد الإلكتروني الموثق للحساب المرتبط بهذا الجهاز. لا نرسل كلمة المرور عبر البريد.',
            textAlign: TextAlign.center,
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Text(_message!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy ? null : _requestEmailReset,
            icon: const Icon(Icons.email_outlined),
            label: Text(_busy ? 'جارٍ الإرسال...' : 'إرسال رمز الاستعادة'),
          ),
          const SizedBox(height: 8),
          _backButton(),
        ],
      );
    }

    if (_step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.password_rounded, size: 60),
          const SizedBox(height: 14),
          const Text(
            'أدخل رمز الاستعادة',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _emailMasked == null
                ? 'تحقق من بريدك الإلكتروني.'
                : 'أرسلنا الرمز إلى $_emailMasked',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            enabled: !_busy,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'رمز الاستعادة',
              hintText: '000000',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _verifyCode,
            child: Text(_busy ? 'جارٍ التحقق...' : 'تحقق من الرمز'),
          ),
          TextButton(
            onPressed: _busy ? null : _requestEmailReset,
            child: const Text('إرسال رمز جديد'),
          ),
          _backButton(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset_rounded, size: 60),
        const SizedBox(height: 14),
        const Text(
          'أنشئ كلمة مرور جديدة',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'يجب أن تتكون من 10 أحرف على الأقل وتحتوي حروفًا وأرقامًا.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة المرور الجديدة',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPassword,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'تأكيد كلمة المرور',
            border: OutlineInputBorder(),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _saveNewPassword,
          child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ كلمة المرور الجديدة'),
        ),
        _backButton(),
      ],
    );
  }

  Widget _backButton() {
    return TextButton(
      onPressed: _busy
          ? null
          : () => Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.login,
                (_) => false,
              ),
      child: const Text('العودة إلى تسجيل الدخول'),
    );
  }

  Widget _legacyView() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('استعادة بيانات الدخول')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_reset, size: 54),
                    const SizedBox(height: 16),
                    const Text(
                      'يمكن استعادة بيانات الدخول باستخدام أدوات الاستعادة المحلية في هذا الإصدار.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _dialogOpen ? null : _openLegacyRecovery,
                      icon: const Icon(Icons.security_outlined),
                      label: const Text('بدء الاستعادة الآمنة'),
                    ),
                    const SizedBox(height: 12),
                    _backButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
