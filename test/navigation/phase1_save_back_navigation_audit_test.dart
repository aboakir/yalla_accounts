import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

String _source(String path) => File(path).readAsStringSync();

void main() {
  test('Primary save flows return to their real caller', () {
    final contracts = <String, RegExp>{
      'lib/features/cheques/screens/cheque_add_screen.dart':
          RegExp(r'Navigator\.pop\(context,\s*true\)'),
      'lib/features/suppliers/screens/supplier_form_screen.dart':
          RegExp(r'Navigator\.pop\(context,\s*true\)'),
      'lib/features/clients/screens/client_edit_screen.dart':
          RegExp(r'Navigator\.pop\(context,\s*true\)'),
      'lib/features/raw_materials/screens/raw_material_edit_screen.dart':
          RegExp(r'Navigator\.pop\(context,\s*true\)'),
      'lib/features/employees/screens/add_employee_screen.dart':
          RegExp(r'Navigator\.pop\(context\)'),
      'lib/features/employees/screens/edit_employee_screen.dart':
          RegExp(r'Navigator\.pop\(context,\s*true\)'),
      'lib/features/vouchers/screens/receipt_voucher_screen.dart':
          RegExp(r'Navigator\.pop\(context,\s*true\)'),
      'lib/features/vouchers/screens/payment_voucher_screen.dart':
          RegExp(r'Navigator\.of\(context\)\.pop\(true\)'),
    };

    final missing = <String>[];
    for (final entry in contracts.entries) {
      if (!entry.value.hasMatch(_source(entry.key))) {
        missing.add(entry.key);
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Save flows that no longer return to the caller: ${missing.join(', ')}',
    );
  });

  test('Hard-coded named navigation never targets an unregistered route', () {
    final navigation = RegExp(
      r'(?:pushNamed|pushReplacementNamed|pushNamedAndRemoveUntil|popAndPushNamed)'
      r'(?:<[^>]+>)?\s*\(\s*(?:context\s*,\s*)?["'
      '](/[^"'
      ']+)["'
      ']',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in navigation.allMatches(source)) {
        final route = match.group(1)!;
        if (route.contains(r'$')) continue;
        if (!AppRoutes.isRegisteredRoute(route)) {
          offenders.add('${entity.path}: $route');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Named navigation to unregistered routes: ${offenders.join(', ')}',
    );
  });

  test('Save/back paths never use the commercial placeholder as a destination',
      () {
    const files = <String>[
      'lib/features/cheques/screens/cheque_add_screen.dart',
      'lib/features/suppliers/screens/supplier_form_screen.dart',
      'lib/features/clients/screens/client_edit_screen.dart',
      'lib/features/raw_materials/screens/raw_material_edit_screen.dart',
      'lib/features/employees/screens/add_employee_screen.dart',
      'lib/features/employees/screens/edit_employee_screen.dart',
      'lib/features/vouchers/screens/receipt_voucher_screen.dart',
      'lib/features/vouchers/screens/payment_voucher_screen.dart',
    ];
    for (final file in files) {
      final source = _source(file);
      expect(source, isNot(contains('UnderConstructionScreen')),
          reason: 'Placeholder leaked into save/back flow: $file');
    }
  });
}
