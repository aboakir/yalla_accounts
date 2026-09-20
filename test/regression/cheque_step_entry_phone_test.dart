import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yalla_accounts/features/cheques/widgets/steps/cheque_step_entry.dart';
import 'package:yalla_accounts/theme/app_theme.dart';

const _save = '\u062d\u0641\u0638 \u0627\u0644\u0634\u064a\u0643';

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(414, 896),
  double keyboard = 0,
  double scale = 1,
  ValueChanged<Map<String, dynamic>?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.lightTheme.copyWith(platform: TargetPlatform.iOS),
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Builder(
        builder: (context) => Scaffold(
              body: Center(
                  child: TextButton(
                onPressed: () async {
                  final result = await showDialog<Map<String, dynamic>>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) =>
                        ChequeStepEntry(amount: 2500, onSubmit: (_) {}),
                  );
                  onResult?.call(result);
                },
                child: const Text('open'),
              )),
            )),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (keyboard > 0) {
    await tester.tap(find.byType(TextFormField).first);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.view.padding = const FakeViewPadding(top: 44);
    await tester.pumpAndSettle();
  }
}

void _expectSaveVisible(WidgetTester tester, Size size, double keyboard) {
  final save = find.widgetWithText(ElevatedButton, _save);
  expect(save.hitTestable(), findsOneWidget,
      reason: 'The save action must remain tappable above the keyboard.');
  final rect = tester.getRect(save);
  expect(rect.top, greaterThanOrEqualTo(44));
  expect(rect.bottom,
      lessThanOrEqualTo(size.height - (keyboard > 0 ? keyboard : 34)));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(size.width));
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(initializeDateFormatting);
  _behaviorTests();
  const cases = [
    (name: 'small phone', size: Size(320, 568), keyboard: 216.0, scale: 1.0),
    (
      name: 'iPhone portrait',
      size: Size(414, 896),
      keyboard: 330.0,
      scale: 1.0
    ),
    (
      name: 'large Arabic text',
      size: Size(390, 844),
      keyboard: 320.0,
      scale: 1.5
    ),
    (
      name: 'phone landscape',
      size: Size(844, 390),
      keyboard: 150.0,
      scale: 1.0
    ),
    (name: 'desktop', size: Size(1280, 800), keyboard: 0.0, scale: 1.0),
  ];
  for (final scenario in cases) {
    for (final keyboard in {0.0, scenario.keyboard}) {
      testWidgets('cheque save visible: ${scenario.name}, keyboard=$keyboard',
          (tester) async {
        await _open(tester,
            size: scenario.size, keyboard: keyboard, scale: scenario.scale);
        _expectSaveVisible(tester, scenario.size, keyboard);
        final scroll = find.descendant(
            of: find.byType(ChequeStepEntry),
            matching: find.byType(SingleChildScrollView));
        expect(scroll, findsOneWidget);
        await tester.drag(scroll, const Offset(0, -900));
        await tester.pumpAndSettle();
        _expectSaveVisible(tester, scenario.size, keyboard);
        final notes = find.byType(TextFormField).last;
        await tester.ensureVisible(notes);
        await tester.pumpAndSettle();
        expect(notes.hitTestable(), findsOneWidget);
        _expectSaveVisible(tester, scenario.size, keyboard);
      });
    }
  }
}

Future<void> _fill(WidgetTester tester, int index, String text) async {
  final field = find.byType(TextFormField).at(index);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void _behaviorTests() {
  testWidgets('valid received cheque returns the unchanged draft exactly once',
      (tester) async {
    Map<String, dynamic>? result;
    var submissions = 0;
    await _open(tester, keyboard: 330, onResult: (value) {
      result = value;
      submissions++;
    });
    await _fill(tester, 0, '7890');
    await _fill(tester, 1, '  Test Drawer  ');
    await _fill(tester, 2, '  Test Bank  ');
    await _fill(tester, 3, 'Branch 1');
    await _fill(tester, 4, 'Last Endorser');
    await _fill(tester, 5, 'Car repair payment');
    _expectSaveVisible(tester, const Size(414, 896), 330);
    await tester.tap(find.widgetWithText(ElevatedButton, _save));
    await tester.pumpAndSettle();
    expect(submissions, 1);
    expect(result, isNotNull);
    expect(result!['amount'], 2500);
    expect(result!['cheque_no'], '7890');
    expect(result!['drawer_name'], 'Test Drawer');
    expect(result!['bank_name'], 'Test Bank');
    expect(result!['bank_branch'], 'Branch 1');
    expect(result!['last_endorser_name'], 'Last Endorser');
    expect(result!['notes'], 'Car repair payment');
    expect(result!['uuid'], isNotEmpty);
    expect(result!['instrument_key'], isNotEmpty);
    expect(DateTime.tryParse(result!['issue_date'] as String), isNotNull);
    expect(DateTime.tryParse(result!['due_date'] as String), isNotNull);
    expect(result!.containsKey('bank_account_id'), isFalse);
    expect(find.byType(ChequeStepEntry), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing required data blocks save while its action stays visible',
      (tester) async {
    var submissions = 0;
    await _open(tester,
        size: const Size(320, 568),
        keyboard: 216,
        onResult: (_) => submissions++);
    await tester.tap(find.widgetWithText(ElevatedButton, _save));
    await tester.pumpAndSettle();
    expect(submissions, 0);
    expect(find.byType(ChequeStepEntry), findsOneWidget);
    final fields = tester
        .stateList<FormFieldState<String>>(find.byType(TextFormField))
        .toList();
    expect(fields.where((field) => field.hasError), hasLength(3));
    _expectSaveVisible(tester, const Size(320, 568), 216);
    await _fill(tester, 0, '9001');
    await _fill(tester, 1, 'Drawer');
    await _fill(tester, 2, 'Bank');
    await tester.tap(find.widgetWithText(ElevatedButton, _save));
    await tester.pumpAndSettle();
    expect(submissions, 1);
    expect(find.byType(ChequeStepEntry), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard hide and reopen preserve entered cheque data',
      (tester) async {
    await _open(tester, keyboard: 330);
    await _fill(tester, 0, '2468');
    await _fill(tester, 1, 'Retained Drawer');
    for (final keyboard in [0.0, 330.0, 0.0, 330.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      tester.view.padding =
          FakeViewPadding(top: 44, bottom: keyboard == 0 ? 34 : 0);
      await tester.pumpAndSettle();
      _expectSaveVisible(tester, const Size(414, 896), keyboard);
      final fields =
          tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      expect(fields[0].controller!.text, '2468');
      expect(fields[1].controller!.text, 'Retained Drawer');
    }
  });
}
