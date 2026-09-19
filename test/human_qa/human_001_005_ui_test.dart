import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/theme/yalla_button_themes.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_delete_image_confirm_dialog.dart';

void main() {
  testWidgets('TEST-UI-001..003 image delete dialog is readable and actionable',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        elevatedButtonTheme: YallaButtonThemes.elevated,
        textButtonTheme: YallaButtonThemes.text,
      ),
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<bool>(
              context: context,
              builder: (_) => const RepairDeleteImageConfirmDialog(),
            );
          },
          child: const Text('فتح'),
        );
      }),
    ));
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الصورة'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  test('TEST-UI-004..006 shared button colors preserve readable contrast', () {
    final elevated = YallaButtonThemes.elevated.style!;
    final filled = YallaButtonThemes.filled.style!;
    expect(elevated.backgroundColor!.resolve({}), AppColors.primary);
    expect(elevated.foregroundColor!.resolve({}), Colors.white);
    expect(filled.backgroundColor!.resolve({}), AppColors.primary);
    expect(filled.foregroundColor!.resolve({}), Colors.white);
    expect(
      elevated.backgroundColor!.resolve({MaterialState.disabled}),
      isNot(elevated.foregroundColor!.resolve({MaterialState.disabled})),
    );
    expect(
      filled.backgroundColor!.resolve({MaterialState.disabled}),
      isNot(filled.foregroundColor!.resolve({MaterialState.disabled})),
    );
  });

  test('TEST-UI-007 employee details keeps all action labels', () {
    final source = File(
      'lib/features/employees/screens/employee_details_screen.dart',
    ).readAsStringSync();
    expect(source, contains("label: const Text('تعديل البيانات العامة')"));
    expect(source, contains("label: const Text('تعديل الراتب')"));
    expect(source, contains("label: const Text('الرواتب')"));
  });

  test('TEST-UI-008 employee forms keep readable save actions', () {
    final add = File(
      'lib/features/employees/screens/add_employee_screen.dart',
    ).readAsStringSync();
    final edit = File(
      'lib/features/employees/screens/edit_employee_screen.dart',
    ).readAsStringSync();
    expect(add, contains("label: const Text('حفظ نهائي')"));
    expect(edit, contains("label: const Text('حفظ التعديلات')"));
  });
}
