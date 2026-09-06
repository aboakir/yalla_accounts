import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/purchase_invoices_table.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';

/// Canonical purchase invoice writer.
///
/// P14 guarantees:
/// - header + lines + GL are one SQLite transaction;
/// - legacy item/name/unit_price aliases are normalized before persistence;
/// - line category is persisted for purchase analytics/cost allocation;
/// - purchase posting remains the accounting event; later RepairCost allocation
///   is management-only and must not post GL again.
class PurchaseInvoiceService {
  static const _tableHeader = 'purchase_invoices';
  static const _tableLines = 'purchase_invoice_lines';

  static const _accExpensePurchase = '5900';
  static const _accCash = '1000';
  static const _accBank = '1010';
  static const _accApRoot = '2200';

  static double _number(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));

  static String _lineName(Map<String, dynamic> item, String purchaseType) {
    final value = (item['item_name'] ?? item['item'] ?? item['name'] ?? '')
        .toString()
        .trim();
    if (value.isNotEmpty) return value;
    switch (purchaseType.trim().toUpperCase()) {
      case 'PARTS':
        return 'قطع غيار';
      case 'RAW':
      case 'RAW_MATERIAL':
        return 'مواد خام';
      case 'PAINT':
        return 'دهان';
      default:
        return 'بند مشتريات';
    }
  }

  static String _lineCategory(
    Map<String, dynamic> item,
    String purchaseType,
  ) {
    final raw =
        (item['category'] ?? purchaseType).toString().trim().toUpperCase();
    if (raw == 'RAW_MATERIAL') return 'RAW';
    if (raw == 'PAINT') return 'PAINT';
    if (raw == 'PARTS') return 'PARTS';
    if (raw == 'TOOLS') return 'TOOLS';
    return raw.isEmpty ? 'OTHER' : raw;
  }

  static Future<String> createInvoice({
    required int supplierId,
    required DateTime date,
    required String? note,
    required List<Map<String, dynamic>> items,
    String purchaseType = 'OTHER',
    String? method,
  }) async {
    final p16Actor =
        await AuthorizationGuard.require(PermissionKeys.purchaseManage);
    if (supplierId <= 0) throw ArgumentError('معرّف المورد غير صالح');
    if (items.isEmpty) {
      throw ArgumentError('فاتورة المشتريات تحتاج بندًا واحدًا على الأقل');
    }

    final db = await DBService.database;
    await PurchaseInvoicesTable.createAllTables(db);
    final invoiceId = const Uuid().v4();
    final type = purchaseType.trim().isEmpty
        ? 'OTHER'
        : purchaseType.trim().toUpperCase();
    final normalized = <Map<String, Object?>>[];
    var total = 0.0;

    for (final item in items) {
      final qty = _number(
        item['qty'] ?? item['quantity'],
        fallback: 1,
      );
      final price = _number(
        item['price'] ?? item['unit_price'] ?? item['unitPrice'],
      );
      if (qty <= 0) {
        throw ArgumentError('كمية المشتريات يجب أن تكون أكبر من صفر');
      }
      if (price < 0) {
        throw ArgumentError('سعر الشراء لا يمكن أن يكون سالبًا');
      }
      final lineTotal = _round2(qty * price);
      final name = _lineName(item, type);
      normalized.add({
        'id': const Uuid().v4(),
        'invoice_id': invoiceId,
        'item': name,
        'item_name': name,
        'qty': qty,
        'unit_price': price,
        'price': price,
        'total': lineTotal,
        'category': _lineCategory(item, type),
        'note': item['note']?.toString(),
      });
      total += lineTotal;
    }
    total = _round2(total);
    if (total <= 0) {
      throw ArgumentError('إجمالي فاتورة المشتريات يجب أن يكون أكبر من صفر');
    }

    final m = _normalizeMethod(method);
    final cashAcc = await _accId(db, _accCash);
    final bankAcc = await _accId(db, _accBank);
    final expenseAcc = await _accId(db, _accExpensePurchase);
    final apRootAcc = await _accId(db, _accApRoot);
    if (cashAcc == null ||
        bankAcc == null ||
        expenseAcc == null ||
        apRootAcc == null) {
      throw StateError(
        'Missing essential accounts: 1000 / 1010 / 5900 / 2200',
      );
    }

    late int creditAcc;
    late String status;
    if (m == 'cash') {
      creditAcc = cashAcc;
      status = 'PAID';
    } else if (m == 'bank') {
      creditAcc = bankAcc;
      status = 'PAID';
    } else {
      creditAcc = await DBService.ensureSupplierAccount(supplierId.toString());
      status = 'UNPAID';
    }

    final now = DateTime.now().toIso8601String();
    await db.transaction((tx) async {
      await tx.insert(_tableHeader, {
        'id': invoiceId,
        'supplier_id': supplierId,
        'date': date.toIso8601String(),
        'note': note,
        'subtotal': total,
        'total': total,
        'amount_total': total,
        'paid_total': 0.0,
        'remaining': status == 'PAID' ? 0.0 : total,
        'status': status,
        'purchase_type': type,
        'method': m,
        'created_at': now,
        'updated_at': now,
      });

      for (final line in normalized) {
        await tx.insert(_tableLines, line);
      }

      final glId = await DBService.postEntryGLOn(
        ex: tx,
        date: date,
        ref: invoiceId,
        source: 'PURCHASE',
        sourceId: invoiceId,
        note: note,
        lines: [
          {
            'account_id': creditAcc,
            'credit': total,
            'debit': 0.0,
            'party_type': m == 'credit' ? 'SUPPLIER' : null,
            'party_id': m == 'credit' ? supplierId : null,
          },
          {
            'account_id': expenseAcc,
            'debit': total,
            'credit': 0.0,
          },
        ],
      );

      await tx.update(
        _tableHeader,
        {
          'gl_entry_id': glId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });

    await AuditTrailService.log(
      actorUserId: p16Actor?.id,
      actorRole: p16Actor?.role,
      action: 'PURCHASE_INVOICE_CREATED',
      entityType: 'purchase_invoice',
      entityId: invoiceId,
      after: {
        'supplier_id': supplierId,
        'date': date.toIso8601String(),
        'total': total,
        'method': m,
        'purchase_type': type,
        'line_count': normalized.length,
      },
      reason: note,
    );
    return invoiceId;
  }

  static String _normalizeMethod(String? m) {
    final x = (m ?? '').toLowerCase();
    if (x.contains('cash') || x.contains('نقد')) return 'cash';
    if (x.contains('bank') || x.contains('بنك') || x.contains('transfer')) {
      return 'bank';
    }
    return 'credit';
  }

  static Future<int?> _accId(Database db, String code) async {
    final rows = await db.query(
      'accounts',
      columns: const ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['id'];
    return value is int ? value : int.tryParse(value.toString());
  }
}
