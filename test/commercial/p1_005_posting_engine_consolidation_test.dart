import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';

void main() {
  test('P1.005 production GL mutations are centralized', () {
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final rel = entity.path.replaceAll('\\', '/');
      final source = entity.readAsStringSync();

      final isLowLevel =
          rel.endsWith('/core/services/db/tables/accounting_tables.dart');
      final isEngine = rel.endsWith('/core/services/posting_engine.dart');

      if (!isLowLevel && !isEngine) {
        final direct = RegExp(
          r'AccountingTables\.(?:post\w+|reverseEntryGL\w*)\s*\(',
        );
        if (direct.hasMatch(source)) {
          violations.add('$rel: direct AccountingTables posting/reversal');
        }
      }

      if (!isLowLevel) {
        final rawMutation = RegExp(
          r'''\.(?:insert|update|delete)\(\s*['"]gl_(?:entries|lines)['"]'''
          r'''|DELETE\s+FROM\s+gl_(?:entries|lines)'''
          r'''|INSERT\s+INTO\s+gl_(?:entries|lines)''',
          caseSensitive: false,
          multiLine: true,
        );
        if (rawMutation.hasMatch(source)) {
          violations.add('$rel: raw GL mutation outside AccountingTables');
        }
      }

      final legacyMutation = RegExp(
        r'''\.(?:insert|update|delete)\(\s*['"]'''
        r'''(?:journal_entries|ledger_entries)['"]''',
        caseSensitive: false,
        multiLine: true,
      );
      if (legacyMutation.hasMatch(source)) {
        violations.add('$rel: legacy parallel-ledger mutation remains');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Production accounting bypasses remain:\n${violations.join('\n')}',
    );
  });

  test('P1.005 DBService delegates GL mutations to PostingEngine', () {
    final source =
        File('lib/core/services/db/db_service.dart').readAsStringSync();

    for (final marker in [
      'PostingEngine.postEntry(',
      'PostingEngine.postEntryOn(',
      'PostingEngine.postInvoice(',
      'PostingEngine.postInvoiceOn(',
      'PostingEngine.postInvoiceFromId(',
      'PostingEngine.reverseEntry(',
      'PostingEngine.reverseEntryOn(',
    ]) {
      expect(source.contains(marker), isTrue, reason: marker);
    }

    expect(
      RegExp(
        r'AccountingTables\.(?:post\w+|reverseEntryGL\w*)\s*\(',
      ).hasMatch(source),
      isFalse,
    );
  });

  test('P1.005 repair receipt screens use one canonical payment path', () {
    final receive = File(
      'lib/features/repairs/screens/recieve_payment_screen.dart',
    ).readAsStringSync();
    final add = File(
      'lib/features/repairs/screens/add_payment_screen.dart',
    ).readAsStringSync();

    for (final source in [receive, add]) {
      expect(source.contains("insert('journal_entries'"), isFalse);
      expect(source.contains('JournalService.instance'), isFalse);
      expect(
        source.contains('AccountsReceivableService.instance.recordPayment'),
        isTrue,
      );
    }

    expect(receive.contains('ChequeGLService.postCheque'), isFalse);
  });

  test('P1.005 Arabic and English cheque aliases are recognized', () {
    expect(ChequeAccountingService.isChequeMethod('CHEQUE'), isTrue);
    expect(ChequeAccountingService.isChequeMethod('check'), isTrue);
    expect(ChequeAccountingService.isChequeMethod('شيك'), isTrue);
    expect(ChequeAccountingService.isChequeMethod('شيكات'), isTrue);
    expect(ChequeAccountingService.isChequeMethod('نقدًا'), isFalse);
  });

  test('P1.005 posted voucher destructive GL delete is removed', () {
    final source = File(
      'lib/features/vouchers/screens/payment_vouchers_list_screen.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        r'DELETE\s+FROM\s+gl_entries',
        caseSensitive: false,
      ).hasMatch(source),
      isFalse,
    );
    expect(
      source.contains("getGlEntryIdBySource('VOUCHER', voucherId)"),
      isTrue,
    );
  });
}
