import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_service.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/screens/register_user_screen.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

class CommercialFirstRunScreen extends StatefulWidget {
  const CommercialFirstRunScreen({
    super.key,
    this.initialExistingCustomer = false,
  });

  final bool initialExistingCustomer;

  @override
  State<CommercialFirstRunScreen> createState() =>
      _CommercialFirstRunScreenState();
}

class _CommercialFirstRunScreenState extends State<CommercialFirstRunScreen> {
  final _business = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _customerCode = TextEditingController();
  final _emailCode = TextEditingController();

  late final CommercialBackendService _service;
  bool _busy = true;
  late bool _existingCustomer;
  bool _emailVerificationRequired = false;
  String? _emailMasked;
  CommercialRegistrationState _state =
      CommercialRegistrationState.unregistered;
  String? _message;

  @override
  void initState() {
    super.initState();
    _existingCustomer = widget.initialExistingCustomer;
    _service = createCommercialBackendService()!;
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final state = await _service.localState();
      _state = state;
      if (state == CommercialRegistrationState.pending) {
        final result = await _service.refreshPendingApproval();
        if (!mounted) return;
        if (result != null) {
          _emailMasked = result.emailMasked;
          _emailVerificationRequired = !result.emailVerified;
          if (result.status == 'APPROVED') {
            await _continueAfterApproval();
            return;
          }
        }
      } else if (state == CommercialRegistrationState.registered) {
        await _continueAfterApproval();
        return;
      }
      if (mounted) {
        setState(() {
          _state = state;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _continueAfterApproval() async {
    final license = await _service.checkCurrentLicense();
    if (!mounted) return;
    if (license == null) {
      setState(() {
        _state = CommercialRegistrationState.pending;
        _busy = false;
      });
      return;
    }

    CommercialBackendRuntimeAccess.applyAccessMode(license.accessMode);

    if (license.isBlocked) {
      setState(() {
        _state = CommercialRegistrationState.registered;
        _busy = false;
        _message = 'تم إيقاف الحساب أو الجهاز. راجع إدارة Yallah.';
      });
      return;
    }

    final hasUsers = await UserService().hasAnyUsers();
    if (!mounted) return;

    if (!hasUsers) {
      if (!license.isFull) {
        setState(() {
          _state = CommercialRegistrationState.registered;
          _busy = false;
          _message =
              'يلزم اشتراك يسمح بالكتابة قبل إنشاء بيانات دخول المالك لأول مرة.';
        });
        return;
      }
      if (!license.emailVerified) {
        setState(() {
          _state = CommercialRegistrationState.registered;
          _busy = false;
          _message =
              'البريد الإلكتروني للحساب غير موثق. راجع إدارة Yallah قبل المتابعة.';
        });
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RegisterUserScreen(
            initialUsername: license.ownerName,
            initialEmail: license.email,
            initialPhone: license.phoneE164,
            initialWorkshopName: license.businessName,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  Future<void> _submit() async {
    if (_busy) return;

    if (_existingCustomer) {
      if (_customerCode.text.trim().isEmpty) {
        setState(() => _message = 'أدخل كود العميل.');
        return;
      }
    } else {
      if (_business.text.trim().length < 2 ||
          _owner.text.trim().length < 2 ||
          _phone.text.trim().length < 8) {
        setState(() => _message = 'أكمل بيانات المنشأة والمالك ورقم الهاتف.');
        return;
      }
      final email = _email.text.trim().toLowerCase();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        setState(() => _message = 'أدخل بريدًا إلكترونيًا صحيحًا.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      if (_existingCustomer) {
        await _service.requestExistingCustomerDevice(
          customerCode: _customerCode.text,
        );
        final status = await _service.refreshPendingApproval();
        if (!mounted) return;

        _emailMasked = status?.emailMasked;
        _emailVerificationRequired = status != null && !status.emailVerified;

        if (_emailVerificationRequired) {
          try {
            final sent = await _service.resendPendingEmailVerification();
            _emailMasked = sent.emailMasked ?? _emailMasked;
          } on CommercialBackendException catch (error) {
            if (error.code != 'EMAIL_CODE_COOLDOWN') rethrow;
          }
        }

        setState(() {
          _state = CommercialRegistrationState.pending;
          _busy = false;
          _message = _emailVerificationRequired
              ? 'تحقق من بريدك الإلكتروني لإكمال طلب هذا الجهاز.'
              : 'تم إرسال طلب الجهاز. الطلب بانتظار موافقة الإدارة.';
        });
      } else {
        final result = await _service.registerNewCustomer(
          businessName: _business.text,
          ownerName: _owner.text,
          phoneE164: _phone.text,
          countryCode: 'PS',
          email: _email.text,
        );
        if (!mounted) return;
        setState(() {
          _state = CommercialRegistrationState.pending;
          _busy = false;
          _emailVerificationRequired =
              result.verificationRequired && !result.emailVerified;
          _emailMasked = result.emailMasked;
          _message = _emailVerificationRequired
              ? 'أرسلنا رمز تحقق من 6 أرقام إلى بريدك الإلكتروني.'
              : 'تم إرسال الطلب وهو بانتظار موافقة إدارة Yallah.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _verifyEmail() async {
    if (_busy) return;
    final code = _emailCode.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _message = 'أدخل رمز التحقق المكوّن من 6 أرقام.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final result = await _service.verifyPendingEmail(code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _emailVerificationRequired = !result.emailVerified;
        _emailCode.clear();
        _message = result.emailVerified
            ? 'تم تأكيد البريد الإلكتروني. طلبك الآن بانتظار موافقة الإدارة.'
            : 'تعذر تأكيد البريد الإلكتروني.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _resendEmailCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _service.resendPendingEmailVerification();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _emailMasked = result.emailMasked ?? _emailMasked;
        _emailVerificationRequired = !result.emailVerified;
        _message = result.emailVerified
            ? 'البريد الإلكتروني موثق بالفعل.'
            : 'تم إرسال رمز تحقق جديد.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _refreshApproval() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _service.refreshPendingApproval();
      if (!mounted) return;

      if (result != null && !result.emailVerified) {
        setState(() {
          _busy = false;
          _emailVerificationRequired = true;
          _emailMasked = result.emailMasked;
          _message = 'يجب تأكيد البريد الإلكتروني قبل تفعيل الحساب.';
        });
        return;
      }

      if (result?.status == 'APPROVED') {
        await _continueAfterApproval();
        return;
      }

      setState(() {
        _busy = false;
        _message = result?.status == 'REJECTED'
            ? 'تم رفض طلب هذا الجهاز.'
            : 'الطلب ما زال بانتظار موافقة الإدارة.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _friendlyError(error);
        });
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is CommercialBackendException) {
      switch (error.code) {
        case 'EMAIL_REQUIRED':
        case 'INVALID_EMAIL':
          return 'أدخل بريدًا إلكترونيًا صحيحًا.';
        case 'EMAIL_CODE_INVALID':
          return 'رمز التحقق غير صحيح.';
        case 'EMAIL_CODE_EXPIRED':
          return 'انتهت صلاحية رمز التحقق. اطلب رمزًا جديدًا.';
        case 'EMAIL_CODE_LOCKED':
          return 'تم تجاوز عدد محاولات التحقق. اطلب رمزًا جديدًا.';
        case 'EMAIL_CODE_COOLDOWN':
          return 'انتظر قليلًا قبل طلب رمز جديد.';
        case 'EMAIL_DELIVERY_FAILED':
          return 'تعذر إرسال البريد حاليًا. أعد المحاولة لاحقًا.';
        case 'REGISTRATION_NOT_AVAILABLE':
          return 'هذا الرقم مرتبط بحساب قائم. استخدم خيار لدي حساب قائم.';
        case 'CUSTOMER_NOT_AVAILABLE':
          return 'كود العميل غير موجود أو الحساب غير نشط.';
        case 'DEVICE_NOT_AUTHORIZED':
          return 'هذا الجهاز غير مصرح له بالعمل.';
        default:
          return error.message;
      }
    }
    return 'تعذر الاتصال بخدمة Yallah. تحقق من الإنترنت ثم أعد المحاولة.';
  }

  @override
  void dispose() {
    _business.dispose();
    _owner.dispose();
    _phone.dispose();
    _email.dispose();
    _customerCode.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _state == CommercialRegistrationState.unregistered) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_state == CommercialRegistrationState.pending &&
        _emailVerificationRequired) {
      return _emailVerificationView();
    }
    if (_state == CommercialRegistrationState.pending) {
      return _pendingView();
    }
    if (_state == CommercialRegistrationState.registered) {
      return _registeredUnavailableView();
    }
    return _registrationView();
  }

  Widget _emailVerificationView() {
    return Scaffold(
      appBar: AppBar(title: const Text('تأكيد البريد الإلكتروني')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_read_outlined, size: 68),
                  const SizedBox(height: 18),
                  const Text(
                    'تحقق من بريدك الإلكتروني',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _emailMasked == null
                        ? 'أرسلنا رمز تحقق من 6 أرقام إلى بريدك المسجل.'
                        : 'أرسلنا رمز تحقق من 6 أرقام إلى $_emailMasked',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'لن يتم تفعيل الحساب أو الجهاز قبل تأكيد البريد.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _emailCode,
                    enabled: !_busy,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'رمز التحقق',
                      hintText: '000000',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _verifyEmail,
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(_busy ? 'جارٍ التحقق...' : 'تأكيد البريد'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _resendEmailCode,
                    child: const Text('إرسال رمز جديد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pendingView() {
    return Scaffold(
      appBar: AppBar(title: const Text('تفعيل Yallah Accounts')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'طلبك بانتظار موافقة الإدارة',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'تم تأكيد البريد. بعد الموافقة سيحصل هذا الجهاز على ترخيصه الخاص تلقائيًا.',
                  textAlign: TextAlign.center,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _refreshApproval,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('فحص الموافقة الآن'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _registeredUnavailableView() {
    return Scaffold(
      appBar: AppBar(title: const Text('ترخيص Yallah Accounts')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_outlined, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'هذا الجهاز مسجل بالفعل',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  _message ??
                      'تعذر التحقق من الترخيص الآن. اتصل بالإنترنت ثم أعد المحاولة.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await _continueAfterApproval();
                          } catch (error) {
                            if (!mounted) return;
                            setState(() {
                              _busy = false;
                              _message = _friendlyError(error);
                            });
                          }
                        },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة فحص الترخيص'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _registrationView() {
    return Scaffold(
      appBar: AppBar(title: const Text('بدء استخدام Yallah Accounts')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اربط هذا الجهاز بحساب Yallah التجاري',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('حساب جديد')),
                      ButtonSegment(value: true, label: Text('لدي حساب قائم')),
                    ],
                    selected: {_existingCustomer},
                    onSelectionChanged: _busy
                        ? null
                        : (value) =>
                            setState(() => _existingCustomer = value.first),
                  ),
                  const SizedBox(height: 20),
                  if (_existingCustomer)
                    TextField(
                      controller: _customerCode,
                      enabled: !_busy,
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(labelText: 'كود العميل'),
                    )
                  else ...[
                    TextField(
                      controller: _business,
                      enabled: !_busy,
                      decoration:
                          const InputDecoration(labelText: 'اسم المنشأة'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _owner,
                      enabled: !_busy,
                      decoration:
                          const InputDecoration(labelText: 'اسم المالك'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      enabled: !_busy,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف الدولي',
                        hintText: '+970...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        helperText:
                            'سنرسل إليه رمز التحقق واستعادة كلمة المرور.',
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy
                        ? 'جارٍ الإرسال...'
                        : _existingCustomer
                            ? 'طلب تفعيل هذا الجهاز'
                            : 'إنشاء الحساب وإرسال رمز التحقق'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
