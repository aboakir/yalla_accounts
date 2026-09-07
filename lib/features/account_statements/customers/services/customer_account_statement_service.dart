import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/parties/services/party_financial_service.dart';

class CustomerStatementLine {
  const CustomerStatementLine({
    required this.entryId,
    required this.date,
    required this.source,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.repairId,
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
  final String? repairId;
  final String? invoiceId;
}

class CustomerAccountStatement {
  const CustomerAccountStatement({
    required this.clientId,
    required this.clientName,
    required this.openingBalance,
    required this.closingBalance,
    required this.lines,
  });

  final int clientId;
  final String clientName;
  final double openingBalance;
  final double closingBalance;
  final List<CustomerStatementLine> lines;
}

class CustomerAccountStatementService {
  CustomerAccountStatementService._();

  static Future<CustomerAccountStatement> load({
    required int clientId,
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    final statement = await PartyFinancialService.statement(
      role: 'CUSTOMER',
      legacyId: clientId,
      from: from,
      to: to,
      executor: executor,
    );

    return CustomerAccountStatement(
      clientId: clientId,
      clientName: statement.displayName,
      openingBalance: statement.openingBalance,
      closingBalance: statement.closingBalance,
      lines: statement.lines
          .map((line) => CustomerStatementLine(
                entryId: line.entryId,
                date: line.date,
                source: line.source,
                reference: line.sourceNumber,
                description: line.description,
                debit: line.debit,
                credit: line.credit,
                balance: line.runningBalance,
                repairId: line.repairId,
                invoiceId: line.invoiceId,
              ))
          .toList(growable: false),
    );
  }
}
