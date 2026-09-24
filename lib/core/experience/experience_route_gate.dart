import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/release/release_scope_config.dart';

import 'app_experience_profile.dart';
import 'app_experience_service.dart';

class ExperienceRouteGate extends StatelessWidget {
  const ExperienceRouteGate({
    super.key,
    required this.routeName,
    required this.child,
  });

  final String routeName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppExperienceProfile>(
      valueListenable: AppExperienceService.current,
      builder: (context, profile, _) {
        final visible = profile.isRouteVisible(
          routeName,
          insurancePilotVisible: ReleaseScopeConfig.insurancePilotVisible,
        );
        if (visible) return child;
        return Scaffold(
          appBar: AppBar(title: const Text('القسم مخفي')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.visibility_off_outlined, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'هذا القسم غير ظاهر في إعدادات تجربتك الحالية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'إخفاء القسم لا يحذف بياناته ولا يغيّر القيود المحاسبية.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamed('/settings/experience'),
                        icon: const Icon(Icons.tune),
                        label: const Text('تخصيص الأقسام'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
