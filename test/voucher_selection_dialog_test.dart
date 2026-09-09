import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/vouchers/dialogs/voucher_selection_dialog.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('selection list renders and responds at $size with keyboard',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      String? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
          child: const Text('open'),
          onPressed: () async {
            selected = await showDialog<String>(
                context: context,
                builder: (ctx) => VoucherSelectionDialog(
                      title: const Text('اختر المورد'),
                      content: SizedBox(
                          width: double.infinity,
                          height: 520,
                          child: Column(children: [
                            const TextField(),
                            Expanded(
                                child: ListView.builder(
                                    itemCount: 30,
                                    itemBuilder: (_, i) => ListTile(
                                        title: Text('supplier $i'),
                                        onTap: () =>
                                            Navigator.pop(ctx, '$i')))),
                          ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('cancel'))
                      ],
                    ));
          },
        ),
      ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('supplier 0'), findsOneWidget);
      tester.view.viewInsets =
          FakeViewPadding(bottom: size.height > 400 ? 300 : 100);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('supplier 0'));
      await tester.pumpAndSettle();
      expect(selected, '0');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(VoucherSelectionDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
