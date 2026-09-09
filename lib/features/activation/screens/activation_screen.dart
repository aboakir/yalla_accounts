import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key, this.service});
  final ActivationService? service;

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _codeController = TextEditingController();
  late final ActivationService _activationService;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _activationService = widget.service ?? ActivationService();
  }

  Future<void> _activate() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _message = 'أدخل رمز التفعيل الصادر من Yalla.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final license = await _activationService.activateFirstInstallation(code);
      final existing = await ref.read(userServiceProvider).hasAnyUsers();
      if (!mounted) return;
      setState(() {
        _message = 'تم التفعيل بنجاح حتى ${_date(license.expiresAt)}.';
      });
      Navigator.of(context).pushReplacementNamed(
        existing ? AppRoutes.login : AppRoutes.register,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = _friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyMessage(Object error) {
    final text = error.toString();
    if (text.contains('not configured')) {
      return 'التفعيل غير متاح في هذه النسخة. اطلب نسخة مهيّأة من فريق Yalla.';
    }
    if (text.contains('Internet connection') || text.contains('timed out')) {
      return 'تعذر الاتصال بخادم Yalla. تحقق من الإنترنت ثم أعد المحاولة.';
    }
    if (text.contains('required before creating First Owner')) {
      return 'يجب إكمال التفعيل قبل إنشاء مالك المنشأة.';
    }
    return 'تعذر إكمال التفعيل. تحقق من الرمز والاتصال ثم أعد المحاولة.';
  }

  static String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = _activationService.isConfigured;
    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('تفعيل Yalla Accounts'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      configured
                          ? Icons.verified_user_outlined
                          : Icons.cloud_off,
                      size: 64,
                      color: configured ? AppColors.primary : Colors.orange,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'التفعيل الأول يتطلب اتصالاً بالإنترنت',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'أدخل رمز التفعيل المخصص لمنشأتك. سيتم ربط الترخيص بهذا الجهاز بعد تحقق خادم Yalla من الاشتراك والجهاز.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _codeController,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'رمز التفعيل',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                      onSubmitted: (_) {
                        if (!_busy) _activate();
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy || !configured ? null : _activate,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_outlined),
                      label: Text(_busy ? 'جارٍ التحقق...' : 'تفعيل الجهاز'),
                    ),
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context)
                                .pushNamedAndRemoveUntil(
                                    AppRoutes.login, (_) => false),
                        child: const Text('العودة إلى تسجيل الدخول')),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (!configured) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'التفعيل غير متاح في هذه النسخة. تواصل مع فريق Yalla للحصول على نسخة مهيّأة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black45),
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
}
