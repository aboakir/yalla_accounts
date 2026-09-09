import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/device_unlock_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';
import '../services/workshop_onboarding_service.dart';
import '../widgets/verified_setup_plan.dart';

/// Entered only after owner authentication or successful first-owner bootstrap.
/// A pending marker never grants a session or relaxes the commercial gate.
class WorkshopOnboardingCompletionScreen extends ConsumerStatefulWidget {
  const WorkshopOnboardingCompletionScreen({super.key, required this.user});
  final AppUser user;
  @override
  ConsumerState<WorkshopOnboardingCompletionScreen> createState() =>
      _CompletionState();
}

class _CompletionState
    extends ConsumerState<WorkshopOnboardingCompletionScreen> {
  bool _busy = true;
  bool _backupStep = false;
  bool _pinDialogOpen = false;
  String? _error;
  CommercialAccessDecision? _access;
  CommercialSettings? _settings;
  CountryPreset? _currency;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<CommercialAccessDecision> _checkOwner() async {
    final user = widget.user;
    if (!user.isOwner || user.mustChangePassword) {
      throw StateError('سجّل الدخول بحساب مالك الورشة لإكمال الإعداد.');
    }
    final decision =
        await ref.read(commercialAccessGateServiceProvider).evaluate(user);
    if (!decision.allowed) throw StateError(decision.message);
    if (!await ref
        .read(workshopOnboardingServiceProvider)
        .needsCompletion(user)) {
      throw StateError('إعداد الورشة مكتمل. عُد إلى تسجيل الدخول.');
    }
    return decision;
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = await _checkOwner();
      final settings = await ref
          .read(workshopOnboardingServiceProvider)
          .loadCommercialSettings();
      final matches = CommercialSettingsService.presets
          .where((preset) => preset.currencyCode == settings.baseCurrencyCode);
      if (!mounted) return;
      setState(() {
        _access = access;
        _settings = settings;
        _currency = matches.isEmpty ? null : matches.first;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is StateError
      ? error.message.toString()
      : 'تعذر إكمال الإعداد بأمان. أعد المحاولة؛ بيانات حسابك محفوظة.';

  Future<void> _secureDevice() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = await _checkOwner();
      final currency = _currency;
      if (!access.readOnly && currency != null) {
        await ref
            .read(workshopOnboardingServiceProvider)
            .saveCurrency(currency);
      }
      if (!mounted) return;
      final unlock = ref.read(deviceUnlockServiceProvider);
      // Always ask for the PIN here, even if an earlier partial write left a hash.
      // Only the dialog's verified successful save advances the setup step.
      setState(() => _pinDialogOpen = true);
      final saved = await showDeviceSecuritySetupDialog(
        context: context,
        service: unlock,
        userId: widget.user.id,
      );
      if (!mounted) return;
      setState(() => _pinDialogOpen = false);
      if (!saved) {
        setState(() => _error =
            'لم يكتمل إعداد PIN. يمكنك إعادة المحاولة أو العودة للدخول.');
        return;
      }
      setState(() {
        _backupStep = true;
        _access = access;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish({required bool openBackup}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(authSessionServiceProvider);
    var sessionStarted = false;
    try {
      await _checkOwner();
      if (!await ref
          .read(deviceUnlockServiceProvider)
          .isConfiguredFor(widget.user.id)) {
        throw StateError('تعذر تأكيد حفظ PIN. أعد حماية الجهاز.');
      }
      await session.saveLoginPreferences(
          username: widget.user.name,
          rememberUsername: true,
          keepSignedIn: true);
      sessionStarted = true;
      await session.createSession(widget.user, keepSignedIn: true);
      await ref
          .read(workshopOnboardingServiceProvider)
          .complete(widget.user, openBackup: openBackup);
      if (!mounted) {
        await session.logout();
        return;
      }
      AuthorizationGuard.enableInteractiveEnforcement();
      ref.read(currentUserProvider.notifier).state = widget.user;
      final navigator = Navigator.of(context);
      navigator.pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
      if (openBackup) navigator.pushNamed(AppRoutes.settingsSecurityData);
    } catch (error) {
      if (sessionStarted) await session.logout();
      if (mounted) {
        ref.read(currentUserProvider.notifier).state = null;
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authSessionServiceProvider).logout();
      if (!mounted) return;
      ref.read(currentUserProvider.notifier).state = null;
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذر إغلاق الجلسة. أعد المحاولة.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: PopScope(
          canPop: !_busy,
          child: Scaffold(
            appBar: AppBar(
                title: const Text('إكمال إعداد الورشة'),
                automaticallyImplyLeading: false),
            body: SafeArea(
                child: Center(
                    child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          _backupStep
                              ? 'النسخ الاحتياطي'
                              : 'الخطة والعملة وحماية الجهاز',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      if (_access?.license != null)
                        VerifiedSetupPlan(license: _access!.license!),
                      if (_access?.readOnly == true)
                        const Text(
                            'الاشتراك للقراءة فقط. تبقى العملة الحالية دون تعديل ويمكنك حماية الدخول ونسخ البيانات.'),
                      if (_settings != null && !_backupStep) ...[
                        const SizedBox(height: 16),
                        if (_currency != null)
                          DropdownButtonFormField<CountryPreset>(
                            value: _currency,
                            decoration: const InputDecoration(
                                labelText: 'عملة الورشة',
                                border: OutlineInputBorder()),
                            items: CommercialSettingsService.presets
                                .map((preset) => DropdownMenuItem(
                                    value: preset,
                                    child: Text(
                                        '${preset.currencyCode} — ${preset.currencySymbol}')))
                                .toList(),
                            onChanged: _busy || _access!.readOnly
                                ? null
                                : (value) => setState(() => _currency = value),
                          )
                        else
                          Text(
                              'عملة الورشة الحالية: ${_settings!.baseCurrencyCode}'),
                        const SizedBox(height: 8),
                        const Text(
                            'اختر العملة قبل أول حركة مالية. لا يمكن تغييرها بعد تسجيل المبالغ.'),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _busy ? null : _secureDevice,
                            child: const Text('متابعة إلى إعداد PIN')),
                      ],
                      if (_backupStep) ...[
                        const SizedBox(height: 16),
                        const Text(
                            'ننصح بإنشاء نسخة احتياطية مشفرة وحفظها خارج هذا الجهاز. يمكنك إعدادها الآن أو لاحقًا من الأمان والبيانات.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed:
                                _busy ? null : () => _finish(openBackup: true),
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('فتح إعداد النسخ الاحتياطي')),
                        OutlinedButton(
                            onPressed:
                                _busy ? null : () => _finish(openBackup: false),
                            child:
                                const Text('لاحقًا — الدخول إلى لوحة التحكم')),
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _backupStep = false),
                            child: const Text('العودة إلى حماية الجهاز')),
                      ],
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      if (_access == null && !_busy)
                        TextButton(
                            onPressed: _load,
                            child: const Text('إعادة المحاولة')),
                      if (_busy && !_pinDialogOpen)
                        const Center(child: CircularProgressIndicator()),
                      TextButton(
                          onPressed: _busy ? null : _cancel,
                          child: const Text('إكمال لاحقًا والعودة للدخول')),
                    ]),
              ),
            ))),
          ),
        ),
      );
}
