import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/repairs/widgets/quick_entry_fields.dart';

void main() {
  for (final count in [1, 3]) {
    for (final save in [true, false]) {
      testWidgets(
          'quick entry $count fields survives ${save ? "save" : "cancel"} while focused',
          (tester) async {
        List<TextEditingController>? owned;
        String? result;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () async {
                            result = await showDialog<String>(
                                context: context,
                                builder: (dialogContext) => QuickEntryFields(
                                      count: count,
                                      builder: (controllers) {
                                        owned = controllers;
                                        return AlertDialog(
                                            content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  for (final controller
                                                      in controllers)
                                                    TextField(
                                                        controller: controller,
                                                        autofocus: controller ==
                                                            controllers.first),
                                                ]),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          dialogContext,
                                                          save
                                                              ? controllers
                                                                  .first.text
                                                              : null),
                                                  child: const Text('close'))
                                            ]);
                                      },
                                    ));
                          },
                          child: const Text('open'),
                        )))));
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, 'vehicle-123');
          await tester.tap(find.text('close'));
          await tester.pump();
          // Dialog result completes before its exit animation/unmount.
          expect(result, save ? 'vehicle-123' : isNull);
          final listener = () {};
          owned!.first.addListener(listener);
          owned!.first.removeListener(listener);
          await tester.pump(const Duration(milliseconds: 75));
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(() => owned!.first.addListener(listener), throwsFlutterError);
        }
      });
    }
  }
}
