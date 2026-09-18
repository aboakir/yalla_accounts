import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, OAuthProvider;
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'cloud_auth_service.dart';
import 'supabase_identity_provider.dart';
import '../onboarding/customer_onboarding_screen.dart';

class CloudAccountLinkTile extends ConsumerWidget {
  const CloudAccountLinkTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!ref.watch(cloudConfigProvider).enabled || user == null) {
      return const SizedBox.shrink();
    }
    return ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('ربط الحساب السحابي'),
        subtitle: const Text('ربط آمن بحسابك الحالي في الورشة'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CloudAuthScreen(linkUser: user))));
  }
}

class CloudAuthScreen extends ConsumerStatefulWidget {
  const CloudAuthScreen({super.key, this.linkUser, this.onboarding = false});
  final AppUser? linkUser;
  final bool onboarding;
  @override
  ConsumerState<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends ConsumerState<CloudAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _localPassword = TextEditingController();
  late SupabaseIdentityProvider _identity;
  bool _busy = true;
  bool _create = false;
  bool _awaitingSignupCode = false;
  bool _awaitingRecoveryCode = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _identity = ref.read(supabaseIdentityProvider);
    _identity.addListener(_changed);
    _initialize();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    try {
      await _identity.beginVisit();
    } catch (_) {
      _message = 'تعذر الاتصال. يمكنك الرجوع والدخول محليًا بدون إنترنت.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on CloudAccountNotLinked {
      _message =
          'الحساب غير مرتبط بهذه الورشة. ادخل محليًا ثم اربطه من الإعدادات. للورشة الجديدة استخدم إعداد الورشة أولًا.';
    } on AuthException catch (error) {
      _message = _authErrorMessage(error);
    } catch (_) {
      _message =
          'لم تكتمل العملية. تحقق من الاتصال وبيانات الدخول، ثم أعد المحاولة. الدخول المحلي متاح.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authErrorMessage(AuthException error) {
    if (error.code == 'over_email_send_rate_limit' ||
        error.statusCode == '429') {
      return 'تم بلوغ حد إرسال رسائل التحقق مؤقتًا. انتظر قليلًا ثم أعد المحاولة. إذا كان لديك حساب بالفعل استخدم تسجيل الدخول.';
    }
    if (error.code == 'weak_password') {
      return 'كلمة المرور لا تحقق متطلبات الأمان. اختر كلمة مرور أقوى ثم أعد المحاولة.';
    }
    if (error.code == 'user_already_exists') {
      return 'تعذر إنشاء حساب جديد بهذا البريد. استخدم تسجيل الدخول أو استعادة كلمة المرور.';
    }
    if (error.code == 'invalid_credentials') {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    }
    return 'لم تكتمل عملية الحساب السحابي. تحقق من البيانات ثم أعد المحاولة.';
  }

  Future<void> _finish() async {
    if (widget.onboarding) {
      await _identity.verifiedOnboardingSession();
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const CustomerOnboardingScreen()));
      }
      return;
    }
    final user = widget.linkUser;
    if (user != null) {
      await ref.read(cloudAuthServiceProvider).link(user, _localPassword.text);
      if (mounted) Navigator.of(context).pop();
    } else {
      final local = await ref
          .read(cloudAuthServiceProvider)
          .enterLinkedWorkshop(createLocalSession: false);
      if (mounted) Navigator.of(context).pop(local);
    }
  }

  Future<void> _submit() => _run(() async {
        if (_identity.recoveryPending) {
          await _identity.updateRecoveredPassword(_password.text);
          _password.clear();
          _message = 'تم تغيير كلمة المرور السحابية. سجّل الدخول من جديد.';
          return;
        }
        if (_awaitingRecoveryCode) {
          await _identity.verifyRecoveryCode(_email.text, _code.text);
          _code.clear();
          _awaitingRecoveryCode = false;
          _message = 'تم التحقق. أدخل كلمة المرور الجديدة.';
          return;
        }
        if (_awaitingSignupCode) {
          await _identity.verifySignupCode(_email.text, _code.text);
          _code.clear();
          _awaitingSignupCode = false;
          _create = false;
          // OTP and recovery sessions share Supabase's OTP AMR. Only a fresh
          // password sign-in may proceed into normal onboarding/commercial use.
          _message = 'تم تأكيد البريد. أدخل كلمة المرور للمتابعة الآمنة.';
          return;
        }
        if (_create) {
          await _identity.signUp(_email.text, _password.text);
          _password.clear();
          _awaitingSignupCode = true;
          _message =
              'إذا كان البريد جديدًا فسيصلك رمز تحقق. إذا كان لديك حساب بالفعل، ارجع لتسجيل الدخول.';
          return;
        }
        await _identity.signIn(_email.text, _password.text);
        _password.clear();
        await _finish();
      });
  @override
  void dispose() {
    _identity.removeListener(_changed);
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _localPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(cloudConfigProvider);
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
            appBar: AppBar(
                title: Text(widget.linkUser == null
                    ? 'الدخول السحابي'
                    : 'ربط الحساب السحابي')),
            body: !config.enabled
                ? const Center(child: Text('الخدمة غير مفعّلة حاليًا.'))
                : SafeArea(
                    child: Center(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 440),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                          'تظل بيانات الورشة على جهازك، والدخول المحلي متاح دون إنترنت.'),
                                      const SizedBox(height: 20),
                                      if (!_identity.recoveryPending)
                                        TextField(
                                            controller: _email,
                                            enabled: !_busy,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            textDirection: TextDirection.ltr,
                                            autocorrect: false,
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'البريد الإلكتروني')),
                                      const SizedBox(height: 12),
                                      if (_awaitingSignupCode ||
                                          _awaitingRecoveryCode)
                                        TextField(
                                            controller: _code,
                                            enabled: !_busy,
                                            keyboardType: TextInputType.number,
                                            textDirection: TextDirection.ltr,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            decoration: const InputDecoration(
                                                labelText: 'رمز التحقق'))
                                      else
                                        TextField(
                                            controller: _password,
                                            enabled: !_busy,
                                            obscureText: true,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            decoration: InputDecoration(
                                                labelText: _identity
                                                        .recoveryPending
                                                    ? 'كلمة المرور الجديدة'
                                                    : 'كلمة المرور السحابية')),
                                      if (widget.linkUser != null &&
                                          !_identity.recoveryPending &&
                                          !_awaitingSignupCode &&
                                          !_awaitingRecoveryCode) ...[
                                        const SizedBox(height: 12),
                                        TextField(
                                            controller: _localPassword,
                                            enabled: !_busy,
                                            obscureText: true,
                                            autocorrect: false,
                                            enableSuggestions: false,
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'كلمة المرور المحلية لتأكيد الربط'))
                                      ],
                                      const SizedBox(height: 16),
                                      if (_message != null ||
                                          _identity.callbackError != null)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 12),
                                            child: Text(_message ??
                                                _identity.callbackError!)),
                                      FilledButton(
                                          onPressed: _busy ? null : _submit,
                                          child: Text(_busy
                                              ? 'جارٍ التحقق…'
                                              : _identity.recoveryPending
                                                  ? 'حفظ كلمة المرور'
                                                  : _awaitingSignupCode
                                                      ? 'تأكيد رمز التسجيل'
                                                      : _awaitingRecoveryCode
                                                          ? 'تأكيد رمز الاستعادة'
                                                          : _create
                                                              ? 'إرسال رمز التسجيل'
                                                              : 'دخول')),
                                      if (_awaitingSignupCode) ...[
                                        TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _run(() async {
                                                      await _identity
                                                          .resendSignupCode(
                                                              _email.text);
                                                      _message =
                                                          'إذا كان البريد مؤهلًا للإرسال فسيصلك رمز جديد. قد يطبق مزود البريد حدًا مؤقتًا على الإرسال.';
                                                    }),
                                            child: const Text(
                                                'إعادة إرسال رمز التسجيل')),
                                        TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => setState(() {
                                                      _awaitingSignupCode =
                                                          false;
                                                      _create = false;
                                                      _code.clear();
                                                      _message = null;
                                                    }),
                                            child: const Text(
                                                'الرجوع لتسجيل الدخول')),
                                      ],
                                      if (!_identity.recoveryPending &&
                                          !_awaitingSignupCode &&
                                          !_awaitingRecoveryCode) ...[
                                        TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _run(() async {
                                                      await _identity
                                                          .resetPassword(
                                                              _email.text);
                                                      _awaitingRecoveryCode =
                                                          true;
                                                      _code.clear();
                                                      _message =
                                                          'إن كان البريد مسجلًا سيصلك رمز استعادة. أدخله هنا على نفس الجهاز.';
                                                    }),
                                            child: const Text(
                                                'نسيت كلمة المرور السحابية')),
                                        TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => setState(
                                                    () => _create = !_create),
                                            child: Text(_create
                                                ? 'لدي حساب سحابي'
                                                : 'إنشاء حساب سحابي')),
                                        if (config.oauthEnabled) ...[
                                          OutlinedButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _run(() => _identity
                                                      .oauth(OAuthProvider
                                                          .google)),
                                              child: const Text(
                                                  'الدخول باستخدام Google')),
                                          OutlinedButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _run(() =>
                                                      _identity.oauth(
                                                          OAuthProvider.apple)),
                                              child: const Text(
                                                  'الدخول باستخدام Apple'))
                                        ],
                                        if (_identity.signedInThisVisit ||
                                            widget.onboarding)
                                          FilledButton.tonal(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _run(_finish),
                                              child: const Text(
                                                  'متابعة إلى حساب الورشة'))
                                      ],
                                    ])))))));
  }
}
