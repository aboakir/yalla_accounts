import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'cloud_auth_service.dart';
import 'supabase_identity_provider.dart';

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
  const CloudAuthScreen({super.key, this.linkUser});
  final AppUser? linkUser;
  @override
  ConsumerState<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends ConsumerState<CloudAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _localPassword = TextEditingController();
  late SupabaseIdentityProvider _identity;
  bool _busy = true;
  bool _create = false;
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
    } catch (_) {
      _message =
          'لم تكتمل العملية. تحقق من الاتصال وبيانات الدخول، ثم أعد المحاولة. الدخول المحلي متاح.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
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
          if (_password.text.length < 10) {
            _message = 'استخدم كلمة مرور من 10 أحرف على الأقل.';
            return;
          }
          await _identity.updateRecoveredPassword(_password.text);
          _password.clear();
          _message = 'تم تغيير كلمة المرور السحابية. سجّل الدخول من جديد.';
        } else if (_create) {
          await _identity.signUp(_email.text, _password.text);
          _password.clear();
          _message =
              'راجع بريدك لتأكيد الحساب ثم سجّل الدخول. بيانات الورشة تبقى محلية.';
          _create = false;
        } else {
          await _identity.signIn(_email.text, _password.text);
          _password.clear();
          await _finish();
        }
      });
  @override
  void dispose() {
    _identity.removeListener(_changed);
    _email.dispose();
    _password.dispose();
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
                                          !_identity.recoveryPending) ...[
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
                                                  : _create
                                                      ? 'إنشاء حساب سحابي'
                                                      : 'دخول')),
                                      if (!_identity.recoveryPending) ...[
                                        TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _run(() async {
                                                      await _identity
                                                          .resetPassword(
                                                              _email.text);
                                                      _message =
                                                          'إن كان البريد مسجلًا سيصلك رابط الاستعادة. افتحه على هذا الجهاز ثم ارجع إلى الدخول السحابي.';
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
                                        if (_identity.signedInThisVisit)
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
