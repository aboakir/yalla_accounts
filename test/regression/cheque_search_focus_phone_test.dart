import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/providers/cheque_provider.dart';
import 'package:yalla_accounts/features/cheques/screens/cheques_list_screen.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';

class _FakeChequeService extends ChequeService {
  final seen = <String?>[];

  @override
  Future<List<Cheque>> fetchFiltered({
    String? search,
    ChequeStatus? status,
    ChequeType? type,
    DateTime? issueFrom,
    DateTime? issueTo,
    DateTime? dueFrom,
    DateTime? dueTo,
  }) async {
    seen.add(search);
    return const <Cheque>[];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cheque search keeps focus on 320px RTL during live rebuilds',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeChequeService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chequeServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
          home: const ChequesListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'بحث...',
    );
    expect(searchField, findsOneWidget);
    await tester.tap(searchField);
    await tester.pump();

    for (final query in ['ش', 'شي', 'شيك', 'شيك ١٢٣']) {
      await tester.enterText(searchField, query);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final editable = tester.widget<EditableText>(
        find.descendant(of: searchField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue,
          reason: 'focus lost at $query');
      final expectedText = query == 'شيك ١٢٣' ? 'شيك 123' : query;
      expect(editable.controller.text, expectedText);
      expect(tester.takeException(), isNull);
    }

    expect(service.seen.last, 'شيك 123');
  });
}
