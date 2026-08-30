import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/insurance/providers/insurance_invoice_provider.dart';
import 'insurance_invoice_edit_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class InsuranceInvoiceListScreen extends ConsumerWidget {
  const InsuranceInvoiceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(insuranceInvoiceListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('فواتير التأمين'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const InsuranceInvoiceEditScreen(),
            ),
          );
          if (result == true) {
            await ref
                .read(insuranceInvoiceListProvider.notifier)
                .loadInvoices();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: invoices.isEmpty
          ? const Center(child: Text('لا توجد فواتير'))
          : ListView.builder(
              itemCount: invoices.length,
              itemBuilder: (context, index) {
                final invoice = invoices[index];
                return ListTile(
                  title: Text(invoice.invoiceNumber),
                  subtitle: Text(
                      '${invoice.clientName} - ${invoice.insuranceCompany}'),
                  trailing: AdaptiveRow(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  InsuranceInvoiceEditScreen(invoice: invoice),
                            ),
                          );
                          if (result == true) {
                            await ref
                                .read(insuranceInvoiceListProvider.notifier)
                                .loadInvoices();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final idStr = invoice.id?.toString();
                          if (idStr != null && idStr.isNotEmpty) {
                            await ref
                                .read(insuranceInvoiceListProvider.notifier)
                                .deleteInvoice(idStr);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
