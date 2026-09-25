import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_offline_lease.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/legal/support_complaint_button.dart';
import 'package:yalla_accounts/core/privacy/account_deletion_request_button.dart';
import 'package:yalla_accounts/core/release/widgets/release_legal_links.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  LicenseCheckResult? _online;
  CommercialOfflineLease? _offline;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final service = createCommercialBackendService();
    if (service == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = StateError('Commercial backend is not configured.');
        });
      }
      return;
    }
    try {
      final result = await service.checkCurrentLicense();
      if (result != null) {
        CommercialBackendRuntimeAccess.applyLicense(result);
      }
      if (!mounted) return;
      setState(() {
        _online = result;
        _offline = null;
        _loading = false;
      });
      return;
    } catch (error) {
      try {
        final lease = await service.checkOfflineLease();
        if (lease != null) {
          CommercialBackendRuntimeAccess.applyOfflineLease(lease);
          if (!mounted) return;
          setState(() {
            _online = null;
            _offline = lease;
            _loading = false;
            _error = null;
          });
          return;
        }
      } catch (_) {
        // Preserve the online error as the most useful diagnostic.
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  String _date(DateTime? value) {
    if (value == null) return '—';
    final d = value.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String _money(double value, String currency) {
    if (value == value.roundToDouble()) {
      return '${value.toStringAsFixed(0)} $currency';
    }
    return '${value.toStringAsFixed(2)} $currency';
  }

  String _stateLabel(String state) => switch (state) {
        'ENABLED' => 'متاحة',
        'READ_ONLY' => 'قراءة فقط',
        'BLOCKED' => 'محظورة',
        _ => 'مقفلة',
      };

  void _upgradeInfo(CommercialPlanOption plan) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('الترقية إلى ${plan.name}'),
        content: const Text(
          'يمكن تنفيذ الترقية مباشرة من Yallah Control. '
          'بعد اعتمادها سيحدّث التطبيق الترخيص ويفتح الميزات الجديدة '
          'دون حذف البيانات أو إعادة تثبيت التطبيق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = _online;
    final offline = _offline;
    final features = online?.features ?? offline?.features ?? const {};
    final limits = online?.limits ?? offline?.limits ?? const {};
    final planCode = online?.planCode ?? offline?.planCode;
    final planName = online?.planName ?? offline?.planName ?? planCode;
    final billing =
        online?.billingPeriod ?? offline?.billingPeriod ?? 'MONTHLY';
    final monthly = online?.monthlyPrice ?? offline?.monthlyPrice ?? 0;
    final annual = online?.annualPrice ?? offline?.annualPrice ?? 0;
    final currency = online?.currency ?? offline?.currency ?? 'USD';
    final status =
        online?.subscriptionStatus ?? offline?.subscriptionStatus ?? 'UNKNOWN';
    final startsAt = online?.startsAt ?? offline?.startsAt;
    final expiresAt = online?.expiresAt ?? offline?.expiresAt;
    final graceUntil = online?.graceUntil ?? offline?.graceUntil;
    final access = online?.accessMode ?? offline?.accessMode ?? 'BLOCKED';
    final plans = online?.availablePlans ?? const <CommercialPlanOption>[];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('الحزمة والاشتراك'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'تحديث الترخيص',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null || (online == null && offline == null)
                ? _ErrorCard(onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (offline != null)
                          const _Notice(
                            icon: Icons.cloud_off_outlined,
                            text:
                                'أنت تعمل بآخر ترخيص Offline صالح. الصلاحيات والحدود '
                                'مأخوذة من آخر Entitlements موثقة على هذا الجهاز.',
                          ),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                        Icons.workspace_premium_outlined),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        planName ?? 'حزمة غير معروفة',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                    ),
                                    _StatusChip(access: access, status: status),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 18,
                                  runSpacing: 8,
                                  children: [
                                    Text('رمز الحزمة: ${planCode ?? '—'}'),
                                    Text(
                                      'الفوترة: ${billing == 'ANNUAL' ? 'سنوي' : 'شهري'}',
                                    ),
                                    Text(
                                      'شهري: ${_money(monthly, currency)}',
                                    ),
                                    Text(
                                      'سنوي: ${_money(annual, currency)}',
                                    ),
                                    Text('البداية: ${_date(startsAt)}'),
                                    Text('الانتهاء: ${_date(expiresAt)}'),
                                    if (graceUntil != null)
                                      Text('المهلة: ${_date(graceUntil)}'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _LimitsCard(limits: limits),
                        const SizedBox(height: 14),
                        _FeaturesCard(
                          features: features,
                          stateLabel: _stateLabel,
                        ),
                        if (plans.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            'عرض الحزم',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          ...plans.map(
                            (plan) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      plan.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (plan.description?.isNotEmpty ==
                                        true) ...[
                                      const SizedBox(height: 4),
                                      Text(plan.description!),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_money(plan.monthlyPrice, plan.currency)} / شهر'
                                      '   ·   ${_money(plan.annualPrice, plan.currency)} / سنة',
                                    ),
                                    const SizedBox(height: 10),
                                    FilledButton.icon(
                                      onPressed: plan.code == planCode
                                          ? null
                                          : () => _upgradeInfo(plan),
                                      icon: Icon(
                                        plan.code == planCode
                                            ? Icons.check_circle_outline
                                            : Icons.upgrade,
                                      ),
                                      label: Text(
                                        plan.code == planCode
                                            ? 'الحزمة الحالية'
                                            : 'ترقية',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const _Notice(
                          icon: Icons.info_outline,
                          text:
                              'لا يوجد شراء أو تجديد مدفوع ذاتي داخل التطبيق. '
                              'تتم إدارة الاشتراك والترقية من خلال Yallah Control أو فريق الدعم.',
                        ),
                        const SizedBox(height: 12),
                        const AccountDeletionRequestButton(),
                        const SizedBox(height: 8),
                        const SupportComplaintButton(),
                        const SizedBox(height: 8),
                        const ReleaseLegalLinks(),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _LimitsCard extends StatelessWidget {
  const _LimitsCard({required this.limits});
  final Map<String, CommercialLimitEntitlement> limits;

  String _label(String code) => switch (code) {
        'MAX_USERS' => 'المستخدمون',
        'MAX_DEVICES' => 'الأجهزة',
        'MAX_REPAIRS_MONTH' => 'ملفات الإصلاح هذا الشهر',
        'MAX_INVOICES_MONTH' => 'الفواتير هذا الشهر',
        'MAX_STORAGE_MB' => 'التخزين (MB)',
        _ => code,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الحدود والاستخدام',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (limits.isEmpty)
              const Text('لا توجد حدود متاحة في الترخيص الحالي.')
            else
              ...limits.values.map(
                (limit) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_label(limit.code)),
                  subtitle: Text(
                    limit.unlimited
                        ? 'المستخدم: ${limit.used} · غير محدود'
                        : 'المستخدم: ${limit.used} / ${limit.value}',
                  ),
                  trailing: limit.reached && !limit.unlimited
                      ? const Icon(Icons.warning_amber_rounded)
                      : const Icon(Icons.check_circle_outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeaturesCard extends StatelessWidget {
  const _FeaturesCard({
    required this.features,
    required this.stateLabel,
  });

  final Map<String, CommercialFeatureEntitlement> features;
  final String Function(String) stateLabel;

  @override
  Widget build(BuildContext context) {
    final values = features.values.toList(growable: false);
    values.sort((a, b) {
      final aw = a.enabled
          ? 0
          : a.readOnly
              ? 1
              : 2;
      final bw = b.enabled
          ? 0
          : b.readOnly
              ? 1
              : 2;
      if (aw != bw) return aw.compareTo(bw);
      return a.code.compareTo(b.code);
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الميزات', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...values.map(
              (feature) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  feature.enabled
                      ? Icons.check_circle_outline
                      : feature.readOnly
                          ? Icons.visibility_outlined
                          : Icons.lock_outline,
                ),
                title: Text(feature.nameAr ?? feature.code),
                subtitle: Text(feature.code),
                trailing: Text(stateLabel(feature.state)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.access, required this.status});
  final String access;
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (access) {
      'FULL' => 'نشط',
      'READ_ONLY' => 'قراءة فقط',
      _ => 'موقوف',
    };
    return Chip(label: Text('$label · $status'));
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(text),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 42),
                  const SizedBox(height: 12),
                  const Text(
                    'تعذر تحميل حالة الحزمة أو التحقق من ترخيص Offline صالح.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
