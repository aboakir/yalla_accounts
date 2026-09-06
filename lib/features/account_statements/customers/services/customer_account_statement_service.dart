import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

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

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _i(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Future<CustomerAccountStatement> load({
    required int clientId,
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final clients = await db.query(
      'clients',
      columns: const ['name'],
      where: 'id=?',
      whereArgs: [clientId],
      limit: 1,
    );
    final clientName = clients.isEmpty
        ? 'عميل $clientId'
        : (clients.first['name'] ?? '').toString();

    final fromIso = from?.toIso8601String();
    final toIso = to == null
        ? null
        : DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();

    var opening = 0.0;
    if (fromIso != null) {
      final openingRows = await db.rawQuery('''
        SELECT COALESCE(SUM(l.debit-l.credit),0) AS balance
        FROM gl_lines l
        JOIN gl_entries e ON e.id=l.entry_id
        LEFT JOIN accounts a ON a.id=l.account_id
        LEFT JOIN clients c ON c.account_id=l.account_id
        WHERE e.date < ?
          AND (a.code LIKE '1200%' OR c.id=?)
          AND (
            c.id=?
            OR (
              UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
              AND CAST(l.party_id AS INTEGER)=?
            )
          )
      ''', [fromIso, clientId, clientId, clientId]);
      opening = openingRows.isEmpty ? 0.0 : _d(openingRows.first['balance']);
    }

    final where = <String>[
      "(a.code LIKE '1200%' OR c.id=?)",
      "(c.id=? OR (UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER') AND CAST(l.party_id AS INTEGER)=?))",
    ];
    final args = <Object?>[clientId, clientId, clientId];
    if (fromIso != null) {
      where.add('e.date >= ?');
      args.add(fromIso);
    }
    if (toIso != null) {
      where.add('e.date <= ?');
      args.add(toIso);
    }

    final rows = await db.rawQuery('''
      SELECT
        e.id AS entry_id,
        e.date AS date,
        e.source AS source,
        e.source_id AS source_id,
        e.source_number AS source_number,
        e.note AS note,
        e.reversal_of AS reversal_of,
        l.debit AS debit,
        l.credit AS credit,
        l.repair_id AS repair_id,
        l.invoice_id AS invoice_id
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      LEFT JOIN accounts a ON a.id=l.account_id
      LEFT JOIN clients c ON c.account_id=l.account_id
      WHERE ${where.join(' AND ')}
      ORDER BY e.date ASC, e.id ASC, l.id ASC
    ''', args);

    var running = opening;
    final lines = <CustomerStatementLine>[];
    for (final row in rows) {
      final debit = _d(row['debit']);
      final credit = _d(row['credit']);
      running = double.parse((running + debit - credit).toStringAsFixed(2));
      final source = (row['source'] ?? '').toString();
      final sourceNumber = (row['source_number'] ?? '').toString().trim();
      final sourceId = (row['source_id'] ?? '').toString().trim();
      final reference = sourceNumber.isNotEmpty ? sourceNumber : sourceId;
      lines.add(CustomerStatementLine(
        entryId: _i(row['entry_id']),
        date:
            DateTime.tryParse(row['date']?.toString() ?? '') ?? DateTime.now(),
        source: source,
        reference: reference,
        description: _description(source, row),
        debit: debit,
        credit: credit,
        balance: running,
        repairId: row['repair_id']?.toString(),
      ));
    }

    return CustomerAccountStatement(
      clientId: clientId,
      clientName: clientName,
      openingBalance: double.parse(opening.toStringAsFixed(2)),
      closingBalance: double.parse(running.toStringAsFixed(2)),
      lines: lines,
    );
  }

  static String _description(String source, Map<String, Object?> row) {
    final upper = source.toUpperCase();
    if (row['reversal_of'] != null || upper.contains('REVERS'))
      return 'عكس حركة مالية';
    if (upper.contains('RECEIPT') || upper.contains('PAYMENT'))
      return 'سند قبض / تحصيل';
    if (upper.contains('REPAIR_VALUE_ADJ')) return 'تعديل قيمة ملف إصلاح';
    if (upper.contains('INVOICE')) return 'فاتورة / إثبات ذمة';
    if (upper.contains('CREDIT')) return 'رصيد دائن / تخصيص رصيد';
    final note = (row['note'] ?? '').toString().trim();
    return note.isEmpty ? source : note;
  }
}
