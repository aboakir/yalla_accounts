import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/db/tables/party_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/sync_foundation_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/unified_sync_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v80 to v81 backfills Purchase stable references without fake sync',
      () async {
    final dir = await Directory.systemTemp.createTemp('phase09_v81_');
    final path = '${dir.path}/fixture.db';
    var db = await DatabaseMigration.initDatabase(pathOverride: path);
    try {
      expect(DatabaseConstants.dbVersion, 81);
      expect(await db.getVersion(), 81);
      final supplierId = await db.insert('suppliers', {
        'name': 'Migration Supplier',
        'phone': '',
        'address': '',
      });
      final partyId = await PartyTables.resolvePartyId(
        db,
        role: 'SUPPLIER',
        legacyId: supplierId,
      );
      expect(partyId, isNotNull);
      final partyIdentity = (await db.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND local_id=?',
        whereArgs: ['party', partyId],
      ))
          .single;
      final partyUuid = partyIdentity['entity_uuid']!.toString();

      const invoiceId = 'phase09-migration-purchase';
      final now = DateTime.utc(2026, 9, 16, 20).toIso8601String();
      await db.insert('purchase_invoices', {
        'id': invoiceId,
        'supplier_id': supplierId,
        'supplier_party_uuid': partyUuid,
        'is_active': 1,
        'purchase_type': 'PARTS',
        'subtotal': 200.0,
        'total': 200.0,
        'amount_total': 200.0,
        'paid_total': 0.0,
        'remaining': 200.0,
        'status': 'UNPAID',
        'date': now,
        'method': 'credit',
        'created_at': now,
        'updated_at': now,
      });
      final invoiceIdentity = (await db.query(
        SyncFoundationTables.registry,
        where: 'entity_type=? AND local_id=?',
        whereArgs: ['purchase_invoice', invoiceId],
      ))
          .single;
      final invoiceUuid = invoiceIdentity['entity_uuid']!.toString();

      const paymentId = 'phase09-migration-payment';
      await db.insert('purchase_payments', {
        'id': paymentId,
        'invoice_id': invoiceId,
        'purchase_invoice_entity_uuid': invoiceUuid,
        'amount': 20.0,
        'date': now,
        'method': 'CASH',
        'created_at': now,
        'updated_at': now,
      });

      final localBefore = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM ${SyncFoundationTables.changes} WHERE origin='local'",
      ))
          .single['c'] as int;

      await db.execute('DROP TRIGGER IF EXISTS trg_sync_v3_change_to_outbox');
      await db
          .execute('DROP TRIGGER IF EXISTS trg_sync_v3_outbox_identity_guard');
      for (final table in ['purchase_invoices', 'purchase_payments']) {
        for (final op in ['insert', 'update', 'delete']) {
          await db.execute('DROP TRIGGER IF EXISTS trg_sync_${table}_$op');
        }
      }
      await db.rawUpdate('''UPDATE ${UnifiedSyncTables.outbox}
        SET payload_json=json_remove(payload_json,
          '\$.supplier_party_uuid','\$.purchase_invoice_entity_uuid')
        WHERE entity_type IN ('purchase_invoice','purchase_payment')''');
      await db.execute(
        'ALTER TABLE purchase_invoices DROP COLUMN supplier_party_uuid',
      );
      await db.execute(
        'ALTER TABLE purchase_invoices DROP COLUMN is_active',
      );
      await db.execute(
        'ALTER TABLE purchase_payments DROP COLUMN purchase_invoice_entity_uuid',
      );
      await db.delete('schema_migrations', where: 'version=?', whereArgs: [81]);
      await db.setVersion(80);
      await db.close();

      db = await DatabaseMigration.initDatabase(pathOverride: path);
      expect(await db.getVersion(), 81);
      expect(
        await db
            .query('schema_migrations', where: 'version=?', whereArgs: [81]),
        hasLength(1),
      );
      final invoice = (await db.query(
        'purchase_invoices',
        where: 'id=?',
        whereArgs: [invoiceId],
      ))
          .single;
      expect(invoice['supplier_party_uuid'], partyUuid);
      expect(invoice['is_active'], 1);
      final payment = (await db.query(
        'purchase_payments',
        where: 'id=?',
        whereArgs: [paymentId],
      ))
          .single;
      expect(payment['purchase_invoice_entity_uuid'], invoiceUuid);

      final invoicePayloadRow = (await db.query(
        UnifiedSyncTables.outbox,
        columns: ['payload_json'],
        where: "entity_type='purchase_invoice' AND entity_id=?",
        whereArgs: [invoiceId],
        orderBy: 'created_at DESC',
        limit: 1,
      ))
          .single;
      final invoicePayload = Map<String, dynamic>.from(
        jsonDecode(invoicePayloadRow['payload_json']!.toString()) as Map,
      );
      expect(invoicePayload['supplier_party_uuid'], partyUuid);
      expect(invoicePayload.containsKey('supplier_id'), isFalse);
      expect(invoicePayload.containsKey('gl_entry_id'), isFalse);
      expect(invoicePayload.containsKey('paid_total'), isFalse);
      expect(invoicePayload.containsKey('remaining'), isFalse);
      expect(invoicePayload.containsKey('status'), isFalse);

      final paymentPayloadRow = (await db.query(
        UnifiedSyncTables.outbox,
        columns: ['payload_json'],
        where: "entity_type='purchase_payment' AND entity_id=?",
        whereArgs: [paymentId],
        orderBy: 'created_at DESC',
        limit: 1,
      ))
          .single;
      final paymentPayload = Map<String, dynamic>.from(
        jsonDecode(paymentPayloadRow['payload_json']!.toString()) as Map,
      );
      expect(paymentPayload['purchase_invoice_entity_uuid'], invoiceUuid);
      expect(paymentPayload.containsKey('invoice_id'), isFalse);
      expect(paymentPayload.containsKey('gl_entry_id'), isFalse);

      final localAfter = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM ${SyncFoundationTables.changes} WHERE origin='local'",
      ))
          .single['c'] as int;
      expect(localAfter, localBefore);
    } finally {
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });
}
