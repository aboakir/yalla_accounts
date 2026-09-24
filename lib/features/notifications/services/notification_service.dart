// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/experience/app_experience_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/inventory_tables.dart';
import 'package:yalla_accounts/features/notifications/models/app_notification.dart';

class NotificationService {
  NotificationService._();

  static const _readKey = 'yallah.notifications.read.v1';
  static const _handledKey = 'yallah.notifications.handled.v1';

  static Future<List<AppNotification>> load() async {
    final profile = await AppExperienceService.load();
    final db = await DBService.database;
    final now = DateTime.now();
    final notifications = <AppNotification>[];

    if (profile.moduleEnabled(AppModule.repairs)) {
      await _safe(() async => notifications.addAll(await _repairs(db, now)));
    }
    if (profile.moduleEnabled(AppModule.finance)) {
      await _safe(
        () async => notifications.addAll(await _receivables(db, now)),
      );
      await _safe(() async => notifications.addAll(await _payables(db, now)));
    }
    if (profile.moduleEnabled(AppModule.cheques)) {
      await _safe(() async => notifications.addAll(await _cheques(db, now)));
    }
    if (profile.moduleEnabled(AppModule.employees)) {
      await _safe(() async => notifications.addAll(await _payroll(db, now)));
    }
    if (profile.moduleEnabled(AppModule.inventory)) {
      await _safe(() async => notifications.addAll(await _inventory(db, now)));
    }

    final prefs = await SharedPreferences.getInstance();
    final read = (prefs.getStringList(_readKey) ?? const <String>[]).toSet();
    final handled =
        (prefs.getStringList(_handledKey) ?? const <String>[]).toSet();

    final byKey = <String, AppNotification>{};
    for (final item in notifications) {
      final isHandled = handled.contains(item.key);
      final isRead = read.contains(item.key) || isHandled;
      byKey[item.key] = item.copyWith(
        isRead: isRead,
        status: isHandled ? AppNotificationStatus.handled : item.status,
      );
    }
    final result = byKey.values.toList()
      ..sort((a, b) {
        if (a.isHandled != b.isHandled) return a.isHandled ? 1 : -1;
        final rank = _rank(b).compareTo(_rank(a));
        return rank != 0 ? rank : b.timestamp.compareTo(a.timestamp);
      });
    return result;
  }

  static int _rank(AppNotification item) => switch (item.status) {
        AppNotificationStatus.overdue => 4,
        AppNotificationStatus.urgent => 3,
        AppNotificationStatus.newItem => 2,
        AppNotificationStatus.unread => 1,
        AppNotificationStatus.handled => 0,
      };

  static Future<void> markRead(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final values = (prefs.getStringList(_readKey) ?? <String>[]).toSet()
      ..add(key);
    await prefs.setStringList(_readKey, values.toList());
  }

  static Future<void> markHandled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final handled = (prefs.getStringList(_handledKey) ?? <String>[]).toSet()
      ..add(key);
    final read = (prefs.getStringList(_readKey) ?? <String>[]).toSet()
      ..add(key);
    await prefs.setStringList(_handledKey, handled.toList());
    await prefs.setStringList(_readKey, read.toList());
  }

  static Future<void> markAllRead(Iterable<AppNotification> items) async {
    final prefs = await SharedPreferences.getInstance();
    final read = (prefs.getStringList(_readKey) ?? <String>[]).toSet()
      ..addAll(items.map((e) => e.key));
    await prefs.setStringList(_readKey, read.toList());
  }

  static Future<void> resetPresentationStateForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_readKey);
    await prefs.remove(_handledKey);
  }

  static Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // One optional source must never make the entire center unavailable.
      // Database/schema integrity is validated separately by release gates.
    }
  }

  static DateTime _date(Object? raw, DateTime fallback) =>
      DateTime.tryParse(raw?.toString() ?? '') ?? fallback;

  static AppNotificationStatus _status({
    required DateTime timestamp,
    required DateTime now,
    bool urgent = false,
    bool overdue = false,
  }) {
    if (overdue) return AppNotificationStatus.overdue;
    if (urgent) return AppNotificationStatus.urgent;
    if (now.difference(timestamp).inHours <= 24) {
      return AppNotificationStatus.newItem;
    }
    return AppNotificationStatus.unread;
  }

  static Future<List<AppNotification>> _repairs(
    DatabaseExecutor db,
    DateTime now,
  ) async {
    final rows = await db.rawQuery('''
      SELECT id, vehicleNumber, receivedDate, created_at, status, vehicleStatus
      FROM repairs
      WHERE COALESCE(isArchived, 0) = 0
      ORDER BY COALESCE(receivedDate, created_at) ASC
      LIMIT 80
    ''');
    final out = <AppNotification>[];
    for (final row in rows) {
      final state = ('${row['status'] ?? ''} ${row['vehicleStatus'] ?? ''}')
          .toLowerCase();
      if (state.contains('closed') ||
          state.contains('cancel') ||
          state.contains('مسلم')) {
        continue;
      }
      final at = _date(row['receivedDate'] ?? row['created_at'], now);
      final overdue = now.difference(at).inDays >= 7;
      final ready = state.contains('ready') ||
          state.contains('complete') ||
          state.contains('جاهز');
      if (!overdue && !ready) continue;
      final id = row['id'].toString();
      out.add(
        AppNotification(
          key: 'repair:$id:' + (ready ? 'ready' : 'overdue'),
          sourceType: 'repairs',
          sourceId: id,
          timestamp: at,
          priority: AppNotificationPriority.urgent,
          status: _status(
            timestamp: at,
            now: now,
            urgent: ready,
            overdue: overdue,
          ),
          title: ready ? 'مركبة جاهزة للمتابعة' : 'ملف إصلاح متأخر',
          message: (row['vehicleNumber'] ?? 'ملف إصلاح').toString() +
              ' يحتاج متابعة من شاشة الإصلاحات.',
          route: AppRoutes.repairDetail,
          arguments: <String, Object?>{'repairId': id},
        ),
      );
    }
    return out;
  }

  static Future<List<AppNotification>> _receivables(
    DatabaseExecutor db,
    DateTime now,
  ) async {
    final rows = await db.rawQuery('''
      SELECT id, client_id, date, total, paid
      FROM invoices
      WHERE COALESCE(total,0) - COALESCE(paid,0) > 0.009
      ORDER BY date ASC
      LIMIT 80
    ''');
    return rows.map((row) {
      final id = row['id'].toString();
      final at = _date(row['date'], now);
      final remaining = ((row['total'] as num?)?.toDouble() ?? 0) -
          ((row['paid'] as num?)?.toDouble() ?? 0);
      final overdue = now.difference(at).inDays >= 30;
      return AppNotification(
        key: 'receivable:$id',
        sourceType: 'receivables',
        sourceId: id,
        timestamp: at,
        priority: overdue
            ? AppNotificationPriority.urgent
            : AppNotificationPriority.normal,
        status: _status(timestamp: at, now: now, overdue: overdue),
        title: 'مبلغ مطلوب تحصيله',
        message:
            'فاتورة عليها ' + remaining.toStringAsFixed(2) + ' متبقي للتحصيل.',
        route: AppRoutes.invoiceView,
        arguments: <String, Object?>{'invoiceId': id},
      );
    }).toList();
  }

  static Future<List<AppNotification>> _payables(
    DatabaseExecutor db,
    DateTime now,
  ) async {
    final rows = await db.rawQuery('''
      SELECT id, supplier_id, date,
             COALESCE(amount_total,total,0) AS total_amount,
             COALESCE(paid_total,0) AS paid_amount
      FROM purchase_invoices
      WHERE COALESCE(is_active,1) = 1
        AND COALESCE(amount_total,total,0) - COALESCE(paid_total,0) > 0.009
      ORDER BY date ASC
      LIMIT 80
    ''');
    return rows.map((row) {
      final id = row['id'].toString();
      final at = _date(row['date'], now);
      final remaining = ((row['total_amount'] as num?)?.toDouble() ?? 0) -
          ((row['paid_amount'] as num?)?.toDouble() ?? 0);
      final overdue = now.difference(at).inDays >= 30;
      return AppNotification(
        key: 'payable:$id',
        sourceType: 'payables',
        sourceId: id,
        timestamp: at,
        priority: overdue
            ? AppNotificationPriority.urgent
            : AppNotificationPriority.normal,
        status: _status(timestamp: at, now: now, overdue: overdue),
        title: 'مبلغ مستحق لمورد',
        message:
            'فاتورة شراء عليها ' + remaining.toStringAsFixed(2) + ' متبقي.',
        route: AppRoutes.purchasesList,
        arguments: <String, Object?>{'purchaseId': id},
      );
    }).toList();
  }

  static Future<List<AppNotification>> _cheques(
    DatabaseExecutor db,
    DateTime now,
  ) async {
    final rows = await db.rawQuery('''
      SELECT id, cheque_no, number, due_date, status, amount, cheque_type
      FROM cheques
      WHERE LOWER(COALESCE(status,'')) IN
        ('pending','postdated','returned','due')
      ORDER BY due_date ASC
      LIMIT 100
    ''');
    final out = <AppNotification>[];
    for (final row in rows) {
      final id = row['id'].toString();
      final state = row['status']?.toString().toLowerCase() ?? '';
      final due = _date(row['due_date'], now);
      final returned = state == 'returned';
      final overdue = !returned &&
          row['due_date'] != null &&
          !due.isAfter(DateTime(now.year, now.month, now.day));
      if (!returned && !overdue) continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      out.add(
        AppNotification(
          key: 'cheque:$id:$state',
          sourceType: 'cheques',
          sourceId: id,
          timestamp: due,
          priority: AppNotificationPriority.urgent,
          status: _status(
            timestamp: due,
            now: now,
            urgent: returned,
            overdue: overdue,
          ),
          title: returned ? 'شيك راجع' : 'شيك مستحق',
          message: 'الشيك ' +
              (row['cheque_no'] ?? row['number'] ?? id).toString() +
              ' بقيمة ' +
              amount.toStringAsFixed(2) +
              ' يحتاج إجراء.',
          route: AppRoutes.chequesEdit,
          arguments: <String, Object?>{'chequeId': id},
        ),
      );
    }
    return out;
  }

  static Future<List<AppNotification>> _payroll(
    DatabaseExecutor db,
    DateTime now,
  ) async {
    final rows = await db.rawQuery('''
      SELECT id, employee_id, period_end, net, amount_paid, status
      FROM payroll_runs
      WHERE COALESCE(net,0) - COALESCE(amount_paid,0) > 0.009
      ORDER BY period_end ASC
      LIMIT 80
    ''');
    return rows.map((row) {
      final id = row['id'].toString();
      final at = _date(row['period_end'], now);
      final remaining = ((row['net'] as num?)?.toDouble() ?? 0) -
          ((row['amount_paid'] as num?)?.toDouble() ?? 0);
      final overdue = now.difference(at).inDays >= 7;
      return AppNotification(
        key: 'payroll:$id',
        sourceType: 'payroll',
        sourceId: id,
        timestamp: at,
        priority: overdue
            ? AppNotificationPriority.urgent
            : AppNotificationPriority.normal,
        status: _status(timestamp: at, now: now, overdue: overdue),
        title: 'راتب غير مكتمل الدفع',
        message: 'متبقي ' + remaining.toStringAsFixed(2) + ' على كشف راتب.',
        route: AppRoutes.employeeList,
      );
    }).toList();
  }

  static Future<List<AppNotification>> _inventory(
    DatabaseExecutor db,
    DateTime now,
  ) async {
    final reorderExists = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='inventory_reorder_levels' LIMIT 1",
    );
    final reorderJoin = reorderExists.isEmpty
        ? 'LEFT JOIN (SELECT NULL AS item_id, 0.0 AS reorder_level WHERE 0) r ON 1=0'
        : '''LEFT JOIN (
             SELECT item_id, MAX(reorder_level) AS reorder_level
             FROM inventory_reorder_levels
             GROUP BY item_id
           ) r ON r.item_id=s.item_id''';
    final rows = await db.rawQuery('''
      SELECT s.item_id AS id, s.name, s.available, i.updated_at,
             COALESCE(r.reorder_level,0) AS reorder_level
      FROM ${InventoryTables.stockByItemView} s
      JOIN ${InventoryTables.items} i ON i.id=s.item_id
      $reorderJoin
      WHERE i.is_active=1
        AND COALESCE(s.available,0) <= COALESCE(r.reorder_level,0)
      ORDER BY s.available ASC, s.name
      LIMIT 80
    ''');
    return rows.map((row) {
      final id = row['id'].toString();
      final at = _date(row['updated_at'], now);
      final available = (row['available'] as num?)?.toDouble() ?? 0.0;
      final threshold = (row['reorder_level'] as num?)?.toDouble() ?? 0.0;
      return AppNotification(
        key: 'inventory:$id:low',
        sourceType: 'inventory',
        sourceId: id,
        timestamp: at,
        priority: AppNotificationPriority.urgent,
        status: _status(timestamp: at, now: now, urgent: true),
        title: available <= 0 ? 'مخزون نافد' : 'مخزون منخفض',
        message:
            '${row['name'] ?? 'صنف'}: المتاح ${available.toStringAsFixed(2)}'
            '${threshold > 0 ? ' / حد الطلب ${threshold.toStringAsFixed(2)}' : ''}.',
        route: AppRoutes.inventory,
        arguments: <String, Object?>{'itemId': id},
      );
    }).toList();
  }
}
