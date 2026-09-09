import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';

class CurrentSubscriptionScreen extends StatefulWidget {
  const CurrentSubscriptionScreen({super.key, this.load});
  final Future<LicenseRuntimeDecision> Function()? load;
  @override
  State<CurrentSubscriptionScreen> createState() =>
      _CurrentSubscriptionScreenState();
}

class _CurrentSubscriptionScreenState extends State<CurrentSubscriptionScreen> {
  late Future<LicenseRuntimeDecision> _decision;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _decision = widget.load?.call() ??
        LicenseRuntimeService().refreshFromStoredLicense();
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('الاشتراك الحالي')),
          body: FutureBuilder<LicenseRuntimeDecision>(
              future: _decision,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('تعذر التحقق من الاشتراك.'),
                    TextButton(
                        onPressed: () => setState(_reload),
                        child: const Text('إعادة المحاولة')),
                  ]));
                }
                final decision = snapshot.data!;
                final license = decision.license;
                return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                              license == null
                                                  ? 'التفعيل مطلوب'
                                                  : 'حالة الاشتراك: ${SubscriptionAccessPolicy.label(license.operationalStatus)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          const SizedBox(height: 16),
                                          if (license != null) ...[
                                            Text(
                                                'تاريخ الانتهاء: ${_date(license.expiresAt)}'),
                                            const SizedBox(height: 12),
                                            Text(
                                                decision.isWritable
                                                    ? 'العمل متاح'
                                                    : 'القراءة فقط',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            const SizedBox(height: 8),
                                            Text(SubscriptionAccessPolicy
                                                .message(decision.mode)),
                                            if (SubscriptionAccessPolicy
                                                    .normalize(license
                                                        .operationalStatus) ==
                                                'EXCEPTION')
                                              const Text(
                                                  'الاستثناء معتمد بالترخيص الموقّع وينتهي في التاريخ الموضح.'),
                                            if (SubscriptionAccessPolicy
                                                    .normalize(license
                                                        .operationalStatus) ==
                                                'DEMO')
                                              const Text(
                                                  'العرض التوضيحي لا يسمح بتعديل بيانات الورشة الحقيقية.'),
                                          ] else
                                            const Text(
                                                'لا يوجد ترخيص موثّق لهذا الجهاز. يمكن للمالك تصدير بياناته من شاشة الدخول.'),
                                          const SizedBox(height: 16),
                                          OutlinedButton.icon(
                                              onPressed: () =>
                                                  setState(_reload),
                                              icon: const Icon(Icons.refresh),
                                              label: const Text(
                                                  'تحديث حالة الاشتراك')),
                                        ]))))));
              })));
}
