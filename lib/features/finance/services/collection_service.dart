import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class CollectionDueItem {
  const CollectionDueItem({
    required this.repairId,
    required this.clientId,
    required this.clientName,
    required this.vehicleLabel,
    required this.amount,
    required this.dueDate,
  });

  final String repairId;
  final int clientId;
  final String clientName;
  final String vehicleLabel;
  final double amount;
  final DateTime dueDate;

  bool get isOverdue => _dateOnly(dueDate).isBefore(_dateOnly(DateTime.now()));
  int get daysUntilDue =>
      _dateOnly(dueDate).difference(_dateOnly(DateTime.now())).inDays;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class CollectionSnapshot {
  const CollectionSnapshot({
    required this.totalAr,
    required this.overdueAmount,
    required this.dueSoonAmount,
    required this.customerCredit,
    required this.dueCheques,
    required this.returnedCheques,
    required this.items,
  });

  final double totalAr;
  final double overdueAmount;
  final double dueSoonAmount;
  final double customerCredit;
  final int dueCheques;
  final int returnedCheques;
  final List<CollectionDueItem> items;
}

class CollectionAlertRecord {
  const CollectionAlertRecord({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.severity,
  });

  final String id;
  final String message;
  final DateTime timestamp;
  final String severity;
}

/// P12 canonical collection layer.
///
/// Financial amount truth remains GL/P10. This service only adds collection
/// scheduling (due dates) and collection-oriented projections/alerts.
class CollectionService {
  CollectionService._();

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _i(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static Future<DatabaseExecutor> _db(DatabaseExecutor? executor) async =>
      executor ?? await DBService.database;

  static Future<void> ensureSchema({DatabaseExecutor? executor}) async {
    final db = await _db(executor);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS collection_due_dates (
        repair_id TEXT PRIMARY KEY,
        due_date TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'default_30d',
        notes TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_collection_due_date ON collection_due_dates(due_date)',
    );
  }

  /// Default is 30 days from the first financial recognition date when
  /// available, otherwise 30 days from the repair intake date. It is stored
  /// once and remains user-editable; collection screens never keep using
  /// receivedDate as the overdue test directly.
  static Future<DateTime> ensureRepairDueDate(
    String repairId, {
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await ensureSchema(executor: db);

    final existing = await db.query(
      'collection_due_dates',
      columns: const ['due_date'],
      where: 'repair_id=?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final parsed =
          DateTime.tryParse(existing.first['due_date']?.toString() ?? '');
      if (parsed != null) return parsed;
    }

    final rows = await db.rawQuery('''
      SELECT
        r.receivedDate AS received_date,
        MIN(e.date) AS first_financial_date
      FROM repairs r
      LEFT JOIN gl_lines l ON l.repair_id=r.id
      LEFT JOIN gl_entries e ON e.id=l.entry_id
      WHERE r.id=?
      GROUP BY r.id, r.receivedDate
    ''', [repairId]);

    if (rows.isEmpty) throw StateError('Repair $repairId not found');
    final base = DateTime.tryParse(
            rows.first['first_financial_date']?.toString() ?? '') ??
        DateTime.tryParse(rows.first['received_date']?.toString() ?? '') ??
        DateTime.now();
    final due = _dateOnly(base).add(const Duration(days: 30));

    await db.insert(
      'collection_due_dates',
      {
        'repair_id': repairId,
        'due_date': due.toIso8601String(),
        'source': 'default_30d',
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return due;
  }

  static Future<void> setRepairDueDate(
    String repairId,
    DateTime dueDate, {
    String? notes,
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await ensureSchema(executor: db);
    await db.insert(
      'collection_due_dates',
      {
        'repair_id': repairId,
        'due_date': _dateOnly(dueDate).toIso8601String(),
        'source': 'manual',
        'notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<CollectionDueItem>> loadOpenDues({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    await ensureSchema(executor: db);

    final raw = await db.rawQuery('''
      WITH repair_ar AS (
        SELECT
          l.repair_id AS repair_id,
          COALESCE(SUM(l.debit-l.credit),0) AS balance
        FROM gl_lines l
        LEFT JOIN accounts a ON a.id=l.account_id
        WHERE l.repair_id IS NOT NULL
          AND (
            a.code LIKE '1200%'
            OR UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
          )
        GROUP BY l.repair_id
      )
      SELECT
        r.id AS repair_id,
        r.client_id AS client_id,
        COALESCE(c.name, r.beneficiaryName, '') AS client_name,
        COALESCE(r.vehicleType,'') AS vehicle_type,
        COALESCE(r.vehicleModel,'') AS vehicle_model,
        COALESCE(r.vehicleNumber,'') AS vehicle_number,
        ar.balance AS balance
      FROM repair_ar ar
      JOIN repairs r ON r.id=ar.repair_id
      LEFT JOIN clients c ON c.id=r.client_id
      WHERE ar.balance > 0.005
      ORDER BY ar.balance DESC
    ''');

    final out = <CollectionDueItem>[];
    for (final row in raw) {
      final repairId = (row['repair_id'] ?? '').toString();
      if (repairId.isEmpty) continue;
      final due = await ensureRepairDueDate(repairId, executor: db);
      final label = [
        (row['vehicle_type'] ?? '').toString().trim(),
        (row['vehicle_model'] ?? '').toString().trim(),
        (row['vehicle_number'] ?? '').toString().trim(),
      ].where((e) => e.isNotEmpty).join(' – ');
      out.add(
        CollectionDueItem(
          repairId: repairId,
          clientId: _i(row['client_id']),
          clientName: (row['client_name'] ?? '').toString(),
          vehicleLabel: label.isEmpty ? repairId : label,
          amount: _d(row['balance']),
          dueDate: due,
        ),
      );
    }
    out.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return out;
  }

  static Future<CollectionSnapshot> loadSnapshot({
    DatabaseExecutor? executor,
    int dueSoonDays = 7,
  }) async {
    final db = await _db(executor);
    final items = await loadOpenDues(executor: db);
    final today = _dateOnly(DateTime.now());
    final soon = today.add(Duration(days: dueSoonDays));

    final arRows = await db.rawQuery('''
      WITH balances AS (
        SELECT
          COALESCE(
            CASE
              WHEN UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
              THEN CAST(l.party_id AS INTEGER)
            END,
            c.id
          ) AS client_id,
          (l.debit-l.credit) AS delta
        FROM gl_lines l
        LEFT JOIN accounts a ON a.id=l.account_id
        LEFT JOIN clients c ON c.account_id=l.account_id
        WHERE a.code LIKE '1200%'
           OR c.id IS NOT NULL
           OR UPPER(COALESCE(l.party_type,'')) IN ('CLIENT','CUSTOMER')
      )
      SELECT COALESCE(SUM(CASE WHEN balance > 0 THEN balance ELSE 0 END),0) AS total_ar,
             COALESCE(SUM(CASE WHEN balance < 0 THEN -balance ELSE 0 END),0) AS credit
      FROM (
        SELECT client_id, SUM(delta) AS balance
        FROM balances
        WHERE client_id IS NOT NULL
        GROUP BY client_id
      )
    ''');
    final totalAr =
        arRows.isEmpty ? 0.0 : math.max(_d(arRows.first['total_ar']), 0.0);
    final customerCredit = arRows.isEmpty ? 0.0 : _d(arRows.first['credit']);

    var overdueAmount = 0.0;
    var dueSoonAmount = 0.0;
    for (final item in items) {
      final due = _dateOnly(item.dueDate);
      if (due.isBefore(today)) {
        overdueAmount += item.amount;
      } else if (!due.isAfter(soon)) {
        dueSoonAmount += item.amount;
      }
    }

    final chequeStats = await db.rawQuery('''
      SELECT
        SUM(CASE
          WHEN LOWER(COALESCE(status,'pending'))='pending'
           AND DATE(due_date) >= DATE(?)
           AND DATE(due_date) <= DATE(?, '+' || ? || ' day')
          THEN 1 ELSE 0 END) AS due_count,
        SUM(CASE WHEN LOWER(COALESCE(status,''))='returned' THEN 1 ELSE 0 END) AS returned_count
      FROM cheques
    ''', [today.toIso8601String(), today.toIso8601String(), dueSoonDays]);

    return CollectionSnapshot(
      totalAr: totalAr,
      overdueAmount: overdueAmount,
      dueSoonAmount: dueSoonAmount,
      customerCredit: customerCredit,
      dueCheques: chequeStats.isEmpty ? 0 : _i(chequeStats.first['due_count']),
      returnedCheques:
          chequeStats.isEmpty ? 0 : _i(chequeStats.first['returned_count']),
      items: items,
    );
  }

  static Future<List<CollectionAlertRecord>> loadAlerts({
    DatabaseExecutor? executor,
  }) async {
    final db = await _db(executor);
    final today = _dateOnly(DateTime.now());
    final alerts = <CollectionAlertRecord>[];

    for (final item in await loadOpenDues(executor: db)) {
      final days = item.daysUntilDue;
      if (days < 0) {
        alerts.add(CollectionAlertRecord(
          id: 'ar:${item.repairId}',
          message:
              'ذمة ${item.clientName} على ${item.vehicleLabel} متأخرة منذ ${-days} يوم',
          timestamp: item.dueDate,
          severity: 'critical',
        ));
      } else if (days <= 3) {
        alerts.add(CollectionAlertRecord(
          id: 'ar:${item.repairId}',
          message: 'ذمة ${item.clientName} تستحق خلال $days يوم',
          timestamp: item.dueDate,
          severity: 'warning',
        ));
      }
    }

    final chequeRows = await db.rawQuery('''
      SELECT id, cheque_no, number, due_date, status
      FROM cheques
      WHERE LOWER(COALESCE(status,'pending'))='pending'
        AND DATE(due_date) <= DATE(?, '+7 day')
      ORDER BY DATE(due_date) ASC
    ''', [today.toIso8601String()]);
    for (final row in chequeRows) {
      final due = DateTime.tryParse(row['due_date']?.toString() ?? '') ?? today;
      final no =
          (row['cheque_no'] ?? row['number'] ?? row['id'] ?? '').toString();
      final days = _dateOnly(due).difference(today).inDays;
      alerts.add(CollectionAlertRecord(
        id: 'cheque:${row['id']}',
        message: days < 0
            ? 'شيك $no متأخر منذ ${-days} يوم'
            : 'شيك $no يستحق خلال $days يوم',
        timestamp: due,
        severity: days < 0 ? 'critical' : 'warning',
      ));
    }

    final returned = await db.rawQuery('''
      SELECT id, cheque_no, number, due_date
      FROM cheques
      WHERE LOWER(COALESCE(status,''))='returned'
      ORDER BY COALESCE(updated_at, due_date) DESC
      LIMIT 10
    ''');
    for (final row in returned) {
      final no =
          (row['cheque_no'] ?? row['number'] ?? row['id'] ?? '').toString();
      alerts.add(CollectionAlertRecord(
        id: 'returned:${row['id']}',
        message: 'شيك راجع يحتاج متابعة: $no',
        timestamp:
            DateTime.tryParse(row['due_date']?.toString() ?? '') ?? today,
        severity: 'critical',
      ));
    }

    alerts.sort((a, b) {
      final sev = {'critical': 0, 'warning': 1, 'info': 2};
      final bySeverity = (sev[a.severity] ?? 9).compareTo(sev[b.severity] ?? 9);
      if (bySeverity != 0) return bySeverity;
      return a.timestamp.compareTo(b.timestamp);
    });
    return alerts;
  }
}
