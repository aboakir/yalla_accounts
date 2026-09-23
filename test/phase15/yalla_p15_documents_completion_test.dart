import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/utils/public_text_sanitizer.dart';

void main() {
  group('P15 public document contracts', () {
    test('internal YALLA markers never survive public sanitization', () {
      final value = PublicTextSanitizer.sanitize('''
[YALLA_SCOPE] كامل
ملاحظة العميل الحقيقية
[YALLA_PAYER] شركة تأمين
[YALLA_WORKS_TOTAL] 4000
''');
      expect(value, 'ملاحظة العميل الحقيقية');
      expect(value, isNot(contains('[YALLA_')));
    });

    test('Repair PDF uses P10 financial truth + canonical repair lines', () {
      final source = File(
        'lib/features/repairs/services/repair_pdf_generator.dart',
      ).readAsStringSync();
      expect(source, contains('RepairFinancialTruthService.load(repair.id)'));
      expect(source, contains('RepairLineBridge.load(repair.id)'));
      expect(source, contains('final grandTotal = truth.fileValue;'));
      expect(source, contains('final paid = truth.paid;'));
      expect(source, contains('final remaining = truth.remaining;'));
      expect(source, contains("row['total']"));
      expect(source, contains('PublicTextSanitizer.sanitize(repair.notes)'));
      expect(source, isNot(contains(r'"ملاحظات: ${repair.notes')));
    });

    test('official invoice PDF reads posted invoice totals, not repair total',
        () {
      final source = File(
        'lib/features/documents/services/p15_document_service.dart',
      ).readAsStringSync();
      expect(source, contains('FROM invoices i'));
      expect(source, contains("_money(inv['subtotal'])"));
      expect(source, contains("_money(inv['total'])"));
      expect(source, contains("_money(inv['paid'])"));
      expect(source, contains('receipt_headers'));
      expect(source, contains('receipt_allocations'));
      expect(source, contains('CustomerAccountStatement statement'));
    });

    test('invoice and customer statement screens expose PDF/print/share', () {
      final invoice = File(
        'lib/features/finance/invoices/screens/invoice_view_screen.dart',
      ).readAsStringSync();
      final statement = File(
        'lib/features/account_statements/customers/screens/customer_account_statement_screen.dart',
      ).readAsStringSync();
      expect(invoice, contains('generateCustomerInvoicePdf'));
      expect(invoice, contains('YallaPdfPrintService.layoutPdf'));
      expect(invoice, contains('Printing.sharePdf'));
      expect(statement, contains('generateCustomerStatementPdf'));
      expect(statement, contains('YallaPdfPrintService.layoutPdf'));
      expect(statement, contains('Printing.sharePdf'));
    });

    test('P11 receipt PDF is rendered from header and allocations', () {
      final source = File(
        'lib/features/vouchers/screens/receipt_vouchers_list_screen.dart',
      ).readAsStringSync();
      expect(source, contains('P15DocumentService.generateReceiptPdf'));
      expect(source, contains("receipt_number"));
    });

    test(
        'global search sanitizes metadata and includes P15 operational sources',
        () {
      final source = File(
        'lib/core/services/global_search_service.dart',
      ).readAsStringSync();
      expect(source, contains('PublicTextSanitizer.sanitize'));
      expect(source, contains('_searchReceipts'));
      expect(source, contains('_searchCheques'));
      expect(source, contains('_searchPurchases'));

      final screen = File(
        'lib/features/search/screens/global_search_screen.dart',
      ).readAsStringSync();
      expect(screen, contains('AppRoutes.invoiceView'));
      expect(screen, contains('AppRoutes.receiptVouchersList'));
      expect(screen, contains('AppRoutes.chequesList'));
      expect(screen, contains('AppRoutes.chequesEdit'));
      expect(screen, contains('AppRoutes.purchasesList'));
    });

    test('owner reports hub routes to real existing reports', () {
      final source = File(
        'lib/features/reports/screens/reports_dashboard_screen.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('غير متاح مؤقتًا')));
      expect(source, contains('AppRoutes.incomeStatement'));
      expect(source, contains('AppRoutes.reportsBalanceSheet'));
      expect(source, contains('AppRoutes.reportsTrialBalance'));
      expect(source, contains('AppRoutes.reportsGeneralLedger'));
      expect(source, contains('AppRoutes.reportsARAging'));
    });
  });
}
