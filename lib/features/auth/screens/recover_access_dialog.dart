import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/auth/screens/reset_password_screen.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

enum RecoverMethod { securityQuestions, recoveryCode }

enum RecoverPurpose { username, password }

class RecoverAccessDialog extends ConsumerStatefulWidget {
  const RecoverAccessDialog({super.key});

  @override
  ConsumerState<RecoverAccessDialog> createState() =>
      _RecoverAccessDialogState();
}

class _RecoverAccessDialogState extends ConsumerState<RecoverAccessDialog> {
  RecoverMethod _method = RecoverMethod.recoveryCode;
  RecoverPurpose _purpose = RecoverPurpose.password;

  final _answer1Ctrl = TextEditingController();
  final _answer2Ctrl = TextEditingController();
  final _recoveryCodeCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _answer1Ctrl.dispose();
    _answer2Ctrl.dispose();
    _recoveryCodeCtrl.dispose();
    super.dispose();
  }

  Future<bool> _verifyForUsername(UserService service) async {
    if (_method == RecoverMethod.recoveryCode) {
      return service.verifyRecoveryCode(_recoveryCodeCtrl.text.trim());
    }

    return service.verifySecurityAnswers(
      answer1: _answer1Ctrl.text.trim(),
      answer2: _answer2Ctrl.text.trim(),
    );
  }

  Future<String?> _grantForPassword(UserService service) async {
    if (_method == RecoverMethod.recoveryCode) {
      return service.createResetGrantWithRecoveryCode(
        _recoveryCodeCtrl.text.trim(),
      );
    }

    return service.createResetGrantWithSecurityAnswers(
      answer1: _answer1Ctrl.text.trim(),
      answer2: _answer2Ctrl.text.trim(),
    );
  }

  Future<void> _verify() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(userServiceProvider);

      if (_purpose == RecoverPurpose.username) {
        final ok = await _verifyForUsername(service);
        if (!ok) {
          if (mounted) {
            setState(() => _error = 'بيانات الاستعادة غير صحيحة');
          }
          return;
        }

        final owner = await service.getOwner();
        if (!mounted || owner == null) return;

        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('اسم مستخدم المالك'),
            content: SelectableText(
              owner.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: owner.name),
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('نسخ'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final grant = await _grantForPassword(service);
      if (grant == null) {
        if (mounted) {
          setState(() => _error = 'بيانات الاستعادة غير صحيحة');
        }
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(
            recoveryGrantToken: grant,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر بدء الاستعادة بأمان.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('استعادة بيانات الدخول'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<RecoverPurpose>(
                  segments: const [
                    ButtonSegment(
                      value: RecoverPurpose.username,
                      icon: Icon(Icons.person_search_outlined),
                      label: Text('نسيت اسم المستخدم'),
                    ),
                    ButtonSegment(
                      value: RecoverPurpose.password,
                      icon: Icon(Icons.password),
                      label: Text('نسيت كلمة المرور'),
                    ),
                  ],
                  selected: {_purpose},
                  onSelectionChanged: _loading
                      ? null
                      : (selection) {
                          setState(() {
                            _purpose = selection.first;
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'حساب المالك:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                ToggleButtons(
                  isSelected: [
                    _method == RecoverMethod.recoveryCode,
                    _method == RecoverMethod.securityQuestions,
                  ],
                  onPressed: _loading
                      ? null
                      : (i) {
                          setState(() {
                            _method = i == 0
                                ? RecoverMethod.recoveryCode
                                : RecoverMethod.securityQuestions;
                            _error = null;
                          });
                        },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('كود الاستعادة'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('أسئلة الأمان'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_method == RecoverMethod.securityQuestions) ...[
                  TextField(
                    controller: _answer1Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'ما أول اسم لورشتك بالعربية؟',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _answer2Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'ما هو رقم هوية صاحب الورشة؟',
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _recoveryCodeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'كود الاستعادة',
                      hintText: 'YA-XXXX-XXXX',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'إذا كنت مستخدمًا عاديًا ونسيت كلمة المرور، '
                  'يستطيع مالك المنشأة تعيين كلمة مرور مؤقتة لك من إدارة المستخدمين.',
                  style: TextStyle(color: Colors.black54),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _loading ? null : _verify,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _purpose == RecoverPurpose.username
                        ? 'إظهار اسم المستخدم'
                        : 'متابعة لإعادة التعيين',
                  ),
          ),
        ],
      ),
    );
  }
}
