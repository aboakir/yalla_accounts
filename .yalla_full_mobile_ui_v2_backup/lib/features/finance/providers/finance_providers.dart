import 'package:flutter_riverpod/flutter_riverpod.dart';

// نماذج وتقارير عامة
import 'package:yalla_accounts/features/finance/models/financial_models.dart';

// فواتير
import 'package:yalla_accounts/features/finance/models/invoice.dart';
import 'package:yalla_accounts/features/finance/services/invoice_database_service.dart'
    as invoice_db;

// خدمات عامة
import 'package:yalla_accounts/features/finance/services/finance_service.dart';
import 'package:yalla_accounts/features/finance/services/finance_events_service.dart';

// ذمم + إصلاحات
import 'package:yalla_accounts/features/finance/models/accounts_receivable_entry.dart';
import 'package:yalla_accounts/features/finance/services/accounts_receivable_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

/// تقارير عامة
final financeDashboardProvider =
    FutureProvider.autoDispose<DashboardStats>((ref) async {
  return FinanceService.getDashboardStats();
});
final balanceSheetProvider =
    FutureProvider.autoDispose<BalanceSheet>((ref) async {
  return FinanceService.getBalanceSheet();
});
final incomeStatementProvider =
    FutureProvider.autoDispose<IncomeStatement>((ref) async {
  return FinanceService.getIncomeStatement();
});
final journalEntriesProvider =
    FutureProvider.autoDispose<List<JournalEntry>>((ref) async {
  return FinanceService.getJournalEntries();
});
final ledgerEntriesProvider =
    FutureProvider.autoDispose<List<LedgerEntry>>((ref) async {
  return FinanceService.getLedgerEntries();
});

/// الدفعات من الذمم المدفوعة
final paymentsProvider =
    FutureProvider.autoDispose<List<PaymentEntry>>((ref) async {
  final arSvc = AccountsReceivableService.instance;

  // كل ملفات الإصلاح لربط اسم المستفيد
  final List<Repair> repairs = await RepairDatabaseService.getAllRepairs();
  final Map<String, Repair> byId = {
    for (final r in repairs) r.id.toString(): r,
  };

  final List<PaymentEntry> out = [];

  for (final r in repairs) {
    final List<AccountsReceivableEntry> entries =
        await arSvc.getEntriesByRepair(r.id.toString());

    for (final e in entries.where((x) => x.isPaid)) {
      final repairKey = e.repairId ?? r.id.toString();
      final rr = byId[repairKey] ?? r;

      // التاريخ: أولوية لتاريخ الدفع ثم تاريخ القيد
      final String paidIso = e.paidDate ?? e.date ?? '';
      final DateTime paidAt = DateTime.tryParse(paidIso) ?? DateTime.now();

      // معرف الدفع الآمن
      final paymentId = e.id ??
          '$repairKey-${paidAt.toIso8601String()}-${e.amount.toStringAsFixed(2)}';

      // اسم الدافع
      final bool hasCustomer =
          (e.customer != null && e.customer!.trim().isNotEmpty);
      final String payee = hasCustomer
          ? e.customer!.trim()
          : (rr.beneficiaryName.trim().isNotEmpty
              ? rr.beneficiaryName
              : 'غير معروف');

      // طريقة الدفع
      final String method = (e.method != null && e.method!.trim().isNotEmpty)
          ? e.method!.trim()
          : 'غير محدد';

      out.add(
        PaymentEntry(
          id: paymentId,
          date: paidAt,
          payee: payee,
          amount: e.amount,
          method: method,
        ),
      );
    }
  }

  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
});

/// الضرائب
final taxReportProvider = FutureProvider.autoDispose<TaxReport>((ref) async {
  return FinanceService.getTaxReport();
});

/// فواتير
final invoiceByIdProvider =
    FutureProvider.autoDispose.family<Invoice?, String>((ref, invoiceId) async {
  return invoice_db.InvoiceDatabaseService.instance.getById(invoiceId);
});

final invoicesForRepairProvider = FutureProvider.autoDispose
    .family<List<Invoice>, String>((ref, repairId) async {
  final inv =
      await invoice_db.InvoiceDatabaseService.instance.getByRepairId(repairId);
  if (inv == null) return [];
  return [inv];
});

final latestInvoiceForRepairProvider =
    FutureProvider.autoDispose.family<Invoice?, String>((ref, repairId) async {
  return invoice_db.InvoiceDatabaseService.instance.getByRepairId(repairId);
});

/// Use-case: تسجيل دفعة
typedef RecordPaymentFn = Future<void> Function(
  String invoiceId,
  double amount,
  DateTime date, {
  String method,
  String? notes,
});

final recordPaymentUseCaseProvider = Provider<RecordPaymentFn>((ref) {
  return (String invoiceId, double amount, DateTime date,
      {String method = 'cash', String? notes}) async {
    final svc = await FinanceEventsService.start();
    await svc.recordPayment(
      invoiceId: invoiceId,
      amount: amount,
      date: date,
      method: method,
      notes: notes,
    );

    ref.invalidate(financeDashboardProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(invoiceByIdProvider(invoiceId));
  };
});
