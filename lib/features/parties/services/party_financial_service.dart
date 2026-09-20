import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/offline_outbox_service.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:uuid/uuid.dart';

class PartyBalanceSummary {
  const PartyBalanceSummary({
    required this.partyId,
    required this.displayName,
    required this.customerLegacyId,
    required this.supplierLegacyId,
    required this.totalReceivable,
    required this.received,
    required this.receivableBalance,
    required this.totalPayable,
    required this.paid,
    required this.payableBalance,
  });

  final String partyId;
  final String displayName;
  final String? customerLegacyId;
  final String? supplierLegacyId;
  final double totalReceivable;
  final double received;
  final double receivableBalance;
  final double totalPayable;
  final double paid;
  final double payableBalance;

  bool get isCustomer => customerLegacyId != null;
  bool get isSupplier => supplierLegacyId != null;
  bool get isCustomerAndSupplier => isCustomer && isSupplier;
}

class PartyLedgerLine {
  const PartyLedgerLine({
    required this.entryId,
    required this.date,
    required this.source,
    required this.sourceNumber,
    required this.description,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    this.sourceId,
    this.invoiceId,
    this.repairId,
  });

  final int entryId;
  final DateTime date;
  final String source;
  final String sourceNumber;
  final String description;
  final double debit;
  final double credit;
  final double runningBalance;
  final String? sourceId;
  final String? invoiceId;
  final String? repairId;
}

class PartyLedgerStatement {
  const PartyLedgerStatement({
    required this.partyId,
    required this.displayName,
    required this.role,
    required this.openingBalance,
    required this.closingBalance,
    required this.lines,
  });

  final String partyId;
  final String displayName;
  final String role;
  final double openingBalance;
  final double closingBalance;
  final List<PartyLedgerLine> lines;
}

class PartyFinancialService {
  PartyFinancialService._();

  static Future<void> createParty(
      {required String name,
      required String phone,
      required String address,
      required bool customer,
      required bool supplier,
      Database? database}) async {
    if (name.trim().isEmpty || (!customer && !supplier)) {
      throw ArgumentError('أدخل الاسم واختر دورًا واحدًا على الأقل');
    }
    final db = database ?? await DBService.database;
    int? customerId;
    int? supplierId;
    final partyId = const Uuid().v4();
    await SyncFoundationService.transaction(db, (txn) async {
      final existing = await txn.rawQuery(
          'SELECT id FROM parties WHERE LOWER(TRIM(display_name))=LOWER(?) AND merged_into_id IS NULL',
          [name.trim()]);
      if (existing.isNotEmpty) {
        throw StateError(
            'توجد جهة بهذا الاسم. استخدم سجلها الحالي أو خيار الربط.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final roles = <String>[
        if (customer) 'CUSTOMER',
        if (supplier) 'SUPPLIER',
      ]..sort();
      await PartyTables.setLegacyProjectionSuppressed(txn, true);
      try {
        await txn.insert('parties', {
          'id': partyId,
          'display_name': name.trim(),
          'phone': phone.trim(),
          'email': '',
          'address': address.trim(),
          'notes': '',
          'role_codes': jsonEncode(roles),
          'is_active': 1,
          'merged_into_id': null,
          'created_at': now,
          'updated_at': now,
        });
        if (customer) {
          customerId = await txn.insert('clients', {
            'name': name.trim(),
            'type': 'أفراد',
            'phone': phone.trim(),
            'address': address.trim(),
            'email': '',
            'notes': ''
          });
          await txn.insert('party_roles', {
            'party_id': partyId,
            'role': 'CUSTOMER',
            'legacy_id': customerId.toString(),
            'created_at': now,
          });
        }
        if (supplier) {
          supplierId = await txn.insert('suppliers', {
            'name': name.trim(),
            'phone': phone.trim(),
            'address': address.trim()
          });
          await txn.update(
              'suppliers', {'pid': 'S${supplierId.toString().padLeft(4, '0')}'},
              where: 'id=?', whereArgs: [supplierId]);
          await txn.insert('party_roles', {
            'party_id': partyId,
            'role': 'SUPPLIER',
            'legacy_id': supplierId.toString(),
            'created_at': now,
          });
        }
        if (!await SyncFoundationTables.isInstalled(txn)) {
          await OfflineOutboxService.enqueue(
            txn,
            channel: OfflineOutboxService.channelSync,
            operation: 'UPSERT',
            entityType: 'party',
            entityId: partyId,
            idempotencyKey: 'party:$partyId:create',
            payload: {
              'schema': 3,
              'id': partyId,
              'display_name': name.trim(),
              'phone': phone.trim(),
              'email': '',
              'address': address.trim(),
              'notes': '',
              'role_codes': roles,
              'is_active': 1,
              'created_at': now,
            },
          );
        }
      } finally {
        await PartyTables.setLegacyProjectionSuppressed(txn, false);
      }
    });
    if (database == null) {
      if (customerId != null) {
        try {
          await DBService.ensureClientAccount(customerId!);
        } catch (_) {}
      }
      if (supplierId != null) {
        try {
          await DBService.ensureSupplierAccount('$supplierId');
        } catch (_) {}
      }
    }
  }

  static double _d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _i(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _role(String role) {
    final canonical = PartyTables.canonicalRole(role);
    if (canonical != 'CUSTOMER' && canonical != 'SUPPLIER') {
      throw ArgumentError('Unsupported financial Party role: $role');
    }
    return canonical;
  }

  static Future<String> resolvePartyId({
    required String role,
    required Object legacyId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final canonical = _role(role);
    final partyId = await PartyTables.resolvePartyId(
      db,
      role: canonical,
      legacyId: legacyId,
    );
    if (partyId == null || partyId.trim().isEmpty) {
      throw StateError(
        'Party mapping missing for $canonical:${PartyTables.canonicalLegacyId(canonical, legacyId)}',
      );
    }
    return partyId;
  }

  static Future<void> linkCustomerAndSupplier({
    required Object customerId,
    required Object supplierId,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final customerPartyId = await resolvePartyId(
      role: 'CUSTOMER',
      legacyId: customerId,
      executor: db,
    );
    await PartyTables.attachRoleToParty(
      db,
      targetPartyId: customerPartyId,
      role: 'SUPPLIER',
      legacyId: supplierId,
    );
  }

  static Future<List<PartyBalanceSummary>> balances({
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final where = <String>[];
    final args = <Object?>[];

    // Balances retain opening movements. The start date selects active parties,
    // never truncates their balance history.
    if (to != null) {
      where.add('substr(e.date,1,10) <= substr(?,1,10)');
      args.add(
        DateTime(to.year, to.month, to.day, 23, 59, 59, 999).toIso8601String(),
      );
    }

    if (from != null) {
      where.add('''EXISTS (SELECT 1 FROM v_party_gl_lines activity
        JOIN gl_entries ae ON ae.id=activity.entry_id
        WHERE activity.canonical_party_id=p.id AND substr(ae.date,1,10) >= substr(?,1,10)
          ${to == null ? '' : 'AND substr(ae.date,1,10) <= substr(?,1,10)'})''');
      args.add(DateTime(from.year, from.month, from.day).toIso8601String());
      if (to != null) {
        args.add(DateTime(to.year, to.month, to.day, 23, 59, 59, 999)
            .toIso8601String());
      }
    }
    final dateClause = where.isEmpty ? '' : 'AND ${where.join(' AND ')}';
    const paymentSources =
        "'PAYMENT', 'PAYMENT_OUT', 'VOUCHER', 'PURCHASE_PAYMENT', 'PURCHASE_PAY', 'SUPPLIER_PAYMENT', 'CREDIT_ALLOCATION', 'PAYMENT-ADJUST', 'CHEQUE_STATUS', 'CHEQUE_ENDORSE'";
    const payment =
        'UPPER(COALESCE(original.source, e.source)) IN ($paymentSources)';

    final rows = await db.rawQuery('''
      SELECT
        p.id AS party_id,
        p.display_name,
        (SELECT prc.legacy_id FROM party_roles prc WHERE prc.party_id=p.id AND prc.role='CUSTOMER' LIMIT 1) AS customer_id,
        (SELECT prs.legacy_id FROM party_roles prs WHERE prs.party_id=p.id AND prs.role='SUPPLIER' LIMIT 1) AS supplier_id,
        COALESCE(SUM(CASE WHEN v.party_role='CUSTOMER' THEN v.debit ELSE 0 END),0) AS ar_debit,
        COALESCE(SUM(CASE WHEN v.party_role='CUSTOMER' THEN v.credit ELSE 0 END),0) AS ar_credit,
        COALESCE(SUM(CASE WHEN v.party_role='SUPPLIER' THEN v.credit ELSE 0 END),0) AS ap_credit,
        COALESCE(SUM(CASE WHEN v.party_role='SUPPLIER' THEN v.debit ELSE 0 END),0) AS ap_debit,
        COALESCE(SUM(CASE WHEN v.party_role='CUSTOMER' AND $payment THEN v.credit-v.debit ELSE 0 END),0) AS receipts,
        COALESCE(SUM(CASE WHEN v.party_role='SUPPLIER' AND $payment THEN v.debit-v.credit ELSE 0 END),0) AS disbursements
      FROM parties p
      LEFT JOIN v_party_gl_lines v ON v.canonical_party_id=p.id
      LEFT JOIN gl_entries e ON e.id=v.entry_id
      LEFT JOIN gl_entries original ON original.id=e.reversal_of
      WHERE p.merged_into_id IS NULL
        AND EXISTS (SELECT 1 FROM party_roles live_role WHERE live_role.party_id=p.id)
        $dateClause
      GROUP BY p.id, p.display_name
      ORDER BY LOWER(p.display_name) ASC
    ''', args);

    return rows.map((row) {
      final arDebit = _d(row['ar_debit']);
      final arCredit = _d(row['ar_credit']);
      final apCredit = _d(row['ap_credit']);
      final apDebit = _d(row['ap_debit']);
      return PartyBalanceSummary(
        partyId: row['party_id'].toString(),
        displayName: (row['display_name'] ?? '').toString(),
        customerLegacyId: row['customer_id']?.toString(),
        supplierLegacyId: row['supplier_id']?.toString(),
        totalReceivable: double.parse(
            (arDebit - arCredit + _d(row['receipts'])).toStringAsFixed(2)),
        received: double.parse(_d(row['receipts']).toStringAsFixed(2)),
        receivableBalance:
            double.parse((arDebit - arCredit).toStringAsFixed(2)),
        totalPayable: double.parse(
            (apCredit - apDebit + _d(row['disbursements'])).toStringAsFixed(2)),
        paid: double.parse(_d(row['disbursements']).toStringAsFixed(2)),
        payableBalance: double.parse((apCredit - apDebit).toStringAsFixed(2)),
      );
    }).toList(growable: false);
  }

  static Future<PartyLedgerStatement> statement({
    required String role,
    bool combined = false,
    required Object legacyId,
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    if (from != null &&
        to != null &&
        DateTime(from.year, from.month, from.day)
            .isAfter(DateTime(to.year, to.month, to.day))) {
      throw ArgumentError('بداية الفترة بعد نهايتها');
    }
    final db = executor ?? await DBService.database;
    final canonicalRole = _role(role);
    final partyId = await resolvePartyId(
      role: canonicalRole,
      legacyId: legacyId,
      executor: db,
    );

    final partyRows = await db.query(
      'parties',
      columns: const ['display_name'],
      where: 'id=?',
      whereArgs: [partyId],
      limit: 1,
    );
    final displayName = partyRows.isEmpty
        ? partyId
        : (partyRows.first['display_name'] ?? partyId).toString();

    final fromIso = from == null
        ? null
        : DateTime(from.year, from.month, from.day).toIso8601String();
    final toIso = to == null
        ? null
        : DateTime(to.year, to.month, to.day, 23, 59, 59, 999)
            .toIso8601String();

    final sign = combined || canonicalRole == 'CUSTOMER' ? 1.0 : -1.0;

    var opening = 0.0;
    if (fromIso != null) {
      final openingRows = await db.rawQuery('''
        SELECT COALESCE(SUM((v.debit-v.credit) * ?),0) AS balance
        FROM v_party_gl_lines v
        JOIN gl_entries e ON e.id=v.entry_id
        WHERE v.canonical_party_id=?
          AND (? = 1 OR v.party_role=?)
          AND substr(e.date,1,10) < substr(?,1,10)
      ''', [sign, partyId, combined ? 1 : 0, canonicalRole, fromIso]);
      opening = openingRows.isEmpty ? 0.0 : _d(openingRows.first['balance']);
    }

    final where = <String>[
      'v.canonical_party_id=?',
      if (!combined) 'v.party_role=?',
    ];
    final args = <Object?>[partyId, if (!combined) canonicalRole];
    if (fromIso != null) {
      where.add('substr(e.date,1,10) >= substr(?,1,10)');
      args.add(fromIso);
    }
    if (toIso != null) {
      where.add('substr(e.date,1,10) <= substr(?,1,10)');
      args.add(toIso);
    }

    final rows = await db.rawQuery('''
      SELECT
        e.id AS entry_id,
        e.date,
        e.source,
        e.source_id,
        e.source_number,
        e.note,
        e.reversal_of,
        v.debit,
        v.credit,
        v.invoice_id,
        v.repair_id
      FROM v_party_gl_lines v
      JOIN gl_entries e ON e.id=v.entry_id
      WHERE ${where.join(' AND ')}
      ORDER BY e.date ASC, e.id ASC, v.gl_line_id ASC
    ''', args);

    var running = opening;
    final lines = <PartyLedgerLine>[];
    for (final row in rows) {
      final rawDebit = _d(row['debit']);
      final rawCredit = _d(row['credit']);

      final debit =
          combined || canonicalRole == 'CUSTOMER' ? rawDebit : rawCredit;
      final credit =
          combined || canonicalRole == 'CUSTOMER' ? rawCredit : rawDebit;
      // Keep full precision while accumulating. Rounding every row creates
      // cumulative drift versus the balance engine for historical fractional
      // postings; only presentation/final balances are rounded to currency.
      running += debit - credit;
      final roundedRunning = double.parse(running.toStringAsFixed(2));

      final source = (row['source'] ?? '').toString();
      final sourceNumber = (row['source_number'] ?? '').toString().trim();
      lines.add(
        PartyLedgerLine(
          entryId: _i(row['entry_id']),
          date: DateTime.tryParse(row['date']?.toString() ?? '') ??
              DateTime.now(),
          source: source,
          sourceNumber: sourceNumber,
          sourceId: row['source_id']?.toString(),
          description: _description(source, row),
          debit: double.parse(debit.toStringAsFixed(2)),
          credit: double.parse(credit.toStringAsFixed(2)),
          runningBalance: roundedRunning,
          invoiceId: row['invoice_id']?.toString(),
          repairId: row['repair_id']?.toString(),
        ),
      );
    }

    return PartyLedgerStatement(
      partyId: partyId,
      displayName: displayName,
      role: combined ? 'COMBINED' : canonicalRole,
      openingBalance: double.parse(opening.toStringAsFixed(2)),
      closingBalance: double.parse(running.toStringAsFixed(2)),
      lines: lines,
    );
  }

  static String _description(String source, Map<String, Object?> row) {
    final upper = source.toUpperCase();
    if (row['reversal_of'] != null || upper.contains('REVERS')) {
      return 'عكس / إلغاء حركة مالية';
    }
    if (upper.contains('PURCHASE')) return 'مشتريات / فاتورة مورد';
    if (upper.contains('INVOICE')) return 'فاتورة / إثبات ذمة';
    if (upper.contains('RECEIPT') || upper == 'PAYMENT') return 'سند قبض';
    if (upper.contains('VOUCHER')) return 'سند صرف';
    if (upper.contains('RETURN') || upper.contains('CREDIT')) {
      return 'مرتجع / إشعار دائن';
    }
    if (upper.contains('ADJUST')) return 'تسوية';
    final note = (row['note'] ?? '').toString().trim();
    return note.isEmpty ? source : note;
  }
}
