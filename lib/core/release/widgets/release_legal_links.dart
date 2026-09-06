import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yalla_accounts/core/release/release_distribution_config.dart';

class ReleaseLegalLinks extends StatelessWidget {
  const ReleaseLegalLinks({
    super.key,
    this.compact = false,
  });

  final bool compact;

  Future<void> _open(
    BuildContext context, {
    required String rawUrl,
    required String missingMessage,
  }) async {
    final uri = ReleaseDistributionConfig.httpsUri(rawUrl);
    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(missingMessage)),
      );
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      TextButton(
        onPressed: () => _open(
          context,
          rawUrl: ReleaseDistributionConfig.privacyUrl,
          missingMessage: 'رابط سياسة الخصوصية غير مهيأ في هذا الإصدار.',
        ),
        child: const Text('سياسة الخصوصية'),
      ),
      TextButton(
        onPressed: () => _open(
          context,
          rawUrl: ReleaseDistributionConfig.termsUrl,
          missingMessage: 'رابط شروط الاستخدام غير مهيأ في هذا الإصدار.',
        ),
        child: const Text('شروط الاستخدام'),
      ),
      TextButton(
        onPressed: () => _open(
          context,
          rawUrl: ReleaseDistributionConfig.accountDeletionUrl,
          missingMessage: 'مسار طلب حذف الحساب غير مهيأ في هذا الإصدار.',
        ),
        child: const Text('طلب حذف الحساب والبيانات'),
      ),
    ];

    if (compact) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 0,
        children: buttons,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: buttons,
    );
  }
}
