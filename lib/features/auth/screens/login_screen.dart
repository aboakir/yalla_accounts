import 'package:yalla_accounts/features/cloud_auth/cloud_auth_screen.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'package:yalla_accounts/features/onboarding/screens/workshop_onboarding_completion_screen.dart';
import 'package:yalla_accounts/features/onboarding/services/workshop_onboarding_service.dart';
import 'owner_data_export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/device_unlock_screen.dart';
import 'package:yalla_accounts/features/auth/screens/reset_password_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

/// Local credentials and secure device unlock share the same commercial check.
/// No username grants a role or creates a synthetic identity.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _keepSignedIn = false;
  bool _firstOwner = false;
  bool _activationRequired = false;
  String? _error;
  AppUser? _unlockUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    // A persisted credential is not permission to open routes before unlock.
    ref.read(currentUserProvider.notifier).state = null;
    try {
      final session = ref.read(authSessionServiceProvider);
      final preferences = await session.loadLoginPreferences();
      final hasUsers = await ref.read(userServiceProvider).hasAnyUsers();
      final restored = await session.restoreSession();
      final protected = restored != null &&
          await ref
              .read(deviceUnlockServiceProvider)
              .isConfiguredFor(restored.id);
      if (!mounted) return;
      setState(() {
        _username.text = preferences.rememberedUsername ?? '';
        _keepSignedIn = preferences.keepSignedIn;
        _firstOwner = !hasUsers;
        _unlockUser = protected ? restored : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر قراءة بيانات الدخول. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _checkAccess(AppUser user) async {
    final decision =
        await ref.read(commercialAccessGateServiceProvider).evaluate(user);
    if (!mounted) return false;
    if (!decision.allowed) {
      setState(() {
        _activationRequired = decision.requiresActivation;
        _error = decision.message;
      });
      return false;
    }
    return true;
  }

  Future<bool> _resumeOnboarding(AppUser user) async {
    if (user.mustChangePassword) return false;
    if (!await ref
        .read(workshopOnboardingServiceProvider)
        .needsCompletion(user)) {
      return false;
    }
    if (!mounted) return true;
    _password.clear();
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => WorkshopOnboardingCompletionScreen(user: user),
    ));
    return true;
  }

  void _enter(AppUser user) {
    if (!mounted) return;
    AuthorizationGuard.enableInteractiveEnforcement();
    ref.read(currentUserProvider.notifier).state = user;
    if (user.mustChangePassword) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(authenticatedUserId: user.id)));
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
        user.isOwner ? AppRoutes.dashboard : AppRoutes.repairsDashboard,
        (_) => false);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _activationRequired = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر التحقق من الدخول بأمان. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() => _run(() async {
        if (_username.text.trim().isEmpty || _password.text.isEmpty) {
          setState(() => _error = 'أدخل اسم المستخدم وكلمة المرور.');
          return;
        }
        final user = await ref
            .read(userServiceProvider)
            .authenticateUser(_username.text.trim(), _password.text);
        if (!mounted) return;
        if (user == null) {
          setState(() =>
              _error = 'بيانات الدخول غير صحيحة أو الحساب غير متاح مؤقتًا.');
          return;
        }
        if (!await _checkAccess(user) || !mounted) return;
        if (await _resumeOnboarding(user) || !mounted) return;
        if (_keepSignedIn) {
          final unlock = ref.read(deviceUnlockServiceProvider);
          if (!await unlock.isConfiguredFor(user.id)) {
            if (!mounted) return;
            if (!await showDeviceSecuritySetupDialog(
                context: context, service: unlock, userId: user.id)) {
              return;
            }
          }
        }
        if (!mounted) return;
        final session = ref.read(authSessionServiceProvider);
        await session.saveLoginPreferences(
            username: user.name,
            rememberUsername: _keepSignedIn,
            keepSignedIn: _keepSignedIn);
        await session.createSession(user, keepSignedIn: _keepSignedIn);
        _password.clear();
        _enter(user);
      });

  Future<void> _unlock({String? pin}) => _run(() async {
        // Re-read the session after the screen was opened: role/revocation may change.
        final user =
            await ref.read(authSessionServiceProvider).restoreSession();
        if (!mounted) return;
        if (user == null || user.id != _unlockUser?.id) {
          setState(() {
            _unlockUser = null;
            _error = 'انتهت الجلسة. سجّل الدخول بكلمة المرور.';
          });
          return;
        }
        final unlock = ref.read(deviceUnlockServiceProvider);
        final valid = pin != null
            ? await unlock.verifyPin(userId: user.id, pin: pin)
            : await unlock.authenticateBiometric(userId: user.id);
        if (!mounted) return;
        if (!valid) {
          setState(() =>
              _error = 'لم ينجح التحقق. تحقق من الرمز أو استخدم كلمة المرور.');
          return;
        }
        if (await _checkAccess(user) && !await _resumeOnboarding(user)) {
          _enter(user);
        }
      });

  Future<void> _cloudLogin() async {
    final user = await Navigator.of(context).push<AppUser>(
        MaterialPageRoute(builder: (_) => const CloudAuthScreen()));
    if (user == null || !mounted) return;
    await _run(() async {
      if (!await _checkAccess(user) || !mounted) return;
      if (await _resumeOnboarding(user) || !mounted) return;
      if (_keepSignedIn) {
        final unlock = ref.read(deviceUnlockServiceProvider);
        if (!await unlock.isConfiguredFor(user.id)) {
          if (!mounted) return;
          if (!await showDeviceSecuritySetupDialog(
              context: context, service: unlock, userId: user.id)) return;
        }
      }
      if (!mounted) return;
      final session = ref.read(authSessionServiceProvider);
      await session.saveLoginPreferences(
          username: user.name,
          rememberUsername: _keepSignedIn,
          keepSignedIn: _keepSignedIn);
      await session.createSession(user, keepSignedIn: _keepSignedIn);
      _enter(user);
    });
  }

  Future<void> _usePassword() => _run(() async {
        await ref.read(authSessionServiceProvider).logout();
        if (mounted) setState(() => _unlockUser = null);
      });

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlockUser = _unlockUser;
    if (unlockUser != null) {
      return Stack(children: [
        DeviceUnlockScaffold(
            displayName: unlockUser.name,
            userId: unlockUser.id,
            service: ref.read(deviceUnlockServiceProvider),
            onPinUnlocked: (pin) => _unlock(pin: pin),
            onBiometricUnlocked: () => _unlock(),
            onUsePassword: _usePassword),
        if (_error != null)
          Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                  child: Material(
                      color: Colors.white,
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!,
                              textDirection: TextDirection.rtl))))),
      ]);
    }
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
            backgroundColor: AppColors.scaffoldBg,
            body: SafeArea(
                child: Center(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Image.asset('assets/logo/logo.png',
                                              height: 80),
                                          const SizedBox(height: 16),
                                          Text('تسجيل الدخول',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall),
                                          const SizedBox(height: 20),
                                          TextField(
                                              controller: _username,
                                              enabled: !_loading,
                                              autocorrect: false,
                                              textInputAction:
                                                  TextInputAction.next,
                                              decoration: const InputDecoration(
                                                  labelText: 'اسم المستخدم')),
                                          const SizedBox(height: 12),
                                          TextField(
                                              controller: _password,
                                              enabled: !_loading,
                                              obscureText: true,
                                              autocorrect: false,
                                              enableSuggestions: false,
                                              onSubmitted: (_) => _login(),
                                              decoration: const InputDecoration(
                                                  labelText: 'كلمة المرور')),
                                          CheckboxListTile(
                                              contentPadding: EdgeInsets.zero,
                                              value: _keepSignedIn,
                                              onChanged: _loading
                                                  ? null
                                                  : (v) => setState(() =>
                                                      _keepSignedIn =
                                                          v ?? false),
                                              title: const Text(
                                                  'حفظ الدخول على هذا الجهاز باستخدام PIN')),
                                          if (_error != null)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 12),
                                                child: Text(_error!,
                                                    style: const TextStyle(
                                                        color: Colors.red),
                                                    textAlign:
                                                        TextAlign.center)),
                                          FilledButton(
                                              onPressed:
                                                  _loading ? null : _login,
                                              child: _loading
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth: 2))
                                                  : const Text('دخول')),
                                          TextButton(
                                              onPressed: _loading
                                                  ? null
                                                  : () => Navigator.of(context)
                                                      .pushNamed(AppRoutes
                                                          .forgotAccess),
                                              child: const Text(
                                                  'نسيت بيانات الدخول')),
                                          TextButton(
                                              onPressed: _loading
                                                  ? null
                                                  : () => Navigator.of(context)
                                                      .push(MaterialPageRoute<
                                                              void>(
                                                          builder: (_) =>
                                                              const OwnerDataExportScreen())),
                                              child: const Text(
                                                  'تصدير نسخة بيانات الورشة')),
                                          if (ref
                                              .watch(cloudConfigProvider)
                                              .enabled)
                                            TextButton(
                                                onPressed: _loading
                                                    ? null
                                                    : _cloudLogin,
                                                child: const Text(
                                                    'الدخول السحابي')),
                                          if (_activationRequired)
                                            TextButton(
                                                onPressed: _loading
                                                    ? null
                                                    : () =>
                                                        Navigator.of(context)
                                                            .pushNamed(AppRoutes
                                                                .activation),
                                                child: const Text(
                                                    'تفعيل هذا الجهاز')),
                                          if (_firstOwner)
                                            TextButton(
                                                onPressed: _loading
                                                    ? null
                                                    : () => Navigator.of(
                                                            context)
                                                        .pushNamed(
                                                            AppRoutes.register),
                                                child: const Text(
                                                    'إعداد الورشة لأول مرة')),
                                        ])))))))));
  }
}
