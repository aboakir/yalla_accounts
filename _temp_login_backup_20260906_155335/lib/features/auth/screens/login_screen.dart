import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/release/release_distribution_config.dart';
import 'package:yalla_accounts/core/release/widgets/release_legal_links.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/recover_access_dialog.dart';
import 'package:yalla_accounts/features/auth/screens/register_user_screen.dart';
import 'package:yalla_accounts/features/auth/screens/reset_password_screen.dart';
import 'package:yalla_accounts/features/auth/screens/yalla_admin_account_dialogs.dart';
import 'package:yalla_accounts/features/auth/screens/yalla_control_center_screen.dart';
import 'package:yalla_accounts/features/auth/screens/device_unlock_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/services/yalla_admin_auth_service.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _rememberUsername = false;
  bool _keepSignedIn = false;
  bool _loadingPreferences = true;
  bool _canCreateFirstOwner = false;
  AppUser? _unlockUser;

  @override
  void initState() {
    super.initState();
    _loadLoginState();
  }

  Future<void> _loadLoginState() async {
    try {
      final session = ref.read(authSessionServiceProvider);
      final preferences = await session.loadLoginPreferences();
      final hasUsers = await ref.read(userServiceProvider).hasAnyUsers();
      AppUser? unlockUser;
      if (hasUsers) {
        final restored = await session.restoreSession();
        if (restored != null &&
            await ref
                .read(deviceUnlockServiceProvider)
                .isConfiguredFor(restored.id)) {
          unlockUser = restored;
        }
      }

      if (!mounted) return;
      setState(() {
        _rememberUsername = preferences.rememberUsername;
        _keepSignedIn = preferences.keepSignedIn;
        _usernameController.text = preferences.rememberedUsername ?? '';
        _canCreateFirstOwner = !hasUsers;
        _unlockUser = unlockUser;
        _loadingPreferences = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPreferences = false);
    }
  }

  Future<void> _completeCustomerAccess(AppUser user) async {
    final commercialAccess =
        await ref.read(commercialAccessGateServiceProvider).evaluate(user);
    if (!commercialAccess.allowed) {
      _error(commercialAccess.message);
      return;
    }
    ref.read(currentUserProvider.notifier).state = user;
    AuthorizationGuard.enableInteractiveEnforcement();
    if (!mounted) return;
    if (user.mustChangePassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(authenticatedUserId: user.id),
        ),
      );
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.dashboard,
      (_) => false,
    );
  }

  Future<void> _unlockWithPin(String pin) async {
    final user = _unlockUser;
    if (user == null) return;
    final ok = await ref.read(deviceUnlockServiceProvider).verifyPin(
          userId: user.id,
          pin: pin,
        );
    if (!ok) {
      _error('PIN غير صحيح');
      return;
    }
    await _completeCustomerAccess(user);
  }

  Future<void> _unlockWithBiometric() async {
    final user = _unlockUser;
    if (user == null) return;
    final ok = await ref
        .read(deviceUnlockServiceProvider)
        .authenticateBiometric(userId: user.id);
    if (!ok) {
      _error('لم ينجح التحقق من هوية الجهاز');
      return;
    }
    await _completeCustomerAccess(user);
  }

  Future<void> _usePasswordInstead() async {
    await ref.read(authSessionServiceProvider).logout();
    if (!mounted) return;
    setState(() => _unlockUser = null);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate() || _loading) return;

    setState(() => _loading = true);

    try {
      final identifier = _usernameController.text.trim();
      final password = _passwordController.text;
      String? adminUnavailableMessage;

      // One screen, two isolated identity realms. Yalla administrative
      // identities are email based and are authenticated only by the Yalla
      // server. Customer identities remain local to the organization DB.
      if (_looksLikeAdminEmail(identifier)) {
        final adminService = ref.read(yallaAdminAuthServiceProvider);
        if (adminService.isConfigured) {
          final result = await adminService.login(
            email: identifier,
            password: password,
          );

          switch (result.state) {
            case YallaAdminLoginState.authenticated:
              await _completeYallaAdminLogin(result.identity!);
              return;
            case YallaAdminLoginState.mfaRequired:
              final identity = await _completeYallaMfa(
                challengeId: result.challengeId!,
              );
              if (identity != null) {
                await _completeYallaAdminLogin(identity);
              }
              return;
            case YallaAdminLoginState.unavailable:
              adminUnavailableMessage = result.message;
              break;
            case YallaAdminLoginState.rejected:
              break;
          }
        } else {
          adminUnavailableMessage =
              'بوابة Yalla الإدارية غير مهيأة في هذا الإصدار.';
        }
      }

      final userService = ref.read(userServiceProvider);
      final AppUser? user = await userService.authenticateUser(
        identifier,
        password,
      );

      if (user == null) {
        if (adminUnavailableMessage != null &&
            _looksLikeAdminEmail(identifier)) {
          _error(
            '$adminUnavailableMessage إذا كان هذا حساب منشأة فتأكد من اسم المستخدم وكلمة المرور.',
          );
        } else {
          _error('اسم المستخدم/البريد أو كلمة المرور غير صحيحة');
        }
        return;
      }

      final commercialAccess =
          await ref.read(commercialAccessGateServiceProvider).evaluate(user);
      if (!commercialAccess.allowed) {
        _error(commercialAccess.message);
        return;
      }

      final unlock = ref.read(deviceUnlockServiceProvider);
      var deviceProtected = await unlock.isConfiguredFor(user.id);
      if (!deviceProtected && mounted) {
        deviceProtected = await showDeviceSecuritySetupDialog(
          context: context,
          service: unlock,
          userId: user.id,
        );
        if (!deviceProtected) return;
      }

      final session = ref.read(authSessionServiceProvider);
      final persistSecureSession = deviceProtected || _keepSignedIn;
      await session.saveLoginPreferences(
        username: identifier,
        rememberUsername: _rememberUsername,
        keepSignedIn: persistSecureSession,
      );
      await session.createSession(
        user,
        keepSignedIn: persistSecureSession,
      );
      await _completeCustomerAccess(user);
    } catch (_) {
      if (mounted) {
        _error('تعذر تسجيل الدخول بأمان');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool _looksLikeAdminEmail(String value) {
    final trimmed = value.trim();
    final at = trimmed.indexOf('@');
    return at > 0 && at < trimmed.length - 3;
  }

  Future<YallaAdminIdentity?> _completeYallaMfa({
    required String challengeId,
  }) async {
    final controller = TextEditingController();
    try {
      final code = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AdaptiveAlertDialog(
          title: const Text('التحقق بخطوتين — حساب Yalla'),
          content: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'رمز MFA',
              prefixIcon: Icon(Icons.security_outlined),
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                controller.text.trim(),
              ),
              child: const Text('تحقق'),
            ),
          ],
        ),
      );
      if (code == null || code.length < 6) return null;
      return await ref.read(yallaAdminAuthServiceProvider).verifyTotp(
            challengeId: challengeId,
            code: code,
          );
    } on YallaAdminAuthException catch (error) {
      _error('فشل MFA: ${error.message}');
      return null;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _completeYallaAdminLogin(YallaAdminIdentity identity) async {
    if (!identity.isYallaAdmin) {
      _error('الحساب لا يحمل صلاحية Yalla إدارية.');
      return;
    }

    // Remembering the identifier is safe. Yalla admin session secrets remain
    // memory-only and are never persisted by the customer-session service.
    await ref.read(authSessionServiceProvider).saveLoginPreferences(
          username: _usernameController.text.trim(),
          rememberUsername: _rememberUsername,
          keepSignedIn: false,
        );
    ref.read(currentUserProvider.notifier).state = null;

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => YallaControlCenterScreen(identity: identity),
      ),
      (_) => false,
    );
  }

  Future<void> _openRecovery() async {
    final identifier = _usernameController.text.trim();
    final adminService = ref.read(yallaAdminAuthServiceProvider);

    if (_looksLikeAdminEmail(identifier) && adminService.isConfigured) {
      final adminRecovery = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AdaptiveAlertDialog(
          title: const Text('نوع الحساب'),
          content: const Text(
            'هل تريد استعادة حساب Yalla الإداري أم حساب مستخدم منشأة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('حساب منشأة'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('حساب Yalla الإداري'),
            ),
          ],
        ),
      );
      if (adminRecovery == true && mounted) {
        await showYallaAdminRecoveryDialog(
          context,
          initialEmail: identifier,
        );
        return;
      }
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RecoverAccessDialog(),
    );
  }

  Future<void> _requestNewCustomerOrganization() async {
    final service = ref.read(yallaAdminAuthServiceProvider);
    if (!service.isConfigured) {
      _error('خدمة طلب الاشتراك تحتاج اتصالًا بـ Yalla Licensing Server.');
      return;
    }
    final request = await showDialog<_CustomerSignupRequest>(
      context: context,
      builder: (_) => const _CustomerSignupDialog(),
    );
    if (request == null) return;
    try {
      final response = await service.requestCustomerOnboarding(
        organizationName: request.organizationName,
        ownerName: request.ownerName,
        ownerEmail: request.ownerEmail,
        phone: request.phone,
        countryCode: request.countryCode,
      );
      if (!mounted) return;
      final requestId = response['request_id']?.toString() ?? '—';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
          title: const Text('تم إرسال طلب المنشأة'),
          content: Text(
            'رقم الطلب: $requestId\n\n'
            'الطلب الآن بانتظار اعتماد Yalla. بعد الموافقة يصدر كود تفعيل '
            'للنسخة، وبعد التفعيل تنشئ حساب مالك المنشأة بنفسك من شاشة الدخول.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
    } on YallaAdminAuthException catch (e) {
      _error('تعذر إرسال طلب المنشأة: ${e.message}');
    }
  }

  Future<void> _openYallaAdminEnrollment() async {
    final service = ref.read(yallaAdminAuthServiceProvider);
    if (!service.isConfigured) {
      _error(
        'يلزم بناء التطبيق مع YALLA_LICENSING_BASE_URL قبل إعداد حساب Yalla الإداري.',
      );
      return;
    }
    final completed = await showYallaAdminEnrollmentDialog(
      context,
      initialEmail: _looksLikeAdminEmail(_usernameController.text)
          ? _usernameController.text.trim()
          : '',
    );
    if (completed == true && mounted) {
      _error('تم إعداد الحساب. سجل الدخول الآن بالبريد وكلمة المرور وMFA.');
    }
  }

  Future<void> _openFirstOwnerSetup() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const RegisterUserScreen(),
      ),
    );

    if (!mounted) return;
    await _loadLoginState();
  }

  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlockUser = _unlockUser;
    if (unlockUser != null) {
      return DeviceUnlockScaffold(
        displayName: unlockUser.name,
        userId: unlockUser.id,
        service: ref.read(deviceUnlockServiceProvider),
        onPinUnlocked: _unlockWithPin,
        onBiometricUnlocked: _unlockWithBiometric,
        onUsePassword: _usePasswordInstead,
      );
    }

    final w = MediaQuery.of(context).size.width;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: w > 600 ? 460 : double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 25,
                    color: Colors.black.withOpacity(0.12),
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo/logo.png', height: 90),
                    const SizedBox(height: 16),
                    const Text(
                      'Yalla Accounts',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _field(
                      controller: _usernameController,
                      label: 'اسم المستخدم أو البريد الإلكتروني',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 20),
                    _field(
                      controller: _passwordController,
                      label: 'كلمة المرور',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      toggle: () {
                        setState(() => _obscure = !_obscure);
                      },
                    ),
                    const SizedBox(height: 10),
                    if (!_loadingPreferences) ...[
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _rememberUsername,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('تذكر اسم المستخدم على هذا الجهاز'),
                        onChanged: _loading
                            ? null
                            : (value) {
                                setState(
                                  () => _rememberUsername = value ?? false,
                                );
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _keepSignedIn,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('ابقني مسجلًا على هذا الجهاز'),
                        subtitle: const Text(
                          'لا يتم حفظ كلمة المرور؛ تحفظ جلسة آمنة فقط.',
                        ),
                        onChanged: _loading
                            ? null
                            : (value) {
                                setState(
                                  () => _keepSignedIn = value ?? false,
                                );
                              },
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _loading ? null : _openRecovery,
                        icon: const Icon(Icons.help_outline),
                        label: const Text(
                          'نسيت اسم المستخدم أو كلمة المرور؟',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'تسجيل الدخول',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'نفس شاشة الدخول لحسابات Yalla الإدارية وحسابات المنشآت. '
                      'البريد الإداري يُتحقق منه عبر Yalla Server؛ حسابات المنشأة تبقى ضمن قاعدة المنشأة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    if (!ReleaseDistributionConfig.isStoreDistribution) ...[
                      OutlinedButton.icon(
                        onPressed:
                            _loading ? null : _requestNewCustomerOrganization,
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('طلب إنشاء منشأة جديدة'),
                      ),
                      const SizedBox(height: 4),
                    ],
                    TextButton.icon(
                      onPressed: _loading ? null : _openYallaAdminEnrollment,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('إعداد حساب Yalla الإداري لأول مرة'),
                    ),
                    if (!_canCreateFirstOwner && !_loadingPreferences) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'إنشاء حسابات مستخدمين جديدة يتم بعد دخول مالك المنشأة '
                        'من الإعدادات ← المستخدمون والصلاحيات.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Divider(),
                    const ReleaseLegalLinks(compact: true),
                    if (_canCreateFirstOwner) ...[
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'هذه النسخة لا تحتوي حساب مالك بعد.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _openFirstOwnerSetup,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('إنشاء حساب مالك المنشأة'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    VoidCallback? toggle,
  }) {
    return TextFormField(
      inputFormatters: const [YallaDigitNormalizer()],
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      textInputAction: obscure ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: obscure ? (_) => _login() : null,
      validator: (v) {
        if (v == null || v.isEmpty) return 'حقل مطلوب';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: toggle != null
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: obscure ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                onPressed: toggle,
              )
            : null,
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _CustomerSignupRequest {
  const _CustomerSignupRequest({
    required this.organizationName,
    required this.ownerName,
    required this.ownerEmail,
    required this.phone,
    required this.countryCode,
  });

  final String organizationName;
  final String ownerName;
  final String ownerEmail;
  final String phone;
  final String countryCode;
}

class _CustomerSignupDialog extends StatefulWidget {
  const _CustomerSignupDialog();

  @override
  State<_CustomerSignupDialog> createState() => _CustomerSignupDialogState();
}

class _CustomerSignupDialogState extends State<_CustomerSignupDialog> {
  final _form = GlobalKey<FormState>();
  final _organization = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController(text: 'PS');

  @override
  void dispose() {
    _organization.dispose();
    _ownerName.dispose();
    _email.dispose();
    _phone.dispose();
    _country.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      _CustomerSignupRequest(
        organizationName: _organization.text.trim(),
        ownerName: _ownerName.text.trim(),
        ownerEmail: _email.text.trim(),
        phone: _phone.text.trim(),
        countryCode: _country.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('طلب إنشاء منشأة جديدة'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _organization,
                  decoration: const InputDecoration(labelText: 'اسم المنشأة'),
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 2 ? 'اسم المنشأة مطلوب' : null,
                ),
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _ownerName,
                  decoration:
                      const InputDecoration(labelText: 'اسم مالك المنشأة'),
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 2 ? 'اسم المالك مطلوب' : null,
                ),
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _email,
                  decoration:
                      const InputDecoration(labelText: 'البريد الإلكتروني'),
                  validator: (v) =>
                      (v?.contains('@') ?? false) ? null : 'أدخل بريدًا صحيحًا',
                ),
                TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'الهاتف')),
                TextFormField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _country,
                    decoration: const InputDecoration(
                        labelText: 'رمز الدولة مثل PS / JO / SA')),
                const SizedBox(height: 12),
                const Text(
                  'إرسال الطلب لا ينشئ كلمة مرور ولا يفعّل النسخة فورًا. يظهر الطلب في Yalla Control Center للمراجعة، وبعد الاعتماد يصدر كود تفعيل للمنشأة.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('إرسال الطلب')),
      ],
    );
  }
}
