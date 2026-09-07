import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('Stage 3 receivables and payables read canonical Party/GL truth', () {
    final service =
        read('lib/features/parties/services/party_financial_service.dart');
    final ar =
        read('lib/features/finance/screens/accounts_receivable_screen.dart');
    final supplier = read(
        'lib/features/suppliers/providers/supplier_payables_provider.dart');
    expect(service, contains('v_party_gl_lines'));
    expect(service, contains('party_roles'));
    expect(service, contains('linkCustomerAndSupplier'));
    expect(ar, contains('PartyFinancialService.balances'));
    expect(supplier, contains('PartyFinancialService.balances'));
  });

  test(
      'Stage 3 statements expose public document numbers, not technical GL ids',
      () {
    final customer = read(
        'lib/features/account_statements/customers/services/customer_account_statement_service.dart');
    final supplier = read(
        'lib/features/account_statements/suppliers/services/supplier_statement_service.dart');
    final supplierScreen =
        read('lib/features/suppliers/screens/supplier_account_screen.dart');
    expect(customer, contains('sourceNumber'));
    expect(supplier, contains('sourceNumber'));
    expect(supplierScreen, isNot(contains("source_id']")));
    expect(supplierScreen, isNot(contains('GL ID')));
  });

  test('Stage 3 basic statement PDFs support summary and detailed modes', () {
    final docs =
        read('lib/features/documents/services/p15_document_service.dart');
    final customerScreen = read(
        'lib/features/account_statements/customers/screens/customer_account_statement_screen.dart');
    final supplierScreen =
        read('lib/features/suppliers/screens/supplier_account_screen.dart');
    expect(docs, contains('bool detailed = true'));
    expect(customerScreen, contains('PDF مختصر'));
    expect(customerScreen, contains('PDF مفصل'));
    expect(supplierScreen, contains('PDF مختصر'));
    expect(supplierScreen, contains('PDF مفصل'));
  });
}
