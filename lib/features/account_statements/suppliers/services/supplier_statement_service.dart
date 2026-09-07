import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

class SupplierStatementLine {
  const SupplierStatementLine({
    required this.entryId,
    required this.date,
    required this.source,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.invoiceId,
  });

  final int entryId;
  final DateTime date;
  final String source;
  final String reference;
  final String description;
  final double debit;
  final double credit;
  final double balance;
  final String? invoiceId;
}

class SupplierAccountStatement {
  const SupplierAccountStatement({
    required this.supplierId,
    required this.supplierName,
    required this.openingBalance,
    required this.closingBalance,
    required this.lines,
  });

  final String supplierId;
  final String supplierName;
  final double openingBalance;
  final double closingBalance;
  final List<SupplierStatementLine> lines;
}

class SupplierStatementService {
  SupplierStatementService._();

  static Future<SupplierAccountStatement> load({
    required String supplierId,
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    final statement = await PartyFinancialService.statement(
      role: 'SUPPLIER',
      legacyId: supplierId,
      from: from,
      to: to,
      executor: executor,
    );
    return SupplierAccountStatement(
      supplierId: supplierId,
      supplierName: statement.displayName,
      openingBalance: statement.openingBalance,
      closingBalance: statement.closingBalance,
      lines: statement.lines
          .map((line) => SupplierStatementLine(
                entryId: line.entryId,
                date: line.date,
                source: line.source,
                reference: line.sourceNumber,
                description: line.description,
                debit: line.debit,
                credit: line.credit,
                balance: line.runningBalance,
                invoiceId: line.invoiceId,
              ))
          .toList(growable: false),
    );
  }
}
