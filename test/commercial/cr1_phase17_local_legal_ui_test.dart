import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/release/widgets/release_legal_links.dart';

void main() {
  const cases = <({
    String keyName,
    String title,
    String version,
  })>[
    (
      keyName: 'localPrivacyPolicyLink',
      title: 'سياسة الخصوصية',
      version: 'privacy_ps_v2',
    ),
    (
      keyName: 'localTermsLink',
      title: 'شروط الاستخدام',
      version: 'terms_ps_v2',
    ),
    (
      keyName: 'localAccountDeletionLink',
      title: 'حذف الحساب والبيانات',
      version: 'deletion_ps_v2',
    ),
    (
      keyName: 'localRefundLink',
      title: 'الإلغاء والاسترداد',
      version: 'refund_ps_v2',
    ),
    (
      keyName: 'localSupportLink',
      title: 'الدعم والشكاوى',
      version: 'support_ps_v2',
    ),
    (
      keyName: 'localContactLink',
      title: 'اتصل بنا',
      version: 'contact_ps_v2',
    ),
  ];

  for (final item in cases) {
    testWidgets(
      'Phase 17 opens bundled ${item.version} inside the app',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: ReleaseLegalLinks(compact: true)),
          ),
        );

        await tester.tap(find.byKey(Key(item.keyName)));
        await tester.pumpAndSettle();

        expect(find.text(item.title), findsWidgets);
        expect(find.textContaining(item.version), findsWidgets);
        expect(find.textContaining('@yallah.ps'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
