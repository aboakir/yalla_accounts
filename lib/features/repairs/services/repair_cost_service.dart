import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';

class RepairCostType {
  RepairCostType._();

  static const parts = 'PARTS';
  static const rawMaterial = 'RAW_MATERIAL';
  static const paint = 'PAINT';
  static const externalService = 'EXTERNAL_SERVICE';
  static const labor = 'LABOR';

  static const all = <String>{
    parts,
    rawMaterial,
    paint,
    externalService,
    labor,
  };

  static String label(String value) {
    switch (value) {
      case parts:
        return 'قطع غيار';
      case rawMaterial:
        return 'مواد خام';
      case paint:
        return 'دهان';
      case externalService:
        return 'خدمات خارجية';
      case labor:
        return 'عمالة';
      default:
        return value;
    }
  }

  static String fromPurchaseType(String? value) {
    final v = (value ?? '').trim().toUpperCase();
    if (v.contains('PART')) return parts;
    if (v.contains('RAW') || v.contains('MATERIAL')) return rawMaterial;
    if (v.contains('PAINT')) return paint;
    return externalService;
  }
}

class RepairCostEntry {
  const RepairCostEntry({
    required this.id,
    required this.repairId,
    required this.costType,
    required this.itemName,
    required this.quantityUsed,
    required this.wasteQuantity,
    required this.unitCost,
    required this.totalCost,
    required this.sourceType,
    required this.status,
    required this.createdAt,
    this.sourceId,
    this.sourceLineId,
    this.employeeId,
    this.workHours,
    this.note,
    this.reversalReason,
  });

  final String id;
  final String repairId;
  final String costType;
  final String itemName;
  final double quantityUsed;
  final double wasteQuantity;
  final double unitCost;
  final double totalCost;
  final String sourceType;
  final String status;
  final DateTime createdAt;
  final String? sourceId;
  final String? sourceLineId;
  final String? employeeId;
  final double? workHours;
  final String? note;
  final String? reversalReason;

  bool get isActive => status == 'ACTIVE';
  double get wasteCost => costType == RepairCostType.labor
      ? 0.0
      : RepairCostService.round2(wasteQuantity * unitCost);

  factory RepairCostEntry.fromMap(Map<String, Object?> row) {
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final rawDate = row['created_at']?.toString();
    return RepairCostEntry(
      id: row['id']?.toString() ?? '',
      repairId: row['repair_id']?.toString() ?? '',
      costType: row['cost_type']?.toString() ?? RepairCostType.externalService,
      itemName: row['item_name']?.toString() ?? '',
      quantityUsed: d(row['quantity_used']),
      wasteQuantity: d(row['waste_quantity']),
      unitCost: d(row['unit_cost']),
      totalCost: d(row['total_cost']),
      sourceType: row['source_type']?.toString() ?? 'MANUAL',
      status: row['status']?.toString() ?? 'ACTIVE',
      createdAt: DateTime.tryParse(rawDate ?? '') ?? DateTime.now(),
      sourceId: row['source_id']?.toString(),
      sourceLineId: row['source_line_id']?.toString(),
      employeeId: row['employee_id']?.toString(),
      workHours: row['work_hours'] == null ? null : d(row['work_hours']),
      note: row['note']?.toString(),
      reversalReason: row['reversal_reason']?.toString(),
    );
  }
}

class PurchaseCostCandidate {
  const PurchaseCostCandidate({
    required this.invoiceId,
    required this.lineId,
    required this.itemName,
    required this.purchaseType,
    required this.date,
    required this.purchasedQty,
    required this.allocatedQty,
    required this.remainingQty,
    required this.unitCost,
  });

  final String invoiceId;
  final String lineId;
  final String itemName;
  final String purchaseType;
  final DateTime date;
  final double purchasedQty;
  final double allocatedQty;
  final double remainingQty;
  final double unitCost;

  String get suggestedCostType => RepairCostType.fromPurchaseType(purchaseType);
}

class RepairProfitabilitySnapshot {
  const RepairProfitabilitySnapshot({
    required this.repairId,
    required this.revenue,
    required this.directCost,
    required this.wasteCost,
    required this.profit,
    required this.marginPercent,
    required this.byType,
    required this.entries,
  });

  final String repairId;
  final double revenue;
  final double directCost;
  final double wasteCost;
  final double profit;
  final double? marginPercent;
  final Map<String, double> byType;
  final List<RepairCostEntry> entries;

  bool get hasCostData => directCost > 0.005;
  double amountFor(String type) => byType[type] ?? 0.0;
}

/// P14 management-costing layer for one repair.
///
/// Accounting boundary:
/// - Revenue is always P10 recognized revenue from GL account 4000.
/// - Purchase allocations and manual cost entries are management dimensions.
/// - This service NEVER posts, edits or deletes GL/invoices/payments.
/// - A purchase line already posted to GL is therefore not expensed twice.
class RepairCostService {
  RepairCostService._();

  static const _table = 'repair_cost_entries';
  static const _uuid = Uuid();

  static double d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double round2(double value) => double.parse(value.toStringAsFixed(2));

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table(
        id TEXT PRIMARY KEY,
        repair_id TEXT NOT NULL,
        cost_type TEXT NOT NULL,
        item_name TEXT NOT NULL,
        quantity_used REAL NOT NULL DEFAULT 0,
        waste_quantity REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0,
        source_type TEXT NOT NULL DEFAULT 'MANUAL',
        source_id TEXT,
        source_line_id TEXT,
        employee_id TEXT,
        work_hours REAL,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        reversal_of TEXT,
        reversal_reason TEXT,
        created_at TEXT NOT NULL,
        created_by TEXT,
        reversed_at TEXT,
        reversed_by TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_cost_entries_repair '
      'ON $_table(repair_id, status, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_cost_entries_source_line '
      'ON $_table(source_line_id, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_cost_entries_employee '
      'ON $_table(employee_id, status)',
    );
  }

  static Future<void> _assertRepairExists(
    DatabaseExecutor db,
    String repairId,
  ) async {
    final rows = await db.query(
      'repairs',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [repairId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('ملف الإصلاح غير موجود');
  }

  static Future<List<RepairCostEntry>> loadEntries(
    String repairId, {
    DatabaseExecutor? executor,
    bool includeReversed = false,
  }) async {
    final db = executor ?? await DBService.database;
    await ensureSchema(db);
    final rows = await db.query(
      _table,
      where: includeReversed ? 'repair_id = ?' : 'repair_id = ? AND status = ?',
      whereArgs: includeReversed ? [repairId] : [repairId, 'ACTIVE'],
      orderBy: 'datetime(created_at) DESC, rowid DESC',
    );
    return rows.map(RepairCostEntry.fromMap).toList();
  }

  static Future<RepairProfitabilitySnapshot> loadSnapshot(
    String repairId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    await ensureSchema(db);
    final truth = await RepairFinancialTruthService.load(
      repairId,
      executor: db,
    );
    final entries = await loadEntries(repairId, executor: db);
    final byType = <String, double>{
      for (final type in RepairCostType.all) type: 0.0,
    };
    var directCost = 0.0;
    var wasteCost = 0.0;
    for (final entry in entries) {
      directCost += entry.totalCost;
      wasteCost += entry.wasteCost;
      byType[entry.costType] = (byType[entry.costType] ?? 0) + entry.totalCost;
    }
    directCost = round2(directCost);
    wasteCost = round2(wasteCost);
    final revenue = round2(truth.recognizedRevenue);
    final profit = round2(revenue - directCost);
    final margin =
        revenue.abs() <= 0.005 ? null : round2((profit / revenue) * 100.0);
    return RepairProfitabilitySnapshot(
      repairId: repairId,
      revenue: revenue,
      directCost: directCost,
      wasteCost: wasteCost,
      profit: profit,
      marginPercent: margin,
      byType: byType.map((k, v) => MapEntry(k, round2(v))),
      entries: entries,
    );
  }

  static Future<String> addManualCost({
    required String repairId,
    required String costType,
    required String itemName,
    required double quantityUsed,
    required double unitCost,
    double wasteQuantity = 0,
    String? employeeId,
    double? workHours,
    String? note,
    String? actorId,
    DatabaseExecutor? executor,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairCostManage);
    if (!RepairCostType.all.contains(costType)) {
      throw ArgumentError('نوع التكلفة غير صالح');
    }
    final name = itemName.trim();
    if (name.isEmpty) throw ArgumentError('اسم بند التكلفة مطلوب');
    if (unitCost < 0) {
      throw ArgumentError('تكلفة الوحدة لا يمكن أن تكون سالبة');
    }

    final isLabor = costType == RepairCostType.labor;
    final used = isLabor ? (workHours ?? quantityUsed) : quantityUsed;
    final waste = isLabor ? 0.0 : wasteQuantity;
    if (used < 0 || waste < 0 || used + waste <= 0) {
      throw ArgumentError('الكمية/الساعات يجب أن تكون أكبر من صفر');
    }
    final total = round2((used + waste) * unitCost);
    if (total <= 0) {
      throw ArgumentError('إجمالي التكلفة يجب أن يكون أكبر من صفر');
    }
    final actor = actorId ?? await CurrentUserContext.userId() ?? 'LOCAL_USER';
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    Future<void> write(DatabaseExecutor db) async {
      await ensureSchema(db);
      await _assertRepairExists(db, repairId);
      await db.insert(_table, {
        'id': id,
        'repair_id': repairId,
        'cost_type': costType,
        'item_name': name,
        'quantity_used': used,
        'waste_quantity': waste,
        'unit_cost': unitCost,
        'total_cost': total,
        'source_type': isLabor ? 'LABOR_MANUAL' : 'MANUAL',
        'employee_id': employeeId,
        'work_hours': isLabor ? used : null,
        'note': _nullIfBlank(note),
        'status': 'ACTIVE',
        'created_at': now,
        'created_by': actor,
      });
    }

    if (executor != null) {
      await write(executor);
    } else {
      await DBService.inTx(write);
    }
    await AuditTrailService.log(
      executor: executor,
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'REPAIR_COST_ADDED',
      entityType: 'repair_cost',
      entityId: id,
      after: {
        'repair_id': repairId,
        'cost_type': costType,
        'item_name': name,
        'quantity_used': used,
        'waste_quantity': waste,
        'unit_cost': unitCost,
        'total_cost': total,
        'employee_id': employeeId,
      },
      reason: note,
    );
    return id;
  }

  static Future<List<PurchaseCostCandidate>> listAvailablePurchaseLines({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    await ensureSchema(db);
    final rows = await db.rawQuery('''
      SELECT
        p.id AS invoice_id,
        p.date,
        COALESCE(p.purchase_type,'OTHER') AS purchase_type,
        pl.id AS line_id,
        COALESCE(NULLIF(TRIM(pl.item_name),''), NULLIF(TRIM(pl.item),''), 'بند مشتريات') AS item_name,
        COALESCE(pl.qty,1) AS purchased_qty,
        COALESCE(NULLIF(pl.price,0), pl.unit_price,
          CASE WHEN COALESCE(pl.qty,0) > 0 THEN pl.total/pl.qty ELSE pl.total END,
          0) AS unit_cost,
        COALESCE(a.allocated_qty,0) AS allocated_qty
      FROM purchase_invoice_lines pl
      JOIN purchase_invoices p ON p.id = pl.invoice_id
      LEFT JOIN (
        SELECT source_line_id,
               SUM(quantity_used + waste_quantity) AS allocated_qty
        FROM $_table
        WHERE status='ACTIVE' AND source_type='PURCHASE_LINE'
        GROUP BY source_line_id
      ) a ON a.source_line_id = pl.id
      ORDER BY datetime(p.date) DESC, pl.rowid DESC
    ''');

    final out = <PurchaseCostCandidate>[];
    for (final row in rows) {
      final purchased = d(row['purchased_qty']);
      final allocated = d(row['allocated_qty']);
      final remaining = math.max(purchased - allocated, 0.0).toDouble();
      if (remaining <= 0.0001) continue;
      out.add(PurchaseCostCandidate(
        invoiceId: row['invoice_id']?.toString() ?? '',
        lineId: row['line_id']?.toString() ?? '',
        itemName: row['item_name']?.toString() ?? 'بند مشتريات',
        purchaseType: row['purchase_type']?.toString() ?? 'OTHER',
        date:
            DateTime.tryParse(row['date']?.toString() ?? '') ?? DateTime.now(),
        purchasedQty: round2(purchased),
        allocatedQty: round2(allocated),
        remainingQty: round2(remaining),
        unitCost: round2(d(row['unit_cost'])),
      ));
    }
    return out;
  }

  static Future<String> allocatePurchaseLine({
    required String repairId,
    required String purchaseLineId,
    required String costType,
    required double quantityUsed,
    double wasteQuantity = 0,
    String? note,
    String? actorId,
    DatabaseExecutor? executor,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairCostManage);
    if (!RepairCostType.all.contains(costType) ||
        costType == RepairCostType.labor) {
      throw ArgumentError('نوع تخصيص المشتريات غير صالح');
    }
    if (quantityUsed < 0 ||
        wasteQuantity < 0 ||
        quantityUsed + wasteQuantity <= 0) {
      throw ArgumentError('الكمية المستخدمة/الهدر يجب أن تكون أكبر من صفر');
    }
    final actor = actorId ?? await CurrentUserContext.userId() ?? 'LOCAL_USER';
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    Future<void> write(DatabaseExecutor db) async {
      await ensureSchema(db);
      await _assertRepairExists(db, repairId);
      final rows = await db.rawQuery('''
        SELECT
          p.id AS invoice_id,
          COALESCE(NULLIF(TRIM(pl.item_name),''), NULLIF(TRIM(pl.item),''), 'بند مشتريات') AS item_name,
          COALESCE(pl.qty,1) AS purchased_qty,
          COALESCE(NULLIF(pl.price,0), pl.unit_price,
            CASE WHEN COALESCE(pl.qty,0) > 0 THEN pl.total/pl.qty ELSE pl.total END,
            0) AS unit_cost
        FROM purchase_invoice_lines pl
        JOIN purchase_invoices p ON p.id = pl.invoice_id
        WHERE pl.id = ?
        LIMIT 1
      ''', [purchaseLineId]);
      if (rows.isEmpty) throw StateError('بند المشتريات غير موجود');

      final allocatedRows = await db.rawQuery('''
        SELECT COALESCE(SUM(quantity_used + waste_quantity),0) AS qty
        FROM $_table
        WHERE source_line_id=? AND status='ACTIVE' AND source_type='PURCHASE_LINE'
      ''', [purchaseLineId]);
      final purchased = d(rows.first['purchased_qty']);
      final already =
          allocatedRows.isEmpty ? 0.0 : d(allocatedRows.first['qty']);
      final requested = quantityUsed + wasteQuantity;
      final available = math.max(purchased - already, 0.0).toDouble();
      if (requested > available + 0.0001) {
        throw StateError(
          'الكمية المطلوبة ${round2(requested)} تتجاوز المتاح ${round2(available)}',
        );
      }
      final unitCost = round2(d(rows.first['unit_cost']));
      final total = round2(requested * unitCost);
      if (unitCost < 0 || total < 0) {
        throw StateError('تكلفة بند المشتريات غير صالحة');
      }

      await db.insert(_table, {
        'id': id,
        'repair_id': repairId,
        'cost_type': costType,
        'item_name': rows.first['item_name']?.toString() ?? 'بند مشتريات',
        'quantity_used': quantityUsed,
        'waste_quantity': wasteQuantity,
        'unit_cost': unitCost,
        'total_cost': total,
        'source_type': 'PURCHASE_LINE',
        'source_id': rows.first['invoice_id']?.toString(),
        'source_line_id': purchaseLineId,
        'note': _nullIfBlank(note),
        'status': 'ACTIVE',
        'created_at': now,
        'created_by': actor,
      });
    }

    if (executor != null) {
      await write(executor);
    } else {
      await DBService.inTx(write);
    }
    await AuditTrailService.log(
      executor: executor,
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'PURCHASE_COST_ALLOCATED',
      entityType: 'repair_cost',
      entityId: id,
      after: {
        'repair_id': repairId,
        'purchase_line_id': purchaseLineId,
        'cost_type': costType,
        'quantity_used': quantityUsed,
        'waste_quantity': wasteQuantity,
      },
      reason: note,
    );
    return id;
  }

  static Future<void> reverseEntry({
    required String entryId,
    required String reason,
    String? actorId,
    DatabaseExecutor? executor,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.repairCostManage);
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('سبب عكس التكلفة مطلوب');
    }
    final actor = actorId ??
        p16Actor?.id ??
        await CurrentUserContext.userId() ??
        'LOCAL_USER';
    String? repairIdForAudit;
    String? costTypeForAudit;
    double? totalForAudit;

    Future<void> write(DatabaseExecutor db) async {
      await ensureSchema(db);
      final rows = await db.query(
        _table,
        columns: const ['id', 'status', 'repair_id', 'cost_type', 'total_cost'],
        where: 'id=?',
        whereArgs: [entryId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('بند التكلفة غير موجود');
      if (rows.first['status']?.toString() != 'ACTIVE') {
        throw StateError('بند التكلفة معكوس مسبقًا');
      }
      repairIdForAudit = rows.first['repair_id']?.toString();
      costTypeForAudit = rows.first['cost_type']?.toString();
      totalForAudit = d(rows.first['total_cost']);
      await db.update(
        _table,
        {
          'status': 'REVERSED',
          'reversal_reason': cleanReason,
          'reversed_at': DateTime.now().toIso8601String(),
          'reversed_by': actor,
        },
        where: 'id=? AND status=?',
        whereArgs: [entryId, 'ACTIVE'],
      );
    }

    if (executor != null) {
      await write(executor);
    } else {
      await DBService.inTx(write);
    }
    await AuditTrailService.log(
      executor: executor,
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'REPAIR_COST_REVERSED',
      entityType: 'repair_cost',
      entityId: entryId,
      before: {
        'status': 'ACTIVE',
        'repair_id': repairIdForAudit,
        'cost_type': costTypeForAudit,
        'total_cost': totalForAudit,
      },
      after: {'status': 'REVERSED'},
      reason: cleanReason,
    );
  }

  static String? _nullIfBlank(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
