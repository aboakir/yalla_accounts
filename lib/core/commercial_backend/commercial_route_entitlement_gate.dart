import 'package:flutter/material.dart';

import 'commercial_backend_environment.dart';
import 'commercial_backend_runtime_access.dart';
import '../licensing/entitlements/commercial_feature_catalog.dart';

class CommercialRouteEntitlementGate extends StatelessWidget {
  const CommercialRouteEntitlementGate({
    super.key,
    required this.routeName,
    required this.child,
  });

  final String routeName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!CommercialBackendEnvironment.enabled) return child;
    final feature = CommercialFeatureCatalog.forRoute(routeName);
    if (feature == null ||
        CommercialBackendRuntimeAccess.canReadFeature(feature)) {
      return child;
    }

    final blocked = CommercialBackendRuntimeAccess.mode ==
        CommercialBackendRuntimeMode.blocked;
    final title = blocked ? 'الحساب موقوف' : 'الميزة مقفلة';
    final message = blocked
        ? 'لا يمكن فتح هذه الميزة قبل إعادة تفعيل الاشتراك.'
        : 'هذه الميزة غير متاحة في الحزمة الحالية. بياناتك الحالية لا تُحذف عند تغيير الحزمة.';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 48),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        feature,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/subscription'),
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: const Text('عرض الحزم'),
                      ),
                    ],
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
