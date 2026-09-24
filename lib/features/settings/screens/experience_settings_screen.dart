import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/experience/app_experience_service.dart';
import 'package:yalla_accounts/core/release/release_scope_config.dart';

class ExperienceSettingsScreen extends StatefulWidget {
  const ExperienceSettingsScreen({super.key});

  @override
  State<ExperienceSettingsScreen> createState() =>
      _ExperienceSettingsScreenState();
}

class _ExperienceSettingsScreenState extends State<ExperienceSettingsScreen> {
  bool _loading = true;
  late Set<BusinessActivity> _activities;
  late ExperienceMode _mode;
  late Map<AppModule, bool> _overrides;
  late Set<String> _hiddenRoutes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await AppExperienceService.load(force: true);
    if (!mounted) return;
    setState(() {
      _activities = {...profile.activities};
      _mode = profile.mode;
      _overrides = {...profile.moduleOverrides};
      _hiddenRoutes = {...profile.hiddenRoutes};
      _loading = false;
    });
  }

  AppExperienceProfile get _draft => AppExperienceProfile(
        activities: _activities,
        mode: _mode,
        moduleOverrides: _overrides,
        hiddenRoutes: _hiddenRoutes,
      );

  Future<void> _save() async {
    if (_activities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر نوع نشاط واحد على الأقل.')),
      );
      return;
    }
    await AppExperienceService.save(_draft);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ تجربة الاستخدام.')));
  }

  String _activityLabel(BusinessActivity activity) => switch (activity) {
        BusinessActivity.garage => 'كراج دهان وإصلاح',
        BusinessActivity.insurance => 'وكيل تأمين',
        BusinessActivity.parts => 'محل قطع سيارات',
      };

  String _moduleLabel(AppModule module) => switch (module) {
        AppModule.repairs => 'الإصلاحات والمركبات',
        AppModule.insurance => 'التأمين',
        AppModule.inventory => 'المخزون والمواد',
        AppModule.purchases => 'المشتريات',
        AppModule.employees => 'الموظفون والرواتب',
        AppModule.finance => 'المال والتحصيل',
        AppModule.vouchers => 'سندات القبض والصرف',
        AppModule.cheques => 'الشيكات',
        AppModule.parties => 'العملاء والموردون',
        AppModule.reports => 'التقارير',
      };

  void _toggleActivity(BusinessActivity activity, bool selected) {
    setState(() {
      if (selected) {
        _activities.add(activity);
      } else if (_activities.length > 1) {
        _activities.remove(activity);
      }
      _overrides.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final suggested = _draft.recommendedModules;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('نوع النشاط والأقسام الظاهرة')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'نوع نشاطك',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'اختر نشاطاً واحداً أو أكثر. سنقترح الأقسام المناسبة ويمكنك تعديلها.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final activity in BusinessActivity.values)
                    if (activity != BusinessActivity.insurance ||
                        ReleaseScopeConfig.insurancePilotVisible)
                      FilterChip(
                        label: Text(_activityLabel(activity)),
                        selected: _activities.contains(activity),
                        onSelected: (value) => _toggleActivity(activity, value),
                      ),
                ],
              ),
              if (!ReleaseScopeConfig.insurancePilotVisible) ...[
                const SizedBox(height: 10),
                const Text(
                  'وحدة التأمين محفوظة هندسياً لكنها غير معروضة في النسخة التجريبية التجارية الحالية.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'طريقة العرض',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              RadioListTile<ExperienceMode>(
                value: ExperienceMode.simple,
                groupValue: _mode,
                title: const Text('بسيط'),
                subtitle: const Text(
                  'مصطلحات عملية مثل: عليهم، علينا، دخل اليوم، صرف اليوم.',
                ),
                onChanged: (value) => setState(() => _mode = value!),
              ),
              RadioListTile<ExperienceMode>(
                value: ExperienceMode.advanced,
                groupValue: _mode,
                title: const Text('متقدم'),
                subtitle: const Text(
                  'يعرض الأستاذ والقيود وميزان المراجعة والفترات المحاسبية.',
                ),
                onChanged: (value) => setState(() => _mode = value!),
              ),
              const SizedBox(height: 16),
              Text(
                'الأقسام الظاهرة',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Text(
                'إخفاء أي قسم يغيّر الواجهة فقط؛ البيانات والقيود والتاريخ لا تُحذف.',
              ),
              const SizedBox(height: 8),
              for (final module in AppModule.values)
                if (module != AppModule.insurance ||
                    ReleaseScopeConfig.insurancePilotVisible)
                  SwitchListTile(
                    title: Text(_moduleLabel(module)),
                    subtitle: Text(
                      suggested.contains(module)
                          ? 'مقترح لهذا النشاط'
                          : 'اختياري',
                    ),
                    value: _draft.moduleEnabled(module),
                    onChanged: (value) => setState(() {
                      _overrides[module] = value;
                    }),
                  ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('تخصيص أقسام محاسبية فرعية'),
                subtitle: const Text('للمستخدم المتقدم عند الحاجة'),
                children: [
                  for (final route
                      in AppExperienceProfile.advancedAccountingRoutes)
                    SwitchListTile(
                      dense: true,
                      title: Text(_routeLabel(route)),
                      value: !_hiddenRoutes.contains(route),
                      onChanged: (value) => setState(() {
                        if (value) {
                          _hiddenRoutes.remove(route);
                        } else {
                          _hiddenRoutes.add(route);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ التخصيص'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _routeLabel(String route) => switch (route) {
        '/finance/journal/entries' => 'قيود اليومية',
        '/finance/account-ledger' => 'دفتر الأستاذ',
        '/finance/gl' => 'متصفح القيود المحاسبية',
        '/finance/general-journal' => 'اليومية العامة',
        '/finance/accounting-periods' => 'الفترات المحاسبية',
        '/reports/trial-balance' => 'ميزان المراجعة',
        '/reports/general-ledger' => 'الأستاذ العام',
        '/reports/balance-sheet' => 'الميزانية العمومية',
        _ => route,
      };
}
