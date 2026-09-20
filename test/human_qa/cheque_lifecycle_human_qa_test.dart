import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('YA-HUMAN-024 deposited incoming cheque appears under collection',
      () async {
    final dir = await Directory.systemTemp.createTemp('cheque_collection_');
    final db = await DatabaseMigration.initDatabase(
      pathOverride: '${dir.path}/test.db',
    );
    DatabaseMigration.useDatabaseForTesting(db);

    try {
      late int chequeId;
      await db.transaction((txn) async {
        chequeId = await ChequeAccountingService.createLinkedChequeOnTxn(
          txn: txn,
          draft: <String, dynamic>{
            'cheque_no': 'QA-024',
            'drawer_name': 'Human QA Client',
            'bank_name': 'QA Bank',
            'bank_branch': 'Bethlehem',
            'issue_date': DateTime(2026, 9, 19).toIso8601String(),
            'due_date': DateTime(2026, 9, 25).toIso8601String(),
          },
          type: ChequeType.incoming,
          amount: 750,
          currency: 'ILS',
          sourceType: 'PAYMENT',
          sourceId: 'qa-payment-024',
          clientId: 1,
        );
        await ChequeAccountingService.transitionStatusOnTxn(
          txn: txn,
          chequeId: chequeId,
          newStatus: ChequeStatus.deposited,
          eventDate: DateTime(2026, 9, 19),
        );
      });

      final collection = await ChequeService().fetchFiltered(
        status: ChequeStatus.deposited,
      );
      expect(collection.map((c) => c.id), contains(chequeId));
      expect(collection.single.status, ChequeStatus.deposited);
      expect(collection.single.chequeType, ChequeType.incoming);
    } finally {
      DatabaseMigration.useDatabaseForTesting(null);
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    }
  });

  test('YA-HUMAN-025 incoming manual add is routed to canonical receipt', () {
    final screen = File(
      'lib/features/cheques/screens/cheque_add_screen.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/cheques/services/cheque_service.dart',
    ).readAsStringSync();

    expect(screen, contains('AppRoutes.receiptVoucher'));
    expect(screen, contains('استلام الشيك وربطه بسند قبض'));
    expect(
      service,
      contains(
          'Incoming cheques must be received through the canonical receipt flow'),
    );
  });
}
