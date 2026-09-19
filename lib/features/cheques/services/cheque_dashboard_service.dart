import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_maturity_service.dart';

class ChequeMetric {
  const ChequeMetric(this.count, this.amount);
  final int count;
  final double amount;
}

class ChequeDashboardData {
  const ChequeDashboardData({
    required this.total,
    required this.receivedHeld,
    required this.receivedDeposited,
    required this.receivedCollected,
    required this.receivedReturned,
    required this.receivedDueSoon,
    required this.issuedOpen,
    required this.issuedDelivered,
    required this.issuedDueSoon,
    required this.issuedCleared,
    required this.issuedCancelled,
  });

  final ChequeMetric total;
  final ChequeMetric receivedHeld;
  final ChequeMetric receivedDeposited;
  final ChequeMetric receivedCollected;
  final ChequeMetric receivedReturned;
  final ChequeMetric receivedDueSoon;
  final ChequeMetric issuedOpen;
  final ChequeMetric issuedDelivered;
  final ChequeMetric issuedDueSoon;
  final ChequeMetric issuedCleared;
  final ChequeMetric issuedCancelled;
}

class ChequeDashboardService {
  ChequeDashboardService._();

  static Future<ChequeDashboardData> load({
    DatabaseExecutor? executor,
    DateTime? from,
    DateTime? to,
    String? bank,
    String? currency,
    String? party,
    ChequeStatus? status,
    ChequeDirection? direction,
  }) async {
    final db = executor ?? await DBService.database;
    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('DATE(issue_date) >= DATE(?)');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('DATE(issue_date) <= DATE(?)');
      args.add(to.toIso8601String());
    }
    if (bank?.trim().isNotEmpty == true) {
      where.add('bank_name LIKE ?');
      args.add('%${bank!.trim()}%');
    }
    if (currency?.trim().isNotEmpty == true) {
      where.add('UPPER(currency)=?');
      args.add(currency!.trim().toUpperCase());
    }

    if (status != null) {
      where.add('status=?');
      args.add(status.name);
    }
    if (direction != null) {
      where.add('direction=?');
      args.add(
        direction == ChequeDirection.received ? 'RECEIVED' : 'ISSUED',
      );
    }

    final rows = await db.query(
      'cheques',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'due_date ASC, id ASC',
    );
    var all = rows.map(Cheque.fromMap).toList();
    if (party?.trim().isNotEmpty == true) {
      final q = party!.trim().toLowerCase();
      final clientRows = await db.rawQuery(
        'SELECT id FROM clients WHERE LOWER(COALESCE(name,\'\')) LIKE ?',
        ['%$q%'],
      );
      final supplierRows = await db.rawQuery(
        'SELECT id FROM suppliers WHERE LOWER(COALESCE(name,\'\')) LIKE ?',
        ['%$q%'],
      );
      final clientIds = clientRows.map((r) => (r['id'] as num).toInt()).toSet();
      final supplierIds = supplierRows.map((r) => r['id'].toString()).toSet();
      all = all.where((c) {
        return c.drawerName.toLowerCase().contains(q) ||
            (c.recipientName ?? '').toLowerCase().contains(q) ||
            (c.clientId != null && clientIds.contains(c.clientId)) ||
            (c.supplierPid != null && supplierIds.contains(c.supplierPid));
      }).toList();
    }
    final today = DateTime.now();

    ChequeMetric metric(Iterable<Cheque> items) {
      var count = 0;
      var amount = 0.0;
      for (final item in items) {
        count++;
        amount += item.amount;
      }
      return ChequeMetric(count, amount);
    }

    bool dueSoon(Cheque c) {
      final cls = ChequeMaturityService.classify(c, asOf: today);
      return cls == ChequeMaturityClass.dueToday ||
          cls == ChequeMaturityClass.dueSoon ||
          cls == ChequeMaturityClass.overdue;
    }

    final received = all.where(
      (c) => c.direction == ChequeDirection.received,
    );
    final issued = all.where(
      (c) => c.direction == ChequeDirection.issued,
    );

    return ChequeDashboardData(
      total: metric(all),
      receivedHeld: metric(received.where(
        (c) =>
            const {ChequeStatus.received, ChequeStatus.held}.contains(c.status),
      )),
      receivedDeposited: metric(
        received.where((c) => c.status == ChequeStatus.deposited),
      ),
      receivedCollected: metric(
        received.where((c) => c.status == ChequeStatus.collected),
      ),
      receivedReturned: metric(
        received.where((c) => c.status == ChequeStatus.returned),
      ),
      receivedDueSoon: metric(received.where(
        (c) =>
            dueSoon(c) &&
            !const {
              ChequeStatus.collected,
              ChequeStatus.returned,
              ChequeStatus.cancelled,
              ChequeStatus.endorsed,
            }.contains(c.status),
      )),
      issuedOpen: metric(issued.where(
        (c) => c.status == ChequeStatus.issued,
      )),
      issuedDelivered: metric(issued.where(
        (c) => const {ChequeStatus.delivered, ChequeStatus.presented}
            .contains(c.status),
      )),
      issuedDueSoon: metric(issued.where(
        (c) =>
            dueSoon(c) &&
            !const {
              ChequeStatus.cleared,
              ChequeStatus.returned,
              ChequeStatus.cancelled,
            }.contains(c.status),
      )),
      issuedCleared: metric(
        issued.where((c) => c.status == ChequeStatus.cleared),
      ),
      issuedCancelled: metric(
        issued.where((c) => c.status == ChequeStatus.cancelled),
      ),
    );
  }
}
