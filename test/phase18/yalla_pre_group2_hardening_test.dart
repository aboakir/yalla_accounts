import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/services/accounting_gl.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Pre Group-2 hardening', () {
    test('canonical GL account codes remain financially stable', () {
      expect(GL.cash, '1000');
      expect(GL.bank, '1010');
      expect(GL.receivedCheques, '1020');
      expect(GL.arMaster, '1200');
      expect(GL.apMaster, '2200');
      expect(GL.otherExpense, '5900');
    });

    test('finance posting services do not redeclare raw core account codes',
        () {
      final targets = <String>[
        'lib/features/finance/purchases/services/purchase_service.dart',
        'lib/features/finance/purchases/services/purchase_payment_service.dart',
        'lib/features/finance/purchases/services/supplier_payment_service.dart',
        'lib/features/finance/payments/services/payment_service.dart',
      ];

      final rawAccountDeclaration = RegExp(
        r'''static\s+const[^\n=]*_ACC_[A-Z0-9_]*\s*=\s*["'][0-9]{4}["']''',
      );

      for (final path in targets) {
        final source = _read(path);
        expect(
          rawAccountDeclaration.hasMatch(source),
          isFalse,
          reason:
              '$path must use the canonical GL facade, not local account-code literals.',
        );
        expect(
          source.contains('GL.cash') || source.contains('GL.bank'),
          isTrue,
          reason: '$path should reference canonical GL account codes.',
        );
      }
    });

    test('runtime source never suppresses async BuildContext safety lint', () {
      final lib = Directory('lib');
      final offenders = <String>[];

      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('ignore: use_build_context_synchronously') ||
            source
                .contains('ignore_for_file: use_build_context_synchronously')) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Fix async-context lifetime safety instead of suppressing the lint.',
      );
    });

    test('high-risk async save/export flows include mounted guards', () {
      final required = <String, String>{
        'lib/features/suppliers/screens/supplier_account_screen.dart':
            'if (!mounted) return;',
        'lib/features/inventory/screens/inventory_edit_screen.dart':
            'if (!mounted) return;',
        'lib/features/insurance/screens/insurance_invoice_edit_screen.dart':
            'if (!mounted) return;',
        'lib/features/repairs/screens/add_payment_screen.dart':
            'if (!mounted) return;',
        'lib/features/repairs/screens/repairs_and_ar_screen.dart':
            'if (!context.mounted) return;',
        'lib/features/repairs/providers/repair_form_provider.dart':
            'if (!context.mounted) return false;',
        'lib/features/insurance_agent/policies/screens/policy_payments_screen.dart':
            'if (!context.mounted) return;',
      };

      for (final entry in required.entries) {
        expect(
          _read(entry.key),
          contains(entry.value),
          reason: '${entry.key} must protect context/state after async gaps.',
        );
      }
    });
  });
}
