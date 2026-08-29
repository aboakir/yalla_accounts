// 📁 lib/core/services/migrations/opening_balances_migration.dart
//
// OpeningBalancesMigration — توليد حسابات للعملاء/الموردين الموجدين وربطها.
// خيارياً ينشر أرصدة افتتاحية على تاريخ محدد.
// الاستخدام:
//   await OpeningBalancesMigration.run(date: DateTime(2025,1,1), postOpening: false);

import 'package:yalla_accounts/core/services/db_service.dart';

class OpeningBalancesMigration {
  /// postOpening=true ينشر قيود افتتاحية لكل حساب بقيمة 0 افتراضياً
  /// يمكنك تمرير خريطة أرصدة اختيارية: clientId -> amount, supplierId -> amount.
  static Future<void> run(
      {DateTime? date,
      bool postOpening = false,
      Map<int, double>? clientOpenings, // عميل -> رصيد مدين +
      Map<String, double>? supplierOpenings // مورد -> رصيد دائن +
      }) async {
    final db = await DBService.database;

    // 1) عملاء
    final clients =
        await db.query('clients', columns: ['id', 'name', 'account_id']);
    for (final c in clients) {
      final cid = _toInt(c['id']);
      if (cid == null) continue;
      final acc = c['account_id'];
      if (acc == null) {
        try {
          await DBService.ensureClientAccount(cid);
        } catch (_) {}
      }
    }

    // 2) موردون
    final suppliers =
        await db.query('suppliers', columns: ['id', 'name', 'account_id']);
    for (final s in suppliers) {
      final sid = (s['id'] ?? '').toString();
      if (sid.isEmpty) continue;
      final acc = s['account_id'];
      if (acc == null) {
        try {
          await DBService.ensureSupplierAccount(sid);
        } catch (_) {}
      }
    }

    if (!postOpening) return;

    final openDate = date ?? DateTime.now();

    // أرصدة افتتاحية بسيطة: عميل مدين، مورد دائن.
    if (clientOpenings != null && clientOpenings.isNotEmpty) {
      for (final e in clientOpenings.entries) {
        final cid = e.key;
        final amount = e.value;
        if (amount <= 0) continue;

        // احصل على account_id
        final accId = await _clientAccountId(cid);
        if (accId == null) continue;

        await DBService.postEntryGL(
          date: openDate,
          source: 'OPENING',
          sourceId: 'OPEN-AR-$cid',
          note: 'Opening balance AR for client $cid',
          lines: [
            {
              'account_id': accId,
              'debit': amount,
              'credit': 0.0,
              'party_type': 'CUSTOMER',
              'party_id': cid.toString()
            },
            // موازنة على حساب افتراضي "أرصدة افتتاحية" إن أردت لاحقاً
          ],
        );
      }
    }

    if (supplierOpenings != null && supplierOpenings.isNotEmpty) {
      for (final e in supplierOpenings.entries) {
        final sid = e.key;
        final amount = e.value;
        if (amount <= 0) continue;

        final accId = await _supplierAccountId(sid);
        if (accId == null) continue;

        await DBService.postEntryGL(
          date: openDate,
          source: 'OPENING',
          sourceId: 'OPEN-AP-$sid',
          note: 'Opening balance AP for supplier $sid',
          lines: [
            {
              'account_id': accId,
              'debit': 0.0,
              'credit': amount,
              'party_type': 'SUPPLIER',
              'party_id': sid
            },
            // موازنة على حساب افتراضي "أرصدة افتتاحية" إن أردت لاحقاً
          ],
        );
      }
    }
  }

  static int? _toInt(Object? v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  static Future<int?> _clientAccountId(int clientId) async {
    final db = await DBService.database;
    final r = await db.query('clients',
        columns: ['account_id'],
        where: 'id=?',
        whereArgs: [clientId],
        limit: 1);
    if (r.isEmpty) return null;
    final v = r.first['account_id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  static Future<int?> _supplierAccountId(String supplierId) async {
    final db = await DBService.database;
    final r = await db.query('suppliers',
        columns: ['account_id'],
        where: 'id=?',
        whereArgs: [supplierId],
        limit: 1);
    if (r.isEmpty) return null;
    final v = r.first['account_id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }
}
