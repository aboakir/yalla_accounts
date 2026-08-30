// 📁 lib/features/reports/providers/general_ledger_provider.dart
//
// GeneralLedgerProvider — دفتر أستاذ تفصيلي من GL v28.
// يُرجع الحركات مرتبة بالتاريخ مع رصيد جاري لكل حساب أو عميل.

import 'package:yalla_accounts/core/services/db_service.dart';

class GeneralLedgerRow {
  final String date; // ISO
  final String accountCode;
  final String accountName;
  final String? partyType; // CUSTOMER/SUPPLIER/EMPLOYEE
  final String? partyId;
  final String? ref;
  final String? source;
  final String? note;
  final double debit;
  final double credit;
  final double runningBalance;

  GeneralLedgerRow({
    required this.date,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    this.partyType,
    this.partyId,
    this.ref,
    this.source,
    this.note,
  });
}

class GeneralLedgerProvider {
  /// دفتر الأستاذ لحساب محدد اختيارياً، ونطاق تاريخ اختياري.
  /// إذا لم تُمرر accountCode يعيد كل الحسابات.
  static Future<List<GeneralLedgerRow>> fetch({
    String? accountCode,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await DBService.database;

    final where = <String>[];
    final args = <Object?>[];

    if (accountCode != null && accountCode.trim().isNotEmpty) {
      where.add('a.code = ?');
      args.add(accountCode.trim());
    }
    if (from != null) {
      where.add('ge.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('ge.date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT
        ge.date AS date,
        ge.ref  AS ref,
        ge.source AS source,
        ge.note AS note,
        a.code AS account_code,
        a.name AS account_name,
        gl.party_type, gl.party_id,
        gl.debit, gl.credit
      FROM gl_lines gl
      JOIN gl_entries ge ON ge.id = gl.entry_id
      JOIN accounts a ON a.id = gl.account_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY a.code, ge.date, gl.id
    ''', args);

    // احسب الرصيد الجاري لكل حساب
    final result = <GeneralLedgerRow>[];
    final running = <String, double>{}; // account_code -> balance
    for (final m in rows) {
      final code = (m['account_code'] ?? '').toString();
      final debit = _d(m['debit']);
      final credit = _d(m['credit']);
      final bal = (running[code] ?? 0) + debit - credit;
      running[code] = bal;

      result.add(GeneralLedgerRow(
        date: (m['date'] ?? '').toString(),
        ref: m['ref']?.toString(),
        source: m['source']?.toString(),
        note: m['note']?.toString(),
        accountCode: code,
        accountName: (m['account_name'] ?? '').toString(),
        partyType: m['party_type']?.toString(),
        partyId: m['party_id']?.toString(),
        debit: debit,
        credit: credit,
        runningBalance: _round(bal),
      ));
    }
    return result;
  }

  static double _d(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '0') ?? 0.0;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}
