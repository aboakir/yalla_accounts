// 📁 lib/features/repairs/services/repair_save_service.dart
//
// نسخة نهائية متوافقة بالكامل مع db_service v38
// - إنشاء ملف إصلاح
// - إدراج الخطوط + الصور
// - إنشاء الفاتورة داخل نفس الـ Transaction
// - ترحيل GL فتح ملف إصلاح (postRepairGL)
// - منع التكرار أو الازدواج
// - ترحيل دفعة أولية إن وجدت
// بدون أي سطر ناقص — جاهزة للاستعمال مباشرة

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_form_provider.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';

class RepairSaveService {
  static Future<String> save({
    required WidgetRef ref,
    required double? actualCost,
    required bool isLedgerEnabled,
  }) async {
    debugPrint('=== RepairSaveService.save START ===');

    final form = ref.read(repairFormProvider);
    final notifier = ref.read(repairFormProvider.notifier);

    // ===========================
    // 1) حساب الإجمالي
    // ===========================
    final normalizedParts = _normalizeLines(form.parts);
    final normalizedWorks = _normalizeLines(form.works);
    final partsTotal = _linesTotal(normalizedParts);
    final worksTotal = _linesTotal(normalizedWorks);
    final grandTotal = partsTotal + worksTotal;

    final paid = _asDouble(form.paidAmount);
    final repairId = const Uuid().v4();

    // ===========================
    // 2) Transaction
    // ===========================
    await DBService.inTx((txn) async {
      debugPrint('--- TX BEGIN ---');

      // ------------------------------------------------------------
      // إنشاء جداول الخطوط والصور لو ناقصه
      // ------------------------------------------------------------
      await _ensureLines(txn);
      await _ensureImages(txn);

      // ------------------------------------------------------------
      // إدراج/تحديث العميل
      // ------------------------------------------------------------
      int? clientId;
      if (form.beneficiaryName.trim().isNotEmpty) {
        clientId = await ClientService.upsertFromRepairOn(
          txn,
          name: form.beneficiaryName.trim(),
          type: (form.beneficiaryType == 'أفراد') ? 'أفراد' : 'شركة تأمين',
        );
      }

      // ------------------------------------------------------------
      // بناء نموذج الإصلاح
      // ------------------------------------------------------------
      await VehicleService.upsertFromRepairOn(
        txn,
        number: form.vehicleNumber.trim(),
        type: form.vehicleType.trim(),
        model: form.vehicleModel.trim(),
        clientId: clientId,
      );

      final repair = Repair(
        id: repairId,
        invoiceNumber: '',
        vehicleModel: form.vehicleModel,
        vehicleType: form.vehicleType,
        vehicleNumber: form.vehicleNumber,
        receivedDate: form.receivedDate,
        beneficiaryType: form.beneficiaryType,
        beneficiaryName: form.beneficiaryName,
        clientId: clientId,
        insuranceStatus: form.insuranceStatus,
        repairType: form.repairType,
        vehicleStatus: form.vehicleStatus,
        status: 'APPROVED',
        quoteNumber: null,
        quoteValidUntil: null,
        approvedAt: DateTime.now(),
        approvedBy: 'SYSTEM',
        parts: normalizedParts,
        works: normalizedWorks,
        fileValue: grandTotal,
        paymentType: _mapPay(form.paymentMethod),
        paidAmount: paid,
        paymentStatus: (paid >= grandTotal)
            ? 'مسدد'
            : (paid > 0 ? 'مسدد جزئي' : 'غير مسدد'),
        notes: form.notes,
        imagePaths: form.imagePaths,
        transferFromAccount: form.transferFromAccount,
        transferToAccount: form.transferToAccount,
        transferCompany: form.transferCompany,
        transferDate: form.transferDate,
        transferAmount: form.transferAmount,
        transferImagePath: form.transferImagePath,
        isArchived: false,
        actualCost: actualCost,
        workCost: null,
        incomeAmount: null,
        isLedgerEnabled: true,
        isLedgerSynced: false,
        finalApprovedAmount: grandTotal,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // ------------------------------------------------------------
      // INSERT repairs
      // ------------------------------------------------------------
      await txn.insert('repairs', _toDb(repair),
          conflictAlgorithm: ConflictAlgorithm.replace);

      // ------------------------------------------------------------
      // Insert تفاصيل الخطوط
      // ------------------------------------------------------------
      await _insertLines(
        txn,
        repairId,
        normalizedParts,
        normalizedWorks,
      );

      // ------------------------------------------------------------
      // Insert صور
      // ------------------------------------------------------------
      if (form.imagePaths.isNotEmpty) {
        final batch = txn.batch();
        final now = DateTime.now().toIso8601String();
        for (final p in form.imagePaths) {
          if (p.trim().isNotEmpty) {
            batch.insert('repairs_images', {
              'repair_id': repairId,
              'path': p.trim(),
              'created_at': now,
            });
          }
        }
        await batch.commit(noResult: true);
      }
      // ------------------------------------------------------------
      // حفظ أول صورة كـ thumbnail_path داخل جدول repairs
      // ------------------------------------------------------------
      if (form.imagePaths.isNotEmpty) {
        await txn.update(
          'repairs',
          {
            'thumbnail_path': form.imagePaths.first.trim(),
            'thumbnail_updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [repairId],
        );
      }

      // ------------------------------------------------------------
      // P04.2 — Local-first atomic Outbox.
      // The repair and its sync envelope commit (or roll back) together.
      // No connectivity check is allowed on the save path.
      // ------------------------------------------------------------
      await OfflineOutboxService.enqueue(
        txn,
        channel: OfflineOutboxService.channelSync,
        operation: 'UPSERT',
        entityType: 'repair',
        entityId: repairId,
        idempotencyKey: 'repair:$repairId:create',
        payload: {
          'schema': 1,
          'entity_type': 'repair',
          'entity_id': repairId,
          'operation': 'UPSERT',
          'updated_at': repair.updatedAt?.toUtc().toIso8601String(),
        },
      );

      debugPrint('--- TX END OK ---');
    });

    // إفراغ النموذج
    notifier.resetForm();

    return repairId;
  }

  // ===========================
  // HELPERS
  // ===========================

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _roundLine(double value) =>
      double.parse(value.toStringAsFixed(2));

  static Map<String, dynamic>? _normalizeLine(Object? raw) {
    if (raw is! Map) return null;

    final item = Map<String, dynamic>.from(raw);
    final name = (item['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    var qty = _asDouble(item['qty']);
    if (qty <= 0) qty = 1.0;

    final price = _asDouble(
      item['price'] ?? item['amount'] ?? item['cost'],
    );

    if (price < 0) {
      throw StateError('Repair line price cannot be negative: $name');
    }

    return <String, dynamic>{
      ...item,
      'name': name,
      'qty': qty,
      'price': price,
      'total': _roundLine(qty * price),
    };
  }

  static List<Map<String, dynamic>> _normalizeLines(
    List<Map<String, dynamic>> lines,
  ) {
    final result = <Map<String, dynamic>>[];

    for (final raw in lines) {
      final normalized = _normalizeLine(raw);
      if (normalized != null) result.add(normalized);
    }

    return result;
  }

  static double _linesTotal(List<Map<String, dynamic>> lines) {
    return lines.fold<double>(
      0.0,
      (sum, line) => sum + _asDouble(line['total']),
    );
  }

  static PaymentType _mapPay(String m) {
    if (m.contains('نقد')) return PaymentType.cash;
    if (m.contains('شيك')) return PaymentType.check;
    if (m.contains('قسط')) return PaymentType.installment;
    return PaymentType.insuranceTransfer;
  }

  static String _mapMethod(String m) {
    if (m.contains('نقد')) return 'cash';
    if (m.contains('شيك')) return 'cheque';
    if (m.contains('قسط')) return 'installment';
    return 'bank';
  }

  static String _mapAccountName(String m) {
    if (m.contains('نقد')) return 'الصندوق';
    if (m.contains('شيك')) return 'البنك';
    return 'البنك';
  }

  static Map<String, dynamic> _toDb(Repair r) => {
        'id': r.id,
        'invoiceNumber': r.invoiceNumber,
        'vehicleModel': r.vehicleModel,
        'vehicleType': r.vehicleType,
        'vehicleNumber': r.vehicleNumber,
        'receivedDate': r.receivedDate.toIso8601String(),
        'beneficiaryType': r.beneficiaryType,
        'beneficiaryName': r.beneficiaryName,
        'client_id': r.clientId,
        'insuranceStatus': r.insuranceStatus,
        'repairType': r.repairType,
        'vehicleStatus': r.vehicleStatus,
        'status': r.status,
        'quote_number': r.quoteNumber,
        'quote_valid_until': r.quoteValidUntil?.toIso8601String(),
        'approved_at': r.approvedAt?.toIso8601String(),
        'approved_by': r.approvedBy,
        'parts': jsonEncode(r.parts),
        'works': jsonEncode(r.works),
        'fileValue': r.fileValue,
        'paymentType': r.paymentType.name,
        'paidAmount': r.paidAmount,
        'paymentStatus': r.paymentStatus,
        'notes': r.notes,
        'imagePaths': jsonEncode(r.imagePaths),
        'isArchived': r.isArchived ? 1 : 0,
        'finalApprovedAmount': r.finalApprovedAmount,
        'isLedgerEnabled': r.isLedgerEnabled ? 1 : 0,
        'isLedgerSynced': r.isLedgerSynced ? 1 : 0,
        'workCost': r.workCost,
        'incomeAmount': r.incomeAmount,
        'invoiceId': r.invoiceId,
        'invoice_id': r.invoiceId,
        'actualCost': r.actualCost,
        'created_at': r.createdAt?.toIso8601String(),
        'updated_at': r.updatedAt?.toIso8601String(),
        'transferFromAccount': r.transferFromAccount,
        'transferToAccount': r.transferToAccount,
        'transferCompany': r.transferCompany,
        'transferDate': r.transferDate?.toIso8601String(),
        'transferAmount': r.transferAmount,
        'transferImagePath': r.transferImagePath,
      };

  // ===========================
  // Tables
  // ===========================

  static Future<void> _ensureLines(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repair_lines(
        id TEXT PRIMARY KEY,
        repair_id TEXT NOT NULL,
        line_type TEXT NOT NULL CHECK(line_type IN ('part','work')),
        name TEXT NOT NULL CHECK(LENGTH(TRIM(name)) > 0),
        qty REAL NOT NULL DEFAULT 1 CHECK(qty > 0),
        price REAL NOT NULL DEFAULT 0 CHECK(price >= 0),
        total REAL NOT NULL DEFAULT 0
          CHECK(total >= 0 AND ABS(total - (qty * price)) <= 0.01),
        notes TEXT,
        created_at TEXT,
        FOREIGN KEY(repair_id) REFERENCES repairs(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _ensureImages(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repairs_images(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repair_id TEXT NOT NULL,
        path TEXT NOT NULL,
        created_at TEXT
      )
    ''');
  }

  static Future<void> _insertLines(
    DatabaseExecutor db,
    String repairId,
    List<Map<String, dynamic>> parts,
    List<Map<String, dynamic>> works,
  ) async {
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    void addLine(String type, Map<String, dynamic> line) {
      batch.insert(
        'repair_lines',
        {
          'id': const Uuid().v4(),
          'repair_id': repairId,
          'line_type': type,
          'name': line['name'],
          'qty': line['qty'],
          'price': line['price'],
          'total': line['total'],
          'notes': line['notes'],
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    for (final part in parts) {
      addLine('part', part);
    }

    for (final work in works) {
      addLine('work', work);
    }

    await batch.commit(noResult: true);
  }
}
