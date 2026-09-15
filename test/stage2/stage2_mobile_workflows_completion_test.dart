import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  group('Stage 2 mobile workflows source contract', () {
    test('P1-01 payer selection is persisted as the repair payer source', () {
      final addRepair = source(
        'lib/features/repairs/screens/add_repair_screen.dart',
      );
      final intake = source(
        'lib/features/repairs/services/repair_intake_service.dart',
      );
      final bridge = source(
        'lib/features/repairs/services/repair_payer_bridge.dart',
      );

      expect(addRepair, contains(r'[YALLA_PAYER] $_payer'));
      expect(addRepair, contains('أدخل اسم شركة التأمين'));
      expect(intake, contains('RepairPayerBridge.resolve'));
      expect(intake, contains('withInsuranceClientId'));
      expect(intake, contains("'paymentType': payerKind"));
      expect(bridge, contains('insuranceClientIdFromNotes'));
      expect(bridge, contains('insuranceCompanyNameFromNotes'));
    });

    test('P1-02 receipt list has a dedicated phone-first presentation', () {
      final receipts = source(
        'lib/features/vouchers/screens/receipt_vouchers_list_screen.dart',
      );

      expect(receipts, contains('final size = MediaQuery.sizeOf(context);'));
      expect(receipts,
          contains('final isPhone = size.width < 600 || size.height < 520;'));
      expect(receipts, contains('Widget _phoneMain()'));
      expect(receipts, contains('VoucherListPhone('));
      expect(receipts, contains('onRefresh: _load'));
      expect(receipts, contains('_exportReceiptPdf'));
      expect(receipts, contains('P15DocumentService.generateReceiptPdf'));
      expect(receipts, contains('Widget _desktopMain()'));
    });

    test(
        'P1-03 payment list is phone-first without regressing repair scope/reversal',
        () {
      final payments = source(
        'lib/features/finance/payments/screens/payment_list_screen.dart',
      );

      expect(payments, contains('Widget _phoneBody'));
      expect(payments, contains('Widget _phonePaymentCard'));
      expect(payments, contains('initialRepairId'));
      expect(payments, contains('relatedRepairId'));
      expect(payments, contains('PaymentService.reverseReceiptByPaymentId'));
      expect(payments, contains('Widget _desktopBody'));
    });

    test('P1-04 employee card exposes the required phone actions', () {
      final employee = source(
        'lib/features/employees/widgets/employee_card.dart',
      );

      expect(employee, contains('Widget _phoneCard'));
      expect(employee, contains("Text('تعديل')"));
      expect(employee, contains("Text('التقرير الشهري')"));
      expect(employee, contains("Text('كشف الراتب')"));
      expect(employee, contains("'حذف'"));
      expect(employee, contains('onMonthlyReport'));
      expect(employee, contains('onSalarySlip'));
      expect(employee, contains('Widget _desktopCard'));
    });

    test(
        'P1-05 purchase details has a phone action bar and keeps Stage 1 PDF fix',
        () {
      final purchase = source(
        'lib/features/finance/purchases/screens/purchase_details_screen.dart',
      );

      expect(purchase, contains('Widget _phoneContent'));
      expect(purchase, contains('Widget _phoneLinesCard'));
      expect(purchase, contains('Widget _phoneActions'));
      expect(purchase, contains("Text('سند صرف')"));
      expect(purchase, contains("Text('PDF')"));
      expect(purchase, contains("Text('إغلاق')"));
      expect(purchase, contains('STAGE1_RUNTIME_FIX3_PURCHASE_PDF_COLUMNS'));
      expect(purchase, contains('Printing.sharePdf'));
      expect(purchase, contains('Widget _actions'));
    });
  });
}
