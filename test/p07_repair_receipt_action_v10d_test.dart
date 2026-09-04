import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P07 repair receipt action V10D', () {
    test('repair quick action hides when settled and opens receipt voucher',
        () {
      final source = File(
        'lib/features/repairs/screens/repairs_screen.dart',
      ).readAsStringSync();

      expect(source, contains('if (r.remainingAmount > 0.005)'));
      expect(source, contains("title: const Text('إضافة دفعة للملف')"));
      expect(source, contains('AppRoutes.receiptVoucher'));
      expect(source, isNot(contains("title: const Text('دفعات هذا الملف')")));
    });

    test('receipt voucher supports preselected repair context', () {
      final source = File(
        'lib/features/vouchers/screens/receipt_voucher_screen.dart',
      ).readAsStringSync();

      expect(source, contains('final String? initialRepairId;'));
      expect(source, contains('await _applyInitialRepairPrefill();'));
      expect(source, contains('if (remaining <= 0.005) return;'));
      expect(source, contains('selectedRepairs = <_RepairItem>['));
    });

    test('receipt voucher route forwards repair context', () {
      final source = File('lib/core/routes/app_routes.dart').readAsStringSync();

      expect(source, contains('ReceiptVoucherScreen('));
      expect(source, contains("args['repairId'] ?? args['relatedRepairId']"));
      expect(source, contains('initialClientId: clientId'));
    });
  });
}
