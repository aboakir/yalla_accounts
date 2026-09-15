import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/entitlements/commercial_entitlement_policy.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';

/// Displays only capabilities authenticated by the existing license verifier.
class VerifiedSetupPlan extends StatelessWidget {
  const VerifiedSetupPlan({super.key, required this.license});
  final VerifiedLicense license;

  @override
  Widget build(BuildContext context) {
    final expiry = license.expiresAt.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الخطة المفعّلة',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
                'الحالة: ${SubscriptionAccessPolicy.label(license.operationalStatus)}'),
            Text(
                'الخطة: ${CommercialEntitlementPolicy.planCode(license) ?? 'غير معروفة'}'),
            Text('المستخدمون: ${license.entitlements['MAX_USERS']}'),
            Text('الأجهزة: ${license.entitlements['MAX_DEVICES']}'),
            Text(
                'صالحة حتى: ${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}'),
            const SizedBox(height: 8),
            const Text('تم تسجيل هذا الجهاز وربطه باشتراك الورشة عند التفعيل.'),
            const Text('تغيير الخطة يحتاج ترخيصًا جديدًا معتمدًا من Yalla.'),
          ],
        ),
      ),
    );
  }
}
