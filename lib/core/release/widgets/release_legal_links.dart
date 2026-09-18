import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/legal/local_legal_documents.dart';

class ReleaseLegalLinks extends StatelessWidget {
  const ReleaseLegalLinks({super.key, this.compact = false});

  final bool compact;

  void _open(BuildContext context, LocalLegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalLegalDocumentScreen(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      TextButton(
        key: const Key('localPrivacyPolicyLink'),
        onPressed: () => _open(context, LocalLegalDocuments.privacy),
        child: const Text('سياسة الخصوصية'),
      ),
      TextButton(
        key: const Key('localTermsLink'),
        onPressed: () => _open(context, LocalLegalDocuments.terms),
        child: const Text('شروط الاستخدام'),
      ),
      TextButton(
        key: const Key('localAccountDeletionLink'),
        onPressed: () => _open(context, LocalLegalDocuments.deletion),
        child: const Text('طلب حذف الحساب والبيانات'),
      ),
      TextButton(
        key: const Key('localRefundLink'),
        onPressed: () => _open(context, LocalLegalDocuments.refund),
        child: const Text('الإلغاء والاسترداد'),
      ),
      TextButton(
        key: const Key('localSupportLink'),
        onPressed: () => _open(context, LocalLegalDocuments.support),
        child: const Text('الدعم والشكاوى'),
      ),
      TextButton(
        key: const Key('localContactLink'),
        onPressed: () => _open(context, LocalLegalDocuments.contact),
        child: const Text('اتصل بنا'),
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
