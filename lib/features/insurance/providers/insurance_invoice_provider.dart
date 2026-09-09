import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/insurance/models/insurance_invoice.dart';
import 'package:yalla_accounts/features/insurance/services/insurance_invoice_service.dart';

final insuranceInvoiceListProvider = StateNotifierProvider<
    InsuranceInvoiceListNotifier, AsyncValue<List<InsuranceInvoice>>>(
  (ref) => InsuranceInvoiceListNotifier(),
);

class InsuranceInvoiceListNotifier
    extends StateNotifier<AsyncValue<List<InsuranceInvoice>>> {
  InsuranceInvoiceListNotifier() : super(const AsyncLoading()) {
    loadInvoices();
  }

  Future<void> loadInvoices() async {
    state = const AsyncLoading();
    final result =
        await AsyncValue.guard(InsuranceInvoiceService.getAllInvoices);
    if (mounted) state = result;
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
