import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/release/widgets/release_legal_links.dart';

void main() {
  testWidgets('Phase 17 legal links open bundled privacy inside the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReleaseLegalLinks(compact: true)),
      ),
    );
    await tester.tap(find.byKey(const Key('localPrivacyPolicyLink')));
    await tester.pumpAndSettle();
    expect(find.text('سياسة الخصوصية'), findsWidgets);
    expect(find.textContaining('privacy_ps_v1'), findsWidgets);
    expect(find.textContaining('yalla.accou@gmail.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phase 17 terms are local and do not launch an external URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReleaseLegalLinks(compact: true)),
      ),
    );
    await tester.tap(find.byKey(const Key('localTermsLink')));
    await tester.pumpAndSettle();
    expect(find.text('شروط الاستخدام'), findsWidgets);
    expect(find.textContaining('terms_ps_v1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
