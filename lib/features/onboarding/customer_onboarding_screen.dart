import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cloud_auth/cloud_auth_service.dart';
import '../activation/screens/activation_screen.dart';
import 'approved_onboarding_activation_service.dart';
import 'customer_onboarding_client.dart';
import 'customer_onboarding_service.dart';

class CustomerOnboardingScreen extends ConsumerStatefulWidget {
  const CustomerOnboardingScreen({super.key});
  @override
  ConsumerState<CustomerOnboardingScreen> createState() =>
      _CustomerOnboardingScreenState();
}

class _CustomerOnboardingScreenState
    extends ConsumerState<CustomerOnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'owner_name',
      'organization_name',
      'phone',
      'city',
      'address'
    ])
      key: TextEditingController()
  };
  bool _busy = true, _newRequest = false;
  String _country = 'PS';
  String? _error;
  CustomerOnboardingStatus? _status;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
      _newRequest = false;
    });
    try {
      final value = await ref.read(customerOnboardingServiceProvider).refresh();
      if (mounted) setState(() => _status = value);
    } on CustomerOnboardingException catch (e) {
      if (mounted) {
        setState(() {
          _newRequest = e.status == 404;
          if (!_newRequest) {
            _error =
                'تعذر التحقق من الطلب. تحقق من الاتصال أو سجّل الدخول مجددًا.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تحتاج إلى تسجيل دخول سحابي صالح ومؤكد.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await ref.read(customerOnboardingServiceProvider).submit({
        for (final entry in _fields.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
        'country_code': _country,
      });
      if (mounted) {
        setState(() {
          _status = value;
          _newRequest = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'لم يتأكد إرسال الطلب. أعد المحاولة بنفس البيانات أو حدّث الحالة.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueToActivation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(approvedOnboardingActivationServiceProvider).prepare();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const ActivationScreen(),
      ));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذر تجهيز التفعيل. حدّث حالة الطلب ثم أعد المحاولة.';
        });
      }
    }
  }

  Future<void> _logout() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await ref.read(supabaseIdentityProvider).signOut();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذر إكمال تسجيل الخروج. أعد المحاولة.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('تسجيل ورشة جديدة'), actions: [
            IconButton(
                onPressed: _busy ? null : _logout,
                tooltip: 'تسجيل الخروج',
                icon: const Icon(Icons.logout)),
          ]),
          body: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                                'إعداد المالك والورشة لا يمنح صلاحية تشغيلية. يبدأ التشغيل بعد موافقة الإدارة والتفعيل التجاري.'),
                            const SizedBox(height: 20),
                            if (_busy) const LinearProgressIndicator(),
                            if (_error != null)
                              Text(_error!, key: const Key('onboarding-error')),
                            if (_newRequest)
                              Form(
                                  key: _form,
                                  child: Column(children: [
                                    for (final field in const {
                                      'owner_name': 'اسم المالك',
                                      'organization_name': 'اسم الورشة',
                                      'phone': 'الهاتف',
                                      'city': 'المدينة',
                                      'address': 'العنوان (اختياري)'
                                    }.entries)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: TextFormField(
                                              controller: _fields[field.key],
                                              enabled: !_busy,
                                              key: Key(field.key),
                                              decoration: InputDecoration(
                                                  labelText: field.value),
                                              validator: (v) =>
                                                  field.key != 'address' &&
                                                          (v?.trim().isEmpty ??
                                                              true)
                                                      ? 'هذا الحقل مطلوب'
                                                      : null)),
                                    DropdownButtonFormField<String>(
                                        initialValue: _country,
                                        decoration: const InputDecoration(
                                            labelText: 'الدولة'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'PS',
                                              child: Text('فلسطين')),
                                          DropdownMenuItem(
                                              value: 'JO',
                                              child: Text('الأردن')),
                                          DropdownMenuItem(
                                              value: 'EG', child: Text('مصر')),
                                          DropdownMenuItem(
                                              value: 'SY', child: Text('سوريا'))
                                        ],
                                        onChanged: _busy
                                            ? null
                                            : (v) =>
                                                setState(() => _country = v!)),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                        onPressed: _busy ? null : _submit,
                                        child:
                                            const Text('إرسال طلب الانضمام')),
                                  ])),
                            if (_status != null) ...[
                              Text('رقم الطلب: ${_status!.requestId}'),
                              Text(_status!.status,
                                  key: const Key('onboarding-status')),
                              Text(switch (_status!.status) {
                                'APPROVED' =>
                                  'تمت الموافقة. بيانات المالك محفوظة بانتظار مرحلة تفعيل الجهاز. التشغيل ما زال مقفلًا.',
                                'REJECTED' =>
                                  'لم تتم الموافقة على الطلب. تواصل مع الإدارة.',
                                _ =>
                                  'طلبك قيد مراجعة الإدارة. يمكنك إغلاق التطبيق والعودة لاحقًا.',
                              }),
                              if (_status!.approved) ...[
                                Text(
                                    'معرّف المنشأة: ${_status!.data['organization_id']}'),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  key: const Key(
                                      'continue-commercial-activation'),
                                  onPressed:
                                      _busy ? null : _continueToActivation,
                                  icon:
                                      const Icon(Icons.verified_user_outlined),
                                  label: const Text('متابعة إلى تفعيل الجهاز'),
                                ),
                              ],
                            ],
                            const SizedBox(height: 16),
                            OutlinedButton(
                                onPressed: _busy ? null : _refresh,
                                child: const Text('تحديث الحالة من الخادم')),
                          ]))))));
}
