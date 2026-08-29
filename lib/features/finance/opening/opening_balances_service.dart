// 📁 lib/features/finance/opening/opening_balances_service.dart
//
// OpeningBalancesService — أرصدة افتتاحية اختيارية.
// - عميل:   Dr AR-<client> / Cr Opening Equity(3100)
// - مورد:   Dr Opening Equity(3100) / Cr AP-<supplier>

import 'package:yalla_accounts/core/services/accounting_gl.dart';

class OpeningBalancesService {
  static const _openingEquity = GL.openingEquity;

  static Future<void> ensureOpeningEquity() async {
    await GL.ensureNamedAccount(
      code: _openingEquity,
      name: 'Opening Equity',
      type: 'EQUITY',
      normal: 'CREDIT',
    );
  }

  static Future<int> postClientOpening({
    required int clientId,
    required String clientName,
    required DateTime date,
    required double amount, // مدين على العميل
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    await ensureOpeningEquity();
    await GL.ensureCoreAccounts();

    final ar = await GL.ensureClientAccount(clientId, clientName);
    final oe = await GL.idByCode(_openingEquity);

    return GL.post(
      date: date,
      ref: 'OPEN-AR-$clientId',
      source: 'OPENING',
      sourceId: 'CLIENT:$clientId',
      note: note ?? 'رصيد افتتاحي عميل',
      lines: [
        {
          'account_id': ar,
          'debit': amount,
          'credit': 0.0,
          'party_type': 'CUSTOMER',
          'party_id': clientId.toString()
        },
        {'account_id': oe, 'debit': 0.0, 'credit': amount},
      ],
    );
  }

  static Future<int> postSupplierOpening({
    required String supplierId,
    required String supplierName,
    required DateTime date,
    required double amount, // دائن لصالح المورّد
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    await ensureOpeningEquity();
    await GL.ensureCoreAccounts();

    final ap = await GL.ensureSupplierAccount(supplierId, supplierName);
    final oe = await GL.idByCode(_openingEquity);

    return GL.post(
      date: date,
      ref: 'OPEN-AP-$supplierId',
      source: 'OPENING',
      sourceId: 'SUPPLIER:$supplierId',
      note: note ?? 'رصيد افتتاحي مورد',
      lines: [
        {'account_id': oe, 'debit': amount, 'credit': 0.0},
        {
          'account_id': ap,
          'debit': 0.0,
          'credit': amount,
          'party_type': 'SUPPLIER',
          'party_id': supplierId
        },
      ],
    );
  }
}
