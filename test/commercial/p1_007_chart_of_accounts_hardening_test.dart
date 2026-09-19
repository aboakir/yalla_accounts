import '../support/accounting_session.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/services/db/database_constants.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/posting_engine.dart';

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

void main() {
  test('P1.007 system-account identity trigger checks actual value changes',
      () {
    final source = File(
      'lib/core/services/db/tables/accounting_tables.dart',
    ).readAsStringSync();

    expect(
      source.contains('NEW.code IS NOT OLD.code'),
      isTrue,
    );
    expect(
      source.contains('NEW.type IS NOT OLD.type'),
      isTrue,
    );
    expect(
      source.contains(
        'NEW.normal_balance IS NOT OLD.normal_balance',
      ),
      isTrue,
    );
    expect(
      source.contains("OLD.normal_balance IS NULL"),
      isTrue,
      reason: 'Initial canonical normalization must remain allowed before GL.',
    );
  });

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('P1.007 fresh current DB COA metadata and posting policy are enforced',
      () async {
    SharedPreferences.setMockInitialValues({});

    final temp = await Directory.systemTemp.createTemp('yalla_p1_007_');
    final path = '${temp.path}${Platform.pathSeparator}fresh.db';
    final db = await DatabaseMigration.initDatabase(pathOverride: path);
    final session = await startAccountingSession(db, 'coa-test-user');

    try {
      expect(
        _int((await db.rawQuery('PRAGMA user_version')).first.values.first),
        DatabaseConstants.dbVersion,
      );

      final columns = await db.rawQuery('PRAGMA table_info(accounts)');
      final names = columns.map((r) => r['name'].toString()).toSet();
      for (final required in [
        'report_class',
        'parent_id',
        'is_postable',
        'is_system',
        'is_active',
        'is_legacy',
      ]) {
        expect(names.contains(required), isTrue, reason: 'missing $required');
      }

      Future<Map<String, Object?>> account(String code) async {
        return (await db.query(
          'accounts',
          where: 'code=?',
          whereArgs: [code],
          limit: 1,
        ))
            .single;
      }

      final arRoot = await account('1200');
      final apRoot = await account('2200');
      final advanceRoot = await account('1120');
      final payrollRoot = await account('2140');

      for (final root in [arRoot, apRoot, advanceRoot, payrollRoot]) {
        expect(_int(root['is_system']), 1);
        expect(_int(root['is_active']), 1);
        expect(_int(root['is_postable']), 0);
        expect(root['report_class'], isNotNull);
      }

      // An older direct INSERT path is normalized by the database itself.
      final clientAccountId = await db.insert('accounts', {
        'code': '1200.C999',
        'name': 'Test client',
        'type': 'ASSET',
        'normal_balance': 'DEBIT',
      });
      final clientAccount = (await db.query(
        'accounts',
        where: 'id=?',
        whereArgs: [clientAccountId],
        limit: 1,
      ))
          .single;

      expect(_int(clientAccount['parent_id']), _int(arRoot['id']));
      expect(clientAccount['report_class'], 'ASSET');
      expect(_int(clientAccount['is_system']), 1);
      expect(_int(clientAccount['is_postable']), 1);
      expect(_int(clientAccount['is_active']), 1);

      // Obsolete account families can no longer return.
      for (final code in ['1200.Elegacy', '2000.S99', '2200.SS0099']) {
        await expectLater(
          db.insert('accounts', {
            'code': code,
            'name': 'blocked',
            'type': code.startsWith('1200') ? 'ASSET' : 'LIABILITY',
          }),
          throwsA(isA<DatabaseException>()),
        );
      }

      // Header/control roots cannot receive new normal postings.
      final cash = await account('1000');
      await expectLater(
        PostingEngine.postEntryOn(
          ex: db,
          date: DateTime(2026, 8, 19),
          source: 'P1_007_BAD_ROOT',
          sourceId: 'bad-root',
          lines: [
            {
              'account_id': arRoot['id'],
              'debit': 10.0,
              'credit': 0.0,
            },
            {
              'account_id': cash['id'],
              'debit': 0.0,
              'credit': 10.0,
            },
          ],
        ),
        throwsA(isA<StateError>()),
      );

      // Normal leaf/system posting remains valid.
      final revenue = await account('4000');
      final normalEntry = await PostingEngine.postEntryOn(
        ex: db,
        date: DateTime(2026, 8, 19),
        source: 'P1_007_OK',
        sourceId: 'normal-posting',
        lines: [
          {
            'account_id': cash['id'],
            'debit': 25.0,
            'credit': 0.0,
          },
          {
            'account_id': revenue['id'],
            'debit': 0.0,
            'credit': 25.0,
          },
        ],
      );
      expect(normalEntry, greaterThan(0));

      // Account identity is immutable once it is system-managed or has GL.
      await expectLater(
        db.update(
          'accounts',
          {'type': 'EXPENSE'},
          where: 'id=?',
          whereArgs: [cash['id']],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.delete(
          'accounts',
          where: 'id=?',
          whereArgs: [apRoot['id']],
        ),
        throwsA(isA<DatabaseException>()),
      );

      // A formal reversal must still be able to use a leaf that was retired
      // after the original posting.
      final customId = await db.insert('accounts', {
        'code': '5999.TEST',
        'name': 'Temporary test expense',
        'type': 'EXPENSE',
        'normal_balance': 'DEBIT',
      });

      final customEntry = await PostingEngine.postEntryOn(
        ex: db,
        date: DateTime(2026, 8, 19),
        source: 'P1_007_RETIRE',
        sourceId: 'retire-test',
        lines: [
          {
            'account_id': customId,
            'debit': 50.0,
            'credit': 0.0,
          },
          {
            'account_id': cash['id'],
            'debit': 0.0,
            'credit': 50.0,
          },
        ],
      );

      await db.update(
        'accounts',
        {'is_active': 0, 'is_postable': 0},
        where: 'id=?',
        whereArgs: [customId],
      );

      final reversalId = await PostingEngine.reverseEntryOn(db, customEntry);
      final reversal = (await db.query(
        'gl_entries',
        where: 'id=?',
        whereArgs: [reversalId],
        limit: 1,
      ))
          .single;

      expect(_int(reversal['reversal_of']), customEntry);
    } finally {
      await session.endEphemeralPreviewSession();
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('P1.007 stale account-code writers are removed', () {
    final gl = File(
      'lib/core/services/accounting_gl.dart',
    ).readAsStringSync();
    expect(gl.contains("empAdvances = '1120'"), isTrue);
    expect(gl.contains("payrollPayable = '2140'"), isTrue);
    expect(gl.contains("openingEquity = '3100'"), isTrue);
    expect(gl.contains("salariesExpense = '5100'"), isTrue);
    expect(gl.contains("empAdvances = '1300'"), isFalse);

    final opening = File(
      'lib/features/finance/opening/opening_balances_service.dart',
    ).readAsStringSync();
    expect(opening.contains("= '3000'"), isFalse);
    expect(opening.contains('GL.openingEquity'), isTrue);

    final vouchers = File(
      'lib/features/vouchers/services/voucher_payment_service.dart',
    ).readAsStringSync();
    expect(vouchers.contains(r'final code = "1200.E$empId"'), isFalse);
    expect(vouchers.contains(r'"1120.E$empId"'), isTrue);

    final purchaseCreate = File(
      'lib/features/finance/purchases/screens/purchase_create_screen.dart',
    ).readAsStringSync();
    expect(purchaseCreate.contains(r'final code = "2200.S$pid"'), isFalse);
    expect(purchaseCreate.contains(r'final code = "2200.$pid"'), isFalse);
    expect(
      purchaseCreate.contains('SupplierService.insertOrGetSupplierId'),
      isTrue,
      reason:
          'Purchase quick-add must delegate supplier/account creation to the canonical SupplierService.',
    );

    final invoiceGl = File(
      'lib/features/finance/invoices/services/invoice_gl_service.dart',
    ).readAsStringSync();
    expect(
        invoiceGl.contains('DBService.ensureClientAccount(clientId)'), isTrue);

    final glService = File(
      'lib/features/finance/services/gl_service.dart',
    ).readAsStringSync();
    expect(glService.contains(r"'1120.E$employeeId'"), isTrue);

    final advanceService = File(
      'lib/features/finance/advances/services/advance_service.dart',
    ).readAsStringSync();
    expect(
      advanceService.contains(r"'$_accEmpAdvCode.E$employeeId'"),
      isTrue,
    );

    final salaryPayment = File(
      'lib/features/employees/services/salary_payment_database_service.dart',
    ).readAsStringSync();
    expect(
      salaryPayment.contains('Legacy salary_payments writes are disabled.'),
      isTrue,
    );

    for (final purchasePath in [
      'lib/features/finance/purchases/screens/unposted_purchases_screen.dart',
      'lib/features/finance/purchases/screens/purchases_gl_audit_screen.dart',
      'lib/features/purchases/widgets/purchase_gl_button.dart',
    ]) {
      final purchaseSource = File(purchasePath).readAsStringSync();
      expect(
        purchaseSource.contains('apId = apRootId'),
        isFalse,
        reason: '$purchasePath must fail closed instead of posting to AP root.',
      );
    }

    final accountingTables = File(
      'lib/core/services/db/tables/accounting_tables.dart',
    ).readAsStringSync();
    expect(
      accountingTables.contains(
        r"final code = '2200.S${parsed.toString().padLeft(4, '0')}'",
      ),
      isTrue,
    );
    expect(
      accountingTables.contains(
        "'suppliers',\n      columns: ['account_id']",
      ),
      isFalse,
      reason: 'Supplier table no longer owns account_id.',
    );
  });
}
