import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

final supplierPayablesProvider =
    FutureProvider<List<SupplierPayableSummary>>((ref) async {
  final balances = await PartyFinancialService.balances();
  return balances
      .where((p) => p.supplierLegacyId != null)
      .map((p) => SupplierPayableSummary(
            supplierId: p.supplierLegacyId!,
            supplierPid:
                'S${int.tryParse(p.supplierLegacyId!)?.toString().padLeft(4, '0') ?? p.supplierLegacyId}',
            supplierName: p.displayName,
            total: p.totalPayable,
            paid: p.paid,
            remain: p.payableBalance,
          ))
      .toList(growable: false);
});

final singleSupplierPayablesProvider =
    FutureProvider.family<List<SupplierInvoiceRow>, String>(
        (ref, supplierId) async {
  final statement = await PartyFinancialService.statement(
    role: 'SUPPLIER',
    legacyId: supplierId,
  );
  return statement.lines
      .where((line) => line.invoiceId != null)
      .map((line) => SupplierInvoiceRow(
            invoiceId: line.invoiceId!,
            date: line.date.toIso8601String(),
            total: line.debit,
            paid: line.credit,
            remain: line.runningBalance,
          ))
      .toList(growable: false);
});

class SupplierPayableSummary {
  final String supplierId;
  final String supplierPid;
  final String supplierName;
  final double total;
  final double paid;
  final double remain;

  const SupplierPayableSummary({
    required this.supplierId,
    required this.supplierPid,
    required this.supplierName,
    required this.total,
    required this.paid,
    required this.remain,
  });
}

class SupplierInvoiceRow {
  final String invoiceId;
  final String date;
  final double total;
  final double paid;
  final double remain;

  const SupplierInvoiceRow({
    required this.invoiceId,
    required this.date,
    required this.total,
    required this.paid,
    required this.remain,
  });
}
