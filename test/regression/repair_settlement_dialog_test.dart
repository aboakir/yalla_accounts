import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_settlement_dialog.dart';
import 'package:yalla_accounts/theme/app_theme.dart';

Future<void> _open(
  WidgetTester tester, {
  double currentValue = 7000,
  double paid = 4800,
  double keyboard = 0,
  Size size = const Size(390, 844),
  ValueChanged<RepairSettlementDraft?>? onResult,
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
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final result = await showDialog<RepairSettlementDraft>(
                context: context,
                barrierDismissible: false,
                builder: (_) => RepairSettlementDialog(
                  currentValue: currentValue,
                  paid: paid,
                ),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  if (keyboard > 0) {
    await tester.tap(find.byKey(const ValueKey('settlement_amount')));
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.view.padding = const FakeViewPadding(top: 44);
    await tester.pumpAndSettle();
  }
}

Future<void> _selectReason(WidgetTester tester, String reason) async {
  await tester.ensureVisible(find.byKey(const ValueKey('settlement_reason')));
  await tester.tap(find.byKey(const ValueKey('settlement_reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(reason).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('minus 2200 previews 4800 and returns signed settlement',
      (tester) async {
    RepairSettlementDraft? result;
    await _open(tester, keyboard: 320, onResult: (value) => result = value);
    await tester.enterText(
      find.byKey(const ValueKey('settlement_amount')),
      '2200',
    );
    await _selectReason(tester, 'اتفاق نهائي مع العميل');

    expect(find.textContaining('4,800'), findsWidgets);
    expect(find.textContaining('المتبقي: 0'), findsOneWidget);
    final save = find.byKey(const ValueKey('settlement_save'));
    expect(save.hitTestable(), findsOneWidget);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.adjustment, -2200);
    expect(result!.reason, 'اتفاق نهائي مع العميل');
    expect(find.byType(RepairSettlementDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('increase returns positive signed settlement', (tester) async {
    RepairSettlementDraft? result;
    await _open(tester, onResult: (value) => result = value);
    await tester.tap(find.byKey(const ValueKey('settlement_increase')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settlement_amount')),
      '500',
    );
    await _selectReason(tester, 'إضافة أعمال أو قطع');
    expect(find.textContaining('7,500'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('settlement_save')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.adjustment, 500);
  });

  testWidgets('reduction beyond current value is blocked', (tester) async {
    RepairSettlementDraft? result;
    await _open(tester, onResult: (value) => result = value);
    await tester.enterText(
      find.byKey(const ValueKey('settlement_amount')),
      '7001',
    );
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('settlement_save')),
    );
    expect(save.onPressed, isNull);
    expect(find.text('لا يمكن أن تصبح قيمة الملف سالبة.'), findsOneWidget);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save action remains reachable on a small phone keyboard',
      (tester) async {
    await _open(
      tester,
      keyboard: 216,
      size: const Size(320, 568),
    );
    final save = find.byKey(const ValueKey('settlement_save'));
    expect(save.hitTestable(), findsOneWidget);
    final rect = tester.getRect(save);
    expect(rect.bottom, lessThanOrEqualTo(568 - 216));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop RTL keeps settlement actions visible without overflow',
      (tester) async {
    RepairSettlementDraft? result;
    await _open(
      tester,
      size: const Size(1280, 800),
      onResult: (value) => result = value,
    );
    await tester.enterText(
      find.byKey(const ValueKey('settlement_amount')),
      '250',
    );
    await _selectReason(tester, 'خصم / سداد مبكر');

    final save = find.byKey(const ValueKey('settlement_save'));
    final cancel = find.byKey(const ValueKey('settlement_cancel'));
    expect(save.hitTestable(), findsOneWidget);
    expect(cancel.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('settlement_preview')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.operationId, isNotEmpty);
    expect(result!.adjustment, -250);
    expect(tester.takeException(), isNull);
  });
}
