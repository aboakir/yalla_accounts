// 📁 lib/features/finance/models/financial_models.dart

/// نموذج إحصائيات لوحة القيادة
class DashboardStats {
  final double totalRevenue;
  final double totalExpenses;
  final double netIncome;
  final double totalAssets;
  final double totalLiabilities;

  DashboardStats({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netIncome,
    required this.totalAssets,
    required this.totalLiabilities,
  });
}

/// نموذج ميزانية عمومية (Balance Sheet)
class BalanceSheet {
  final List<BalanceItem> assets;
  final List<BalanceItem> liabilities;
  final double totalAssets;
  final double totalLiabilities;
  final double equity;

  BalanceSheet({
    required this.assets,
    required this.liabilities,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.equity,
  });
}

class BalanceItem {
  final String name;
  final double amount;

  BalanceItem({
    required this.name,
    required this.amount,
  });
}

/// نموذج قائمة الدخل (Income Statement)
class IncomeStatement {
  final List<IncomeItem> revenues;
  final List<IncomeItem> expenses;
  final double totalRevenues;
  final double totalExpenses;
  final double netProfit;

  IncomeStatement({
    required this.revenues,
    required this.expenses,
    required this.totalRevenues,
    required this.totalExpenses,
    required this.netProfit,
  });
}

class IncomeItem {
  final String name;
  final double amount;

  IncomeItem({
    required this.name,
    required this.amount,
  });
}

/// نموذج قيود اليومية (Journal Entry)
class JournalEntry {
  final String id;
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final String account;

  JournalEntry({
    required this.id,
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.account,
  });
}

/// نموذج القيد في الدفتر العام (Ledger Entry)
class LedgerEntry {
  final String id;
  final DateTime date;
  final String account;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  LedgerEntry({
    required this.id,
    required this.date,
    required this.account,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}

/// نموذج الدفعات (Payment Entry)
class PaymentEntry {
  final String id;
  final DateTime date;
  final String payee;
  final double amount;
  final String method;

  PaymentEntry({
    required this.id,
    required this.date,
    required this.payee,
    required this.amount,
    required this.method,
  });
}

/// نموذج تقرير الضرائب (Tax Report)
class TaxReport {
  final double taxableIncome;
  final double taxRate;
  final double taxDue;

  TaxReport({
    required this.taxableIncome,
    required this.taxRate,
    required this.taxDue,
  });
}
