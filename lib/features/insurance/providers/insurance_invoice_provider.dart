import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/insurance/models/insurance_invoice.dart';
import 'package:yalla_accounts/features/insurance/services/insurance_invoice_service.dart';

final insuranceInvoiceListProvider =
    StateNotifierProvider<InsuranceInvoiceListNotifier, List<InsuranceInvoice>>(
  (ref) => InsuranceInvoiceListNotifier(),
);

class InsuranceInvoiceListNotifier
    extends StateNotifier<List<InsuranceInvoice>> {
  InsuranceInvoiceListNotifier() : super([]) {
    loadInvoices();
  }

  Future<void> loadInvoices() async {
    final invoices = await InsuranceInvoiceService.getAllInvoices();
    state = invoices;
  }

  Future<void> addInvoice(InsuranceInvoice invoice) async {
    await InsuranceInvoiceService.insertInvoice(invoice);
    await loadInvoices();
  }

  Future<void> updateInvoice(InsuranceInvoice invoice) async {
    await InsuranceInvoiceService.updateInvoice(invoice);
    await loadInvoices();
  }

  Future<void> deleteInvoice(String id) async {
    await InsuranceInvoiceService.deleteInvoice(id);
    await loadInvoices();
  }
}
