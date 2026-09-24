import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class CommercialFirstRunScreen extends StatefulWidget {
  const CommercialFirstRunScreen({super.key});

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

  late final CommercialBackendService _service;
  bool _busy = true;
  bool _existingCustomer = false;
  CommercialRegistrationState _state = CommercialRegistrationState.unregistered;
  String? _message;

  @override
  void initState() {
    super.initState();
    _service = createCommercialBackendService()!;
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final state = await _service.localState();
      _state = state;
      if (state == CommercialRegistrationState.pending) {
        final result = await _service.refreshPendingApproval();
        if (result?.status == 'APPROVED') {
          await _continueAfterApproval();
          return;
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
    if (license.isBlocked) {
      setState(() {
        _state = CommercialRegistrationState.registered;
        _busy = false;
        _message = 'تم إيقاف الحساب أو الجهاز. راجع إدارة يلا.';
      });
      return;
    }
    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_existingCustomer) {
        await _service.requestExistingCustomerDevice(
          customerCode: _customerCode.text,
        );
      } else {
        await _service.registerNewCustomer(
          businessName: _business.text,
          ownerName: _owner.text,
          phoneE164: _phone.text,
          countryCode: 'PS',
          email: _email.text.trim().isEmpty ? null : _email.text,
        );
      }
      if (!mounted) return;
      setState(() {
        _state = CommercialRegistrationState.pending;
        _busy = false;
        _message = 'تم إرسال الطلب. سيعمل هذا الجهاز بعد موافقة إدارة يلا.';
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
      if (result?.status == 'APPROVED') {
        await _continueAfterApproval();
        return;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _message = result?.status == 'REJECTED'
              ? 'تم رفض طلب هذا الجهاز.'
              : 'الطلب ما زال بانتظار الموافقة.';
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

  String _friendlyError(Object error) {
    if (error is CommercialBackendException) {
      switch (error.code) {
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
    return 'تعذر الاتصال بخدمة يلا. تحقق من الإنترنت ثم أعد المحاولة.';
  }

  @override
  void dispose() {
    _business.dispose();
    _owner.dispose();
    _phone.dispose();
    _email.dispose();
    _customerCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _state == CommercialRegistrationState.unregistered) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_state == CommercialRegistrationState.pending) {
      return _pendingView();
    }
    if (_state == CommercialRegistrationState.registered) {
      return _registeredUnavailableView();
    }
    return _registrationView();
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
                  'بعد الموافقة سيحصل هذا الجهاز على ترخيصه الخاص تلقائيًا.',
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
                    'اربط هذا الجهاز بحساب يلا التجاري',
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
                        labelText: 'البريد الإلكتروني (اختياري)',
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
                            : 'إنشاء الحساب وإرسال الطلب'),
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
