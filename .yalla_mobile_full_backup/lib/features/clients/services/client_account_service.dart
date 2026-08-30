// 📁 lib/features/clients/services/client_account_service.dart
//
// ClientAccountService — نسخة منقحة ومطابقة تمامًا لـ DBService الحالي.
// تستخدم دوال DBService مباشرة بدون الحاجة لـ db_accounts.dart.

import 'package:yalla_accounts/core/services/db_service.dart';

class ClientAccountService {
  static ClientAccountService? _instance;
  ClientAccountService._();
  static ClientAccountService instance() {
    _instance ??= ClientAccountService._();
    return _instance!;
  }

  // ============================================================
  //  ضمان حساب العميل 1200.C<clientId>
  // ============================================================

  Future<int> ensureForClient(int clientId) async {
    final db = await DBService.database;

    // 1) تحقق من وجود account_id في جدول clients
    final row = await db.query(
      'clients',
      columns: const ['account_id'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );

    if (row.isEmpty) {
      throw Exception('Client not found: $clientId');
    }

    final existing = row.first['account_id'];
    if (existing != null) {
      final parsed =
          (existing is int) ? existing : int.tryParse(existing.toString());
      if (parsed != null) return parsed;
    }

    // 2) الحساب غير موجود — ننشئ حساب جديد 1200.C<id>
    final code = '1200.C$clientId';

    // نستخدم DBService بدلاً من دوال غير موجودة
    final accId = (await DBService.getAccountIdByCode(code)) ??
        await DBService.ensureAccount(
          code: code,
          name: 'ذمم مدينة - عميل $clientId',
          type: 'ASSET',
          normalBalance: 'DEBIT',
        );

    // 3) ربط الحساب الجديد مع العميل
    await db.update(
      'clients',
      {'account_id': accId},
      where: 'id = ?',
      whereArgs: [clientId],
    );

    return accId;
  }

  // ============================================================
  //  الحصول على account_id للعميل إن وجد
  // ============================================================

  Future<int?> getAccountIdForClient(int clientId) async {
    final db = await DBService.database;

    final row = await db.query(
      'clients',
      columns: const ['account_id'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );

    if (row.isEmpty) return null;

    final v = row.first['account_id'];
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
