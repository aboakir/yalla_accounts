import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_theme.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/support/screens/technical_support_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A9 drawer is responsive at three phone widths', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in <double>[320, 390, 430]) {
      tester.view.physicalSize = Size(width, 844);
      final key = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: YallaMobileTheme.from(
            ThemeData(useMaterial3: true),
            viewportWidth: width,
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              key: key,
              drawer: const Drawer(child: YallaSidebar()),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      final expected = YallaMobileTheme.drawerWidthFor(width);
      expect(tester.getSize(find.byType(Drawer)).width, closeTo(expected, .01));
      expect(tester.getSize(find.byType(YallaSidebar)).width,
          lessThanOrEqualTo(expected));
      expect(tester.takeException(), isNull);
      key.currentState!.closeDrawer();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('A9 RTL contact screen renders at three phone widths',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in <double>[320, 390, 430]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpWidget(const MaterialApp(
        home: TechnicalSupportScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('التواصل مع الشركة'), findsOneWidget);
      expect(find.text(TechnicalSupportScreen.whatsapp), findsOneWidget);
      expect(find.text(TechnicalSupportScreen.phone), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
