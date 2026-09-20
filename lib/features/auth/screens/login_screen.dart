import 'dart:async';

import 'package:yalla_accounts/features/cloud_auth/cloud_auth_screen.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';
import 'package:yalla_accounts/features/onboarding/screens/workshop_onboarding_completion_screen.dart';
import 'package:yalla_accounts/features/onboarding/services/workshop_onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/design/yalla_components.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/window/desktop_window_service.dart';
import 'package:yalla_accounts/core/release/widgets/release_legal_links.dart';
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
      unawaited(configureLoginWindow());
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
    unawaited(configureMainAppWindow());
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
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 760;
    final cloudEnabled = ref.watch(cloudConfigProvider).enabled;

    InputDecoration fieldDecoration({required String labelText}) =>
        InputDecoration(
          labelText: labelText,
          isDense: isDesktop,
          labelStyle: const TextStyle(color: YallaColors.textMuted),
          floatingLabelStyle: const TextStyle(
            color: YallaColors.brandDark,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: YallaColors.surface,
          contentPadding: EdgeInsets.symmetric(
            horizontal: YallaSpacing.md,
            vertical: isDesktop ? 14 : YallaSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(YallaRadii.compact),
            borderSide: const BorderSide(color: YallaColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(YallaRadii.compact),
            borderSide: const BorderSide(color: YallaColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(YallaRadii.compact),
            borderSide: const BorderSide(
              color: YallaColors.brand,
              width: 1.6,
            ),
          ),
        );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: YallaColors.canvas,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 32 : 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 470 : 440),
                child: YallaSurfaceCard(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 34 : 24,
                    vertical: isDesktop ? 28 : 24,
                  ),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: YallaColors.successSurface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Image.asset(
                              'assets/branding/yallah_logo_horizontal.png',
                              height: isDesktop ? 44 : 62,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SizedBox(height: isDesktop ? 22 : 20),
                        Text(
                          'تسجيل الدخول',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: YallaColors.text,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        SizedBox(height: isDesktop ? 24 : 22),
                        TextField(
                          controller: _username,
                          enabled: !_loading,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: fieldDecoration(
                            labelText: 'اسم المستخدم',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _password,
                          enabled: !_loading,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: fieldDecoration(
                            labelText: 'كلمة المرور',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Checkbox(
                              value: _keepSignedIn,
                              activeColor: YallaColors.brand,
                              checkColor: YallaColors.surface,
                              side: const BorderSide(
                                color: YallaColors.textMuted,
                                width: 1.4,
                              ),
                              onChanged: _loading
                                  ? null
                                  : (value) => setState(
                                        () => _keepSignedIn = value ?? false,
                                      ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'حفظ الدخول على هذا الجهاز باستخدام PIN',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: TextStyle(
                                  color: YallaColors.textMuted,
                                  fontSize: isDesktop ? 13 : null,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: YallaColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: isDesktop ? 46 : 48,
                          child: YallaPrimaryButton(
                            label: 'دخول',
                            onPressed: _loading ? null : _login,
                            isBusy: _loading,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: YallaColors.brandDark,
                          ),
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context)
                                  .pushNamed(AppRoutes.forgotAccess),
                          child: const Text(
                            'نسيت بيانات الدخول',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (cloudEnabled || _firstOwner) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Expanded(
                                child: Divider(color: YallaColors.border),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'أو',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: YallaColors.textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(color: YallaColors.border),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (cloudEnabled)
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: YallaColors.brandDark,
                                backgroundColor: YallaColors.surface,
                                side: const BorderSide(
                                  color: YallaColors.brand,
                                  width: 1.3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    YallaRadii.compact,
                                  ),
                                ),
                              ),
                              onPressed: _loading ? null : _cloudLogin,
                              icon: const Icon(Icons.cloud_outlined),
                              label: const Text(
                                'الدخول السحابي',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        if (cloudEnabled && _firstOwner)
                          const SizedBox(height: 10),
                        if (_firstOwner)
                          SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: YallaColors.successSurface,
                                foregroundColor: YallaColors.brandDark,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    YallaRadii.compact,
                                  ),
                                ),
                              ),
                              onPressed: _loading
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const CloudAuthScreen(
                                            onboarding: true,
                                          ),
                                        ),
                                      ),
                              icon: const Icon(Icons.add_business_outlined),
                              label: const Text(
                                'إنشاء ورشة جديدة',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        if (_activationRequired) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: YallaColors.brandDark,
                            ),
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context)
                                    .pushNamed(AppRoutes.activation),
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('تفعيل هذا الجهاز'),
                          ),
                        ],
                        SizedBox(height: isDesktop ? 16 : 16),
                        if (isDesktop)
                          const Divider(
                            height: 18,
                            color: YallaColors.border,
                          ),
                        Theme(
                          data: Theme.of(context).copyWith(
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                foregroundColor: YallaColors.brandDark,
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          child: const ReleaseLegalLinks(compact: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
