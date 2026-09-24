import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';
import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/home/services/daily_dashboard_service.dart';

class FirstUseChecklistCard extends StatefulWidget {
  const FirstUseChecklistCard({
    super.key,
    required this.profile,
    required this.data,
    required this.onOpen,
  });

  final AppExperienceProfile profile;
  final DailyDashboardData data;
  final void Function(String route, String? repairId) onOpen;

  @override
  State<FirstUseChecklistCard> createState() => _FirstUseChecklistCardState();
}

class _FirstUseChecklistCardState extends State<FirstUseChecklistCard> {
  static const _dismissedKey = 'yallah.first_use.dismissed.v1';
  bool _loaded = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dismissed = prefs.getBool(_dismissedKey) == true;
      _loaded = true;
    });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
    if (mounted) setState(() => _dismissed = true);
  }

  List<_FirstUseStep> get _steps {
    final steps = <_FirstUseStep>[];
    if (widget.profile.moduleEnabled(AppModule.repairs)) {
      final hasRepair = widget.data.cars.isNotEmpty ||
          widget.data.recentFiles.isNotEmpty ||
          widget.data.newFiles > 0;
      steps.add(_FirstUseStep(
        title: 'أنشئ أول ملف إصلاح',
        note: 'سجّل العميل والمركبة والأعمال المطلوبة.',
        route: AppRoutes.repairsAdd,
        done: hasRepair,
      ));
    }
    if (widget.profile.moduleEnabled(AppModule.inventory)) {
      steps.add(_FirstUseStep(
        title: 'جهّز أول صنف في المخزون',
        note: 'افتح المخزون وأضف الصنف أو راجع الرصيد الافتتاحي.',
        route: AppRoutes.inventory,
        done: widget.data.inventory.itemCount > 0,
      ));
    }
    if (widget.profile.moduleEnabled(AppModule.purchases)) {
      steps.add(_FirstUseStep(
        title: 'سجّل أول فاتورة شراء',
        note: 'اربط المورد والبنود والمخزون من نفس الحركة.',
        route: AppRoutes.purchaseCreate,
        done: widget.data.inventory.periodPurchases > 0,
      ));
    }
    if (widget.profile.moduleEnabled(AppModule.vouchers)) {
      steps.add(_FirstUseStep(
        title: 'سجّل أول حركة قبض أو صرف',
        note: 'استخدم السندات لتبقى الذمم والحسابات متزامنة.',
        route: AppRoutes.receiptVoucher,
        done: widget.data.lastEntry != null,
      ));
    }
    return steps;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _dismissed) return const SizedBox.shrink();
    final pending = _steps.where((step) => !step.done).toList(growable: false);
    if (pending.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_outlined, color: YallaColors.brand),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ابدأ أول عملية',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ),
                IconButton(
                  tooltip: 'إخفاء دليل البداية',
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              'هذه الخطوات لا تنشئ بيانات وهمية؛ كل زر يفتح شاشة العمل الحقيقية.',
              style: TextStyle(fontSize: 12, color: YallaColors.textMuted),
            ),
            const SizedBox(height: 8),
            for (final step in pending.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.arrow_circle_left_outlined),
                title: Text(step.title),
                subtitle: Text(step.note),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => widget.onOpen(step.route, null),
              ),
          ],
        ),
      ),
    );
  }
}

class _FirstUseStep {
  const _FirstUseStep({
    required this.title,
    required this.note,
    required this.route,
    required this.done,
  });

  final String title;
  final String note;
  final String route;
  final bool done;
}
