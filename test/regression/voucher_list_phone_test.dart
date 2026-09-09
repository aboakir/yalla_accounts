import 'dart:io';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/vouchers/widgets/voucher_list_phone.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  for (final receipt in [true, false]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
          'voucher phone receipt=$receipt width=$width, large text and actions',
          (t) async {
        t.view.physicalSize = Size(width, 720);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var search = '';
        var method = '';
        var documents = 0;
        var reversals = 0;
        final rows = List.generate(
            20,
            (i) => <String, Object?>{
                  'clientName': 'اسم العميل الطويل للاختبار على الهاتف $i',
                  'party_name': 'اسم المستفيد الطويل للاختبار على الهاتف $i',
                  'amount': 1234567.89,
                  'date': '2026-09-09T12:30:00',
                  'method': 'cash',
                  'notes':
                      'تفاصيل السند وبيان العملية المحفوظ كما أدخله المستخدم',
                  'status': i == 1 ? 'REVERSED' : 'POSTED',
                  'reversal_lines': i == 1 ? 1 : 0,
                });
        await t.pumpWidget(MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 720), textScaler: const TextScaler.linear(1.5)),
          child: Scaffold(
              body: VoucherListPhone(
            isReceipt: receipt,
            rows: rows,
            today: 1234567.89,
            month: 8765432.10,
            method: 'الكل',
            methods: const ['الكل', 'cash', 'cheque'],
            onSearch: (v) => search = v,
            onMethod: (v) => method = v,
            onRefresh: () async {},
            onExport: () {},
            onDocument: (_) => documents++,
            onReverse: receipt ? null : (_) => reversals++,
            numberLabel: (_) => 'سند رقم 123456',
          )),
        )));
        await t.pumpAndSettle();
        expect(
            find.text(receipt ? 'سندات القبض' : 'سندات الصرف'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.enterText(find.byType(TextField), '123');
        expect(search, '123');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
        await t.tap(find.byType(DropdownButtonFormField<String>));
        await t.pumpAndSettle();
        await t.tap(find.text('شيك').last);
        await t.pumpAndSettle();
        expect(method, 'cheque');
        await t.dragUntilVisible(find.text('فتح السند PDF').hitTestable(),
            find.byType(ListView), const Offset(0, -180));
        await t.pumpAndSettle();
        await t.tap(find.text('فتح السند PDF').hitTestable().first);
        expect(documents, 1);
        if (!receipt) {
          await t.dragUntilVisible(find.text('إلغاء السند').hitTestable(),
              find.byType(ListView), const Offset(0, -80));
          await t.pumpAndSettle();
          await t.tap(find.text('إلغاء السند').hitTestable().first);
          expect(reversals, 1);
        }
        await t.drag(find.byType(ListView), const Offset(0, -400));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
  test('voucher screen source contains Arabic without encoding corruption', () {
    for (final type in ['receipt', 'payment']) {
      final source = File(
              'lib/features/vouchers/screens/${type}_vouchers_list_screen.dart')
          .readAsStringSync();
      expect(source, isNot(contains('ط§')));
      expect(source, isNot(contains('ظ„')));
    }
  });
}
