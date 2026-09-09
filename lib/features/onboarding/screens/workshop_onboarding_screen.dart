import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/screens/register_user_screen.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import '../services/workshop_onboarding_service.dart';
import '../widgets/verified_setup_plan.dart';

/// Safe entry for both new installations and workshops that already have users.
class WorkshopOnboardingScreen extends ConsumerStatefulWidget {
  const WorkshopOnboardingScreen({super.key});
  @override
  ConsumerState<WorkshopOnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<WorkshopOnboardingScreen> {
  bool _busy = true;
  bool _existing = false;
  VerifiedLicense? _license;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = await ref.read(userServiceProvider).hasAnyUsers();
      final license =
          await ref.read(workshopOnboardingServiceProvider).loadSetupLicense();
      if (mounted) {
        setState(() {
          _existing = existing;
          _license = license;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر التحقق من إعداد الورشة. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('إعداد الورشة')),
          body: SafeArea(
              child: Center(
                  child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('أهلًا بك في Yalla Accounts',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    const Text(
                        'التفعيل، حساب المالك، بيانات الورشة، حماية الجهاز ثم النسخ الاحتياطي.'),
                    const SizedBox(height: 20),
                    if (_busy)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null) ...[
                      Text(_error!),
                      TextButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة')),
                    ] else ...[
                      if (_existing) ...[
                        const Text(
                            'توجد ورشة على هذا التثبيت. سجّل الدخول بحسابك الحالي لإكمال الإعداد أو متابعة العمل.'),
                        FilledButton(
                            onPressed: () => Navigator.of(context)
                                .pushNamedAndRemoveUntil(
                                    AppRoutes.login, (_) => false),
                            child: const Text('الدخول إلى الورشة الحالية')),
                      ],
                      if (_license != null)
                        VerifiedSetupPlan(license: _license!),
                      if (!_existing && _license != null)
                        FilledButton(
                            onPressed: () => Navigator.of(context)
                                .pushReplacement(MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const RegisterUserScreen())),
                            child: const Text('متابعة إنشاء حساب المالك')),
                      if (_license == null) ...[
                        const Text(
                            'يلزم رمز تفعيل صالح لهذا الجهاز. التفعيل الأول يحتاج اتصالًا بالإنترنت.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: () => Navigator.of(context)
                                .pushNamed(AppRoutes.activation),
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('بدء تفعيل الجهاز')),
                      ],
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: () => Navigator.of(context)
                              .pushNamedAndRemoveUntil(
                                  AppRoutes.login, (_) => false),
                          child: const Text('العودة إلى تسجيل الدخول')),
                    ],
                  ]),
            ),
          ))),
        ),
      );
}
