import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/services/yalla_admin_auth_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class RegisterUserScreen extends ConsumerStatefulWidget {
  const RegisterUserScreen({super.key});

  @override
  ConsumerState<RegisterUserScreen> createState() => _RegisterUserScreenState();
}

class _RegisterUserScreenState extends ConsumerState<RegisterUserScreen> {
  final _ownerName = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _workshopName = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _street = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();

  int _step = 0;
  bool _loading = false;
  bool _obscure = true;
  bool _enableBiometric = false;
  bool _biometricAvailable = false;
  bool _otpBusy = false;
  bool _phoneVerified = false;
  String? _phoneChallengeId;
  String? _phoneVerificationToken;
  String? _verifiedPhone;
  String _country = 'فلسطين';
  String _province = 'الضفة الغربية';
  XFile? _logo;

  static const _countries = ['فلسطين', 'الأردن', 'مصر', 'سوريا'];
  static const _provinces = <String, List<String>>{
    'فلسطين': ['الضفة الغربية', 'قطاع غزة'],
    'الأردن': ['عمان', 'إربد'],
    'مصر': ['القاهرة', 'الإسكندرية'],
    'سوريا': ['دمشق', 'حلب'],
  };

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
  }

  Future<void> _loadBiometrics() async {
    final value =
        await ref.read(deviceUnlockServiceProvider).biometricAvailable();
    if (mounted) setState(() => _biometricAvailable = value);
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        if (_ownerName.text.trim().length < 2) return _fail('أدخل اسم المالك.');
        if (_password.text.length < 10 ||
            !RegExp(r'\d').hasMatch(_password.text)) {
          return _fail(
              'كلمة المرور يجب أن تكون 10 أحرف على الأقل وتحتوي رقمًا.');
        }
        if (_password.text != _confirmPassword.text)
          return _fail('كلمتا المرور غير متطابقتين.');
        return true;
      case 1:
        final phone = _normalizedPhone();
        if (phone.length < 8) return _fail('أدخل رقم هاتف صحيحًا.');
        if (!_phoneVerified || _verifiedPhone != phone) {
          return _fail('تحقق من رقم الهاتف بواسطة رمز SMS أولًا.');
        }
        return true;
      case 2:
        if (_workshopName.text.trim().length < 2)
          return _fail('أدخل اسم الورشة.');
        if (_city.text.trim().isEmpty) return _fail('أدخل المدينة.');
        return true;
      case 3:
        if (!RegExp(r'^\d{4,6}$').hasMatch(_pin.text))
          return _fail('PIN يجب أن يكون من 4 إلى 6 أرقام.');
        if (_pin.text != _confirmPin.text) return _fail('تأكيد PIN غير مطابق.');
        return true;
    }
    return false;
  }

  bool _fail(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    return false;
  }

  String _normalizedPhone() =>
      _phone.text.replaceAll(RegExp(r'[\s\-\(\)]'), '');

  void _resetPhoneVerification() {
    if (_phoneVerified ||
        _phoneChallengeId != null ||
        _phoneVerificationToken != null) {
      setState(() {
        _phoneVerified = false;
        _phoneChallengeId = null;
        _phoneVerificationToken = null;
        _verifiedPhone = null;
        _otp.clear();
      });
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _normalizedPhone();
    if (phone.length < 8) {
      _fail('أدخل رقم هاتف صحيحًا أولًا.');
      return;
    }
    if (_otpBusy) return;
    setState(() => _otpBusy = true);
    try {
      final service = ref.read(yallaAdminAuthServiceProvider);
      if (!service.isConfigured) {
        throw const YallaAdminAuthException(
          'خادم Yalla Licensing غير مهيأ في هذه النسخة.',
        );
      }
      final challenge =
          await service.startCustomerPhoneVerification(phone: phone);
      if (!mounted) return;
      setState(() {
        _phoneChallengeId = challenge.challengeId;
        _phoneVerificationToken = null;
        _verifiedPhone = null;
        _phoneVerified = false;
        _otp.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إرسال رمز التحقق. صالح لمدة '
            '${(challenge.expiresInSeconds / 60).ceil()} دقائق.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) _fail('تعذر إرسال رمز التحقق: $e');
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final challengeId = _phoneChallengeId;
    final phone = _normalizedPhone();
    final code = _otp.text.trim();
    if (challengeId == null) {
      _fail('اطلب رمز تحقق أولًا.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _fail('أدخل رمز التحقق المكوّن من 6 أرقام.');
      return;
    }
    if (_otpBusy) return;
    setState(() => _otpBusy = true);
    try {
      final verified =
          await ref.read(yallaAdminAuthServiceProvider).verifyCustomerPhoneOtp(
                challengeId: challengeId,
                code: code,
              );
      if (!mounted) return;
      if (verified.phone != phone) {
        throw const YallaAdminAuthException(
          'رقم الهاتف الذي تم التحقق منه لا يطابق الرقم الحالي.',
        );
      }
      setState(() {
        _phoneVerificationToken = verified.verificationToken;
        _verifiedPhone = verified.phone;
        _phoneVerified = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم التحقق من رقم الهاتف بنجاح.')),
      );
    } catch (e) {
      if (mounted) _fail('رمز التحقق غير صحيح أو انتهت صلاحيته: $e');
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  Future<void> _next() async {
    if (!_validateCurrentStep()) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    if (_loading || !_validateCurrentStep()) return;
    setState(() => _loading = true);
    try {
      final userService = ref.read(userServiceProvider);
      if (await userService.hasAnyUsers()) {
        _fail('تم إعداد مالك المنشأة مسبقًا.');
        if (mounted)
          Navigator.of(context).pushReplacementNamed(AppRoutes.login);
        return;
      }

      final challengeId = _phoneChallengeId;
      final verificationToken = _phoneVerificationToken;
      final verifiedPhone = _verifiedPhone;
      if (!_phoneVerified ||
          challengeId == null ||
          verificationToken == null ||
          verifiedPhone == null ||
          verifiedPhone != _normalizedPhone()) {
        throw const YallaAdminAuthException(
          'Server-authoritative phone verification is required.',
        );
      }
      await ref
          .read(yallaAdminAuthServiceProvider)
          .consumeCustomerPhoneVerification(
            challengeId: challengeId,
            phone: verifiedPhone,
            verificationToken: verificationToken,
          );
      _phoneVerificationToken = null;

      final result = await userService.bootstrapFirstOwner(
        FirstOwnerBootstrapRequest(
          ownerName: _ownerName.text.trim(),
          email: _ownerEmail.text.trim(),
          password: _password.text,
          workshopName: _workshopName.text.trim(),
          workshopAddress: _address.text.trim(),
          country: _country,
          province: _province,
          city: _city.text.trim(),
          street: _street.text.trim(),
          phone: _phone.text.trim(),
          logoPath: _logo?.path,
        ),
      );

      await ref.read(deviceUnlockServiceProvider).configure(
            userId: result.ownerUserId,
            pin: _pin.text,
            enableBiometric: _enableBiometric,
          );

      final AppUser? user = await userService.getUserById(result.ownerUserId);
      if (user == null) throw StateError('تعذر قراءة حساب المالك بعد إنشائه.');
      final access =
          await ref.read(commercialAccessGateServiceProvider).evaluate(user);
      if (!access.allowed) throw StateError(access.message);

      final session = ref.read(authSessionServiceProvider);
      await session.saveLoginPreferences(
        username: user.name,
        rememberUsername: true,
        keepSignedIn: true,
      );
      await session.createSession(user, keepSignedIn: true);
      ref.read(currentUserProvider.notifier).state = user;

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AdaptiveAlertDialog(
          title: const Text('تم تأسيس الورشة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('احفظ رمز الاستعادة في مكان آمن. يظهر مرة واحدة فقط.'),
              const SizedBox(height: 12),
              SelectableText(result.recoveryCode,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('حفظته'))
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
    } catch (e) {
      if (mounted) _fail('تعذر إكمال تأسيس الورشة: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null && mounted) setState(() => _logo = file);
  }

  @override
  void dispose() {
    for (final c in [
      _ownerName,
      _ownerEmail,
      _password,
      _confirmPassword,
      _phone,
      _workshopName,
      _address,
      _city,
      _street,
      _pin,
      _confirmPin
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('تأسيس الورشة'),
          centerTitle: false,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  _ProgressHeader(step: _step),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isPhone ? 16 : 24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                            key: ValueKey(_step), child: _stepBody()),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          isPhone ? 16 : 24, 8, isPhone ? 16 : 24, 16),
                      child: AdaptiveRow(
                        children: [
                          if (_step > 0)
                            Expanded(
                                child: OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () => setState(() => _step--),
                                    child: const Text('السابق'))),
                          if (_step > 0) const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _loading ? null : _next,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Text(_step == 3
                                      ? 'ابدأ استخدام Yalla Accounts'
                                      : 'التالي'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _CardSection(
          title: '1/4 — حساب المالك',
          subtitle:
              'إعداد حساب مالك المنشأة — بيانات الدخول الأساسية للمالك الأول.',
          children: [
            _field(_ownerName, 'اسم المالك', Icons.person_outline),
            _field(_ownerEmail, 'البريد الإلكتروني (اختياري)',
                Icons.email_outlined,
                keyboard: TextInputType.emailAddress),
            _field(_password, 'كلمة المرور', Icons.lock_outline,
                obscure: _obscure,
                suffix: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility))),
            _field(_confirmPassword, 'تأكيد كلمة المرور', Icons.lock_reset,
                obscure: true),
          ],
        );
      case 1:
        return _CardSection(
          title: '2/4 — التحقق من الهاتف',
          subtitle:
              'يرسل خادم Yalla الموثوق رمز SMS. لا يتم إنشاء الرمز أو حفظه داخل التطبيق.',
          children: [
            _field(
              _phone,
              'رقم الهاتف',
              Icons.phone_outlined,
              keyboard: TextInputType.phone,
              onChanged: (_) => _resetPhoneVerification(),
            ),
            FilledButton.icon(
              onPressed: _otpBusy ? null : _sendPhoneOtp,
              icon: const Icon(Icons.sms_outlined),
              label: Text(_phoneChallengeId == null
                  ? 'إرسال رمز SMS'
                  : 'إعادة إرسال رمز SMS'),
            ),
            if (_phoneChallengeId != null) ...[
              const SizedBox(height: 12),
              _field(
                _otp,
                'رمز التحقق — 6 أرقام',
                Icons.password_outlined,
                keyboard: TextInputType.number,
              ),
              OutlinedButton.icon(
                onPressed: _otpBusy || _phoneVerified ? null : _verifyPhoneOtp,
                icon: Icon(_phoneVerified
                    ? Icons.verified_outlined
                    : Icons.verified_user_outlined),
                label: Text(
                    _phoneVerified ? 'تم التحقق من الهاتف' : 'تحقق من الرمز'),
              ),
            ],
            const SizedBox(height: 12),
            _InfoBanner(
              text: _phoneVerified
                  ? 'رقم الهاتف موثق من الخادم وسيتم استهلاك إثبات التحقق مرة واحدة عند تأسيس الورشة.'
                  : 'رمز OTP لا يعود في استجابة API ولا يُحفظ في FlutterSecureStorage أو SQLite.',
            ),
          ],
        );
      case 2:
        return _CardSection(
          title: '3/4 — بيانات الورشة',
          subtitle: 'المعلومات الأساسية التي ستظهر داخل ملفات وتقارير الورشة.',
          children: [
            _field(_workshopName, 'اسم الورشة', Icons.storefront_outlined),
            DropdownButtonFormField<String>(
                value: _country,
                decoration: const InputDecoration(
                    labelText: 'الدولة', border: OutlineInputBorder()),
                items: _countries
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _country = v;
                    _province = _provinces[v]!.first;
                  });
                }),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                value: _province,
                decoration: const InputDecoration(
                    labelText: 'المنطقة', border: OutlineInputBorder()),
                items: (_provinces[_country] ?? const <String>[])
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _province = v);
                }),
            _field(_city, 'المدينة', Icons.location_city_outlined),
            _field(_address, 'العنوان', Icons.place_outlined),
            _field(_street, 'الشارع (اختياري)', Icons.signpost_outlined),
            OutlinedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.image_outlined),
                label: Text(_logo == null
                    ? 'إضافة شعار الورشة (اختياري)'
                    : 'تم اختيار الشعار — تغييره')),
          ],
        );
      default:
        return _CardSection(
          title: '4/4 — حماية الجهاز',
          subtitle: 'PIN محلي مشفّر مع بصمة / Face ID عند توفرها.',
          children: [
            _field(_pin, 'PIN من 4 إلى 6 أرقام', Icons.pin_outlined,
                keyboard: TextInputType.number, obscure: true),
            _field(_confirmPin, 'تأكيد PIN', Icons.verified_user_outlined,
                keyboard: TextInputType.number, obscure: true),
            if (_biometricAvailable)
              SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _enableBiometric,
                  onChanged: (v) => setState(() => _enableBiometric = v),
                  title: const Text('تفعيل البصمة / Face ID'),
                  subtitle: const Text('يستخدم التحقق المحلي الآمن للجهاز.')),
            const _InfoBanner(
                text:
                    'بعد الإعداد، يمكن للمستخدم المسجل سابقًا فتح التطبيق محليًا عند انقطاع الإنترنت طالما الجلسة والترخيص المحلي ما زالا صالحين.'),
          ],
        );
    }
  }

  Widget _field(TextEditingController controller, String label, IconData icon,
      {TextInputType? keyboard,
      bool obscure = false,
      Widget? suffix,
      ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        inputFormatters: const [YallaDigitNormalizer()],
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        onChanged: onChanged,
        decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: suffix,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: AdaptiveRow(
        children: List.generate(
            4,
            (index) => Expanded(
                child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                        color:
                            index <= step ? AppColors.primary : Colors.black12,
                        borderRadius: BorderRadius.circular(99))))),
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection(
      {required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          ...children
        ]),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(.07),
          borderRadius: BorderRadius.circular(14)),
      child:
          AdaptiveRow(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13)))
      ]));
}
