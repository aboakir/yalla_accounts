import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readSource(String path) => File(path).readAsStringSync();

void main() {
  test('P0.008 database version and canonical cheque accounts', () {
    final constants = readSource(
      'lib/core/services/db/database_constants.dart',
    );
    final tables = readSource(
      'lib/core/services/db/tables/cheque_tables.dart',
    );

    final versionMatch = RegExp(r'dbVersion\s*=\s*(\d+)').firstMatch(constants);
    expect(versionMatch, isNotNull);
    expect(int.parse(versionMatch!.group(1)!), greaterThanOrEqualTo(56));
    expect(tables.contains("code: '1020'"), isTrue);
    expect(tables.contains("code: '1030'"), isTrue);
    expect(tables.contains('cheque_events'), isTrue);
    expect(tables.contains('uq_cheques_source'), isTrue);

    // Maturity alone must never mark a cheque returned.
    expect(tables.contains("due_date < ?"), isFalse);
  });

  test('P0.008 outgoing voucher creates real cheque and credits 1030', () {
    final source = readSource(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    );

    expect(source.contains('createLinkedChequeOnTxn'), isTrue);
    expect(source.contains('ChequeType.outgoing'), isTrue);
    expect(source.contains("'1030'"), isTrue);
    expect(source.contains('attachInitialGlOnTxn'), isTrue);
    expect(
      source.contains('Cheque creation/linkage is completed in P0.008'),
      isFalse,
    );
  });

  test('P0.008 incoming receipt creates real cheque and debits 1020', () {
    final source = readSource(
      'lib/features/finance/payments/services/payment_service.dart',
    );

    expect(source.contains('ChequeType.incoming'), isTrue);
    expect(source.contains("'1020'"), isTrue);
    expect(source.contains('attachInitialGlOnTxn'), isTrue);
    expect(
      source.contains('temporarily blocked until P0.008'),
      isFalse,
    );
    expect(
      source
          .contains('Outgoing cheque payments must use VoucherPaymentService'),
      isTrue,
    );
  });

  test('P0.008 receipt screen no longer inserts cheques directly', () {
    final source = readSource(
      'lib/features/vouchers/screens/receipt_voucher_screen.dart',
    );

    expect(source.contains('db.insert("cheques"'), isFalse);
    expect(source.contains('chequeDraft:'), isTrue);
    expect(
      source.contains('الشيك الواحد يجب ربطه بملف واحد'),
      isTrue,
    );
  });

  test('P0.008 linked cheques are immutable and not destructively deleted', () {
    final source = readSource(
      'lib/features/cheques/services/cheque_service.dart',
    );

    expect(source.contains('ChequeLinkService'), isFalse);
    expect(
      source.contains('An accounted/linked cheque is immutable.'),
      isTrue,
    );
    expect(
      source.contains('Cannot delete a linked/accounted cheque.'),
      isTrue,
    );
    expect(source.contains('isLegacyIncomplete'), isTrue);
  });

  test('P0.008 legacy parallel cheque services cannot corrupt accounting', () {
    final link = readSource(
      'lib/features/cheques/services/cheque_link_service.dart',
    );
    final gl = readSource(
      'lib/features/cheques/services/cheque_gl_service.dart',
    );
    final endorsement = readSource(
      'lib/features/cheques/services/cheque_endorsement_service.dart',
    );

    expect(link.contains('Legacy cheque-to-payment auto-generation'), isTrue);
    expect(gl.contains('Legacy ChequeGLService is disabled'), isTrue);
    expect(endorsement.contains('ChequeAccountingService.endorseToSupplier'),
        isTrue);
  });

  test('P0.008 lifecycle service uses explicit status accounting', () {
    final source = readSource(
      'lib/features/cheques/services/cheque_accounting_service.dart',
    );

    expect(source.contains("source: 'CHEQUE_STATUS'"), isTrue);
    expect(source.contains("source: 'CHEQUE_ENDORSE'"), isTrue);
    expect(source.contains('ChequeStatus.deposited'), isTrue);
    expect(source.contains('ChequeStatus.collected'), isTrue);
    expect(source.contains('ChequeStatus.returned'), isTrue);
    expect(source.contains('ChequeStatus.cancelled'), isTrue);
  });
}
