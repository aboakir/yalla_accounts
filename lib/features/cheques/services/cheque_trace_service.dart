import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';

class ChequeTraceResult {
  const ChequeTraceResult({
    required this.cheque,
    required this.voucherLinks,
    required this.allocations,
    required this.events,
    required this.glEntries,
    required this.endorsements,
    required this.depositItems,
    required this.payments,
    required this.vouchers,
    required this.parties,
  });

  final Cheque cheque;
  final List<Map<String, Object?>> voucherLinks;
  final List<Map<String, Object?>> allocations;
  final List<Map<String, Object?>> events;
  final List<Map<String, Object?>> glEntries;
  final List<Map<String, Object?>> endorsements;
  final List<Map<String, Object?>> depositItems;
  final List<Map<String, Object?>> payments;
  final List<Map<String, Object?>> vouchers;
  final List<Map<String, Object?>> parties;
}

class ChequeTraceService {
  ChequeTraceService._();

  static Future<List<Cheque>> search(
    String query, {
    DatabaseExecutor? executor,
    int limit = 100,
  }) async {
    final db = executor ?? await DBService.database;
    final q = query.trim();
    if (q.isEmpty) {
      final rows = await db.query(
        'cheques',
        orderBy: 'due_date DESC, id DESC',
        limit: limit,
      );
      return rows.map(Cheque.fromMap).toList();
    }

    final like = '%$q%';
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT c.*
      FROM cheques c
      LEFT JOIN clients cl ON cl.id=c.client_id
      LEFT JOIN suppliers s
        ON CAST(s.id AS TEXT)=COALESCE(c.supplier_pid,'')
      LEFT JOIN cheque_voucher_links vl ON vl.cheque_id=c.id
      LEFT JOIN cheque_allocations ca ON ca.cheque_id=c.id
      LEFT JOIN payments p
        ON p.cheque_id=c.id
        OR (
          UPPER(COALESCE(c.source_type,''))='PAYMENT'
          AND p.id=c.source_id
        )
      LEFT JOIN vouchers v
        ON CAST(v.cheque_id AS TEXT)=CAST(c.id AS TEXT)
        OR (
          UPPER(COALESCE(c.source_type,''))='VOUCHER'
          AND v.id=c.source_id
        )
      LEFT JOIN gl_lines gl ON gl.cheque_id=c.id
      LEFT JOIN repairs r
        ON r.id=COALESCE(
          NULLIF(p.repair_id,''),
          NULLIF(p.relatedRepairId,''),
          NULLIF(gl.repair_id,''),
          CASE
            WHEN UPPER(COALESCE(ca.allocation_type,''))='REPAIR'
            THEN ca.target_id
            ELSE NULL
          END
        )
      WHERE
        COALESCE(c.cheque_no,'') LIKE ?
        OR COALESCE(c.drawer_name,'') LIKE ?
        OR COALESCE(c.recipient_name,'') LIKE ?
        OR COALESCE(c.bank_name,'') LIKE ?
        OR COALESCE(c.bank_branch,'') LIKE ?
        OR CAST(c.amount AS TEXT) LIKE ?
        OR COALESCE(vl.voucher_id,'') LIKE ?
        OR COALESCE(c.source_id,'') LIKE ?
        OR COALESCE(ca.target_id,'') LIKE ?
        OR COALESCE(cl.name,'') LIKE ?
        OR COALESCE(s.name,'') LIKE ?
        OR COALESCE(p.id,'') LIKE ?
        OR COALESCE(p.repair_id,'') LIKE ?
        OR COALESCE(p.relatedRepairId,'') LIKE ?
        OR COALESCE(p.invoice_id,'') LIKE ?
        OR COALESCE(v.reference,'') LIKE ?
        OR COALESCE(v.party_id,'') LIKE ?
        OR COALESCE(gl.invoice_id,'') LIKE ?
        OR COALESCE(gl.repair_id,'') LIKE ?
        OR COALESCE(r.vehicleNumber,'') LIKE ?
        OR COALESCE(r.vehicleType,'') LIKE ?
        OR COALESCE(r.vehicleModel,'') LIKE ?
      ORDER BY c.due_date DESC, c.id DESC
      LIMIT ?
      ''',
      [
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        like,
        limit,
      ],
    );
    return rows.map(Cheque.fromMap).toList();
  }

  static Future<ChequeTraceResult> load(
    int chequeId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DBService.database;
    final chequeRows = await db.query(
      'cheques',
      where: 'id=?',
      whereArgs: [chequeId],
      limit: 1,
    );
    if (chequeRows.isEmpty) throw StateError('Cheque not found.');
    final cheque = Cheque.fromMap(chequeRows.single);

    final voucherLinks = await db.query(
      'cheque_voucher_links',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
      orderBy: 'id',
    );
    final allocations = await db.query(
      'cheque_allocations',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
      orderBy: 'id',
    );
    final events = await db.query(
      'cheque_events',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
      orderBy: 'id',
    );
    final endorsements = await db.query(
      'cheque_endorsements',
      where: 'cheque_id=?',
      whereArgs: [chequeId],
      orderBy: 'sequence_no',
    );
    final depositItems = await db.rawQuery(
      '''
      SELECT di.*, b.bank_account_id, b.deposit_date, b.status AS batch_status,
        b.total_value AS batch_total, b.cheque_count
      FROM cheque_deposit_items di
      JOIN cheque_deposit_batches b ON b.id=di.batch_id
      WHERE di.cheque_id=?
      ORDER BY di.id
      ''',
      [chequeId],
    );

    final glEntries = await db.rawQuery(
      '''
      SELECT
        e.id AS entry_id,
        e.date,
        e.source,
        e.source_id,
        e.source_number,
        e.ref,
        e.note,
        l.id AS line_id,
        a.code AS account_code,
        a.name AS account_name,
        l.debit,
        l.credit,
        l.party_type,
        l.party_id,
        l.invoice_id,
        l.repair_id
      FROM gl_lines l
      JOIN gl_entries e ON e.id=l.entry_id
      JOIN accounts a ON a.id=l.account_id
      WHERE l.cheque_id=?
         OR e.id=?
      ORDER BY e.id, l.id
      ''',
      [chequeId, cheque.glEntryId ?? -1],
    );

    final payments = await db.rawQuery(
      '''
      SELECT DISTINCT p.*
      FROM payments p
      WHERE p.cheque_id=?
        OR (
          UPPER(?)='PAYMENT'
          AND p.id=?
        )
      ORDER BY p.date, p.id
      ''',
      [chequeId, cheque.sourceType ?? '', cheque.sourceId ?? ''],
    );

    final vouchers = await db.rawQuery(
      '''
      SELECT DISTINCT v.*
      FROM vouchers v
      WHERE CAST(v.cheque_id AS TEXT)=?
        OR (
          UPPER(?)='VOUCHER'
          AND v.id=?
        )
        OR EXISTS(
          SELECT 1
          FROM cheque_voucher_links vl
          WHERE vl.cheque_id=?
            AND vl.voucher_type='PAYMENT'
            AND vl.voucher_id=v.id
        )
      ORDER BY v.date, v.id
      ''',
      [
        chequeId.toString(),
        cheque.sourceType ?? '',
        cheque.sourceId ?? '',
        chequeId,
      ],
    );

    final parties = <Map<String, Object?>>[];
    if (cheque.clientId != null) {
      final rows = await db.query(
        'clients',
        where: 'id=?',
        whereArgs: [cheque.clientId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        parties.add({
          'party_type': 'CLIENT',
          ...Map<String, Object?>.from(rows.single),
        });
      }
    }
    final supplierId = int.tryParse(cheque.supplierPid ?? '');
    if (supplierId != null) {
      final rows = await db.query(
        'suppliers',
        where: 'id=?',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        parties.add({
          'party_type': 'SUPPLIER',
          ...Map<String, Object?>.from(rows.single),
        });
      }
    }

    return ChequeTraceResult(
      cheque: cheque,
      voucherLinks:
          voucherLinks.map((e) => Map<String, Object?>.from(e)).toList(),
      allocations:
          allocations.map((e) => Map<String, Object?>.from(e)).toList(),
      events: events.map((e) => Map<String, Object?>.from(e)).toList(),
      glEntries: glEntries.map((e) => Map<String, Object?>.from(e)).toList(),
      endorsements:
          endorsements.map((e) => Map<String, Object?>.from(e)).toList(),
      depositItems:
          depositItems.map((e) => Map<String, Object?>.from(e)).toList(),
      payments: payments.map((e) => Map<String, Object?>.from(e)).toList(),
      vouchers: vouchers.map((e) => Map<String, Object?>.from(e)).toList(),
      parties: parties,
    );
  }
}
