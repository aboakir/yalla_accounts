import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class SupplierAgingRow {
  const SupplierAgingRow({
    required this.supplierId,
    required this.supplierName,
    required this.b0_30,
    required this.b31_60,
    required this.b61_90,
    required this.b91_120,
    required this.b120p,
    required this.total,
    this.advanceBalance = 0,
  });

  final String supplierId;
  final String supplierName;
  final double b0_30;
  final double b31_60;
  final double b61_90;
  final double b91_120;
  final double b120p;
  final double total;
  final double advanceBalance;
}

class SupplierAgingProvider {
  SupplierAgingProvider._();
  static Future<List<SupplierAgingRow>> fetch({
    required DateTime asOf,
    String query = '',
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final day = DateTime(asOf.year, asOf.month, asOf.day);
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
    final nextDayIso = day.add(const Duration(days: 1)).toIso8601String();
    final term = query.trim();

    final whereSearch = term.isEmpty
        ? ''
        : '''AND (
          LOWER(COALESCE(p.display_name, s.name, '')) LIKE LOWER(?)
          OR COALESCE(pr.legacy_id, CAST(v.legacy_party_id AS TEXT)) LIKE ?
          OR CAST(v.legacy_party_id AS TEXT) LIKE ?
        )''';
    final args = <Object?>[
      nextDayIso,
      if (term.isNotEmpty) '%$term%',
      if (term.isNotEmpty) '%$term%',
      if (term.isNotEmpty) '%$term%',
    ];

    final rows = await db.rawQuery('''
      SELECT
        e.date AS date,
        v.debit AS debit,
        v.credit AS credit,
        COALESCE(pr.legacy_id, CAST(v.legacy_party_id AS TEXT)) AS supplier_id,
        COALESCE(p.display_name, s.name, 'مورد') AS supplier_name
      FROM v_party_gl_lines v
      JOIN gl_entries e ON e.id = v.entry_id
      JOIN accounts a ON a.id = v.account_id
      LEFT JOIN parties p ON p.id = v.canonical_party_id
      LEFT JOIN party_roles pr
        ON pr.party_id = v.canonical_party_id AND pr.role = 'SUPPLIER'
      LEFT JOIN suppliers s ON CAST(s.id AS TEXT) = pr.legacy_id
      WHERE (
        a.code = '2100'
        OR a.code = '2200'
        OR a.code GLOB '2200.S[0-9]*'
      )
        AND e.date < ?
        AND v.party_role = 'SUPPLIER'
        AND v.canonical_party_id IS NOT NULL
        $whereSearch
      ORDER BY e.date ASC, e.id ASC, v.gl_line_id ASC
    ''', args);

    final suppliers = <String, _SupplierBucket>{};
    for (final row in rows) {
      final id = (row['supplier_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final name = (row['supplier_name'] ?? 'مورد').toString();
      final record =
          suppliers.putIfAbsent(id, () => _SupplierBucket(id, name));

      final date =
          DateTime.tryParse((row['date'] ?? '').toString()) ?? end;
      final debit = _toDouble(row['debit']);
      final credit = _toDouble(row['credit']);

      if (credit > 0) {
        record.obligations.add(_Leg(date: date, amount: credit));
      }
      if (debit > 0) {
        record.reliefs.add(_Leg(date: date, amount: debit));
      }
    }

    for (final record in suppliers.values) {
      record.obligations.sort((a, b) => a.date.compareTo(b.date));
      var reliefPool =
          record.reliefs.fold<double>(0, (sum, item) => sum + item.amount);
      for (final obligation in record.obligations) {
        if (reliefPool <= 0) break;
        final take = obligation.remaining <= reliefPool
            ? obligation.remaining
            : reliefPool;
        obligation.remaining = _money(obligation.remaining - take);
        reliefPool = _money(reliefPool - take);
      }
      record.advanceBalance = _money(reliefPool);

      for (final obligation in record.obligations) {
        final remaining = obligation.remaining;
        if (remaining <= 0) continue;
        final days = end.difference(obligation.date).inDays;
        if (days <= 30) {
          record.b0_30 += remaining;
        } else if (days <= 60) {
          record.b31_60 += remaining;
        } else if (days <= 90) {
          record.b61_90 += remaining;
        } else if (days <= 120) {
          record.b91_120 += remaining;
        } else {
          record.b120p += remaining;
        }
      }
    }
    final result = suppliers.values
        .map((record) => record.toRow())
        .where((row) => row.total > 0.000001)
        .toList(growable: false)
      ..sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _money(double value) =>
      double.parse(value.toStringAsFixed(2));
}

class _Leg {
  _Leg({required this.date, required this.amount}) : remaining = amount;

  final DateTime date;
  final double amount;
  double remaining;
}

class _SupplierBucket {
  _SupplierBucket(this.id, this.name);

  final String id;
  final String name;
  final List<_Leg> obligations = [];
  final List<_Leg> reliefs = [];

  double b0_30 = 0;
  double b31_60 = 0;
  double b61_90 = 0;
  double b91_120 = 0;
  double b120p = 0;
  double advanceBalance = 0;

  SupplierAgingRow toRow() {
    final total = SupplierAgingProvider._money(
      b0_30 + b31_60 + b61_90 + b91_120 + b120p,
    );
    return SupplierAgingRow(
      supplierId: id,
      supplierName: name,
      b0_30: SupplierAgingProvider._money(b0_30),
      b31_60: SupplierAgingProvider._money(b31_60),
      b61_90: SupplierAgingProvider._money(b61_90),
      b91_120: SupplierAgingProvider._money(b91_120),
      b120p: SupplierAgingProvider._money(b120p),
      total: total,
      advanceBalance: SupplierAgingProvider._money(advanceBalance),
    );
  }
}
