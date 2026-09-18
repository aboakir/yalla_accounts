import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/auth/services/device_unlock_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class DeviceUnlockScaffold extends StatefulWidget {
  const DeviceUnlockScaffold({
    super.key,
    required this.displayName,
    required this.userId,
    required this.service,
    required this.onPinUnlocked,
    required this.onBiometricUnlocked,
    required this.onUsePassword,
  });

  final String displayName;
  final String userId;
  final DeviceUnlockService service;
  final Future<void> Function(String pin) onPinUnlocked;
  final Future<void> Function() onBiometricUnlocked;
  final Future<void> Function() onUsePassword;

  @override
  State<DeviceUnlockScaffold> createState() => _DeviceUnlockScaffoldState();
}

class _DeviceUnlockScaffoldState extends State<DeviceUnlockScaffold> {
  final _pin = TextEditingController();
  bool _busy = false;
  bool _biometric = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.service.biometricEnabledFor(widget.userId);
    if (mounted) setState(() => _biometric = enabled);
  }

  Future<void> _submitPin() async {
    if (_busy || !RegExp(r'^\d{4,6}$').hasMatch(_pin.text)) {
      setState(() => _error = 'أدخل PIN من 4 إلى 6 أرقام.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.onPinUnlocked(_pin.text);
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/branding/yallah_logo_horizontal.png',
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 18),
                        Text('مرحبًا، ${widget.displayName}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        const Text('افتح الورشة بسرعة وأمان على هذا الجهاز.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        TextField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _pin,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          obscureText: true,
                          maxLength: 6,
                          onSubmitted: (_) => _submitPin(),
                          decoration: InputDecoration(
                            labelText: 'PIN',
                            counterText: '',
                            errorText: _error,
                            prefixIcon: const Icon(Icons.pin_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _submitPin,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('فتح التطبيق'),
                          ),
                        ),
                        if (_biometric) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _busy ? null : widget.onBiometricUnlocked,
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('استخدام البصمة / Face ID'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : widget.onUsePassword,
                          child: const Text('الدخول بكلمة المرور بدلًا من ذلك'),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                            'يعمل فتح الجهاز محليًا عند انقطاع الإنترنت، مع بقاء صلاحية الترخيص المحلي هي المرجع.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54)),
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

Future<bool> showDeviceSecuritySetupDialog({
  required BuildContext context,
  required DeviceUnlockService service,
  required String userId,
}) async {
  final available = await service.biometricAvailable();
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeviceSecuritySetupDialog(
          service: service,
          userId: userId,
          biometricAvailable: available,
        ),
      ) ==
      true;
}

class _DeviceSecuritySetupDialog extends StatefulWidget {
  const _DeviceSecuritySetupDialog(
      {required this.service,
      required this.userId,
      required this.biometricAvailable});
  final DeviceUnlockService service;
  final String userId;
  final bool biometricAvailable;
  @override
  State<_DeviceSecuritySetupDialog> createState() => _SecuritySetupState();
}

class _SecuritySetupState extends State<_DeviceSecuritySetupDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _biometric = false;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy) return;
    final value = _pin.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(value) ||
        value != _confirm.text.trim()) {
      setState(() => _error = 'تحقق من PIN وتأكيده.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.configure(
          userId: widget.userId, pin: value, enableBiometric: _biometric);
      if (!await widget.service.isConfiguredFor(widget.userId) ||
          !await widget.service.verifyPin(userId: widget.userId, pin: value)) {
        throw StateError('PIN verification after save failed.');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر حفظ حماية الجهاز بأمان. أعد المحاولة أو ألغِ الإعداد.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AdaptiveAlertDialog(
            title: const Text('حماية هذا الجهاز'),
            content: SizedBox(
                width: 420,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'أنشئ PIN سريعًا. سيبقى تسجيل الدخول محفوظًا داخل التخزين الآمن.'),
                  const SizedBox(height: 16),
                  TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _pin,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          labelText: 'PIN من 4 إلى 6 أرقام', counterText: '')),
                  TextField(
                      inputFormatters: const [YallaDigitNormalizer()],
                      controller: _confirm,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          labelText: 'تأكيد PIN', counterText: '')),
                  if (widget.biometricAvailable)
                    SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _biometric,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _biometric = value),
                        title: const Text('تفعيل البصمة / Face ID')),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ])),
            actions: [
              TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ والمتابعة')),
            ],
          ),
        ),
      );
}
