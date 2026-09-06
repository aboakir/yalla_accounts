import 'package:flutter/material.dart';

/// Subscription administration is server-authoritative in P18.
///
/// This legacy screen intentionally performs no local subscription/user writes.
class PendingSubscriptionsScreen extends StatelessWidget {
  const PendingSubscriptionsScreen({super.key});

  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الاشتراكات')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'إنشاء الاشتراكات وتجديدها وتغيير حالتها يتم من السلطة التجارية '
              'على خادم Yalla. التطبيق المحلي يعرض فقط الحالة الموقّعة.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
