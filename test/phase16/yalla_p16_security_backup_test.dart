import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db/tables/p16_security_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P16 official authorization matrix', () {
    test('official roles are present and technician has no financial grants',
        () {
      expect(
          RoleKeys.all,
          containsAll(<String>{
            RoleKeys.owner,
            RoleKeys.manager,
            RoleKeys.accountant,
            RoleKeys.employee,
            RoleKeys.technician,
          }));
      expect(RoleKeys.assignable, <String>{
        RoleKeys.admin,
        RoleKeys.accountant,
        RoleKeys.staff,
        RoleKeys.viewer,
      });
      expect(
        AuthorizationPolicy.forRole(RoleKeys.owner),
        containsAll(PermissionKeys.all),
      );
      final tech = AuthorizationPolicy.forRole(RoleKeys.technician);
      expect(tech, contains(PermissionKeys.repairWorkflow));
      expect(tech, isNot(contains(PermissionKeys.receiptCreate)));
      expect(tech, isNot(contains(PermissionKeys.glView)));
      expect(tech, isNot(contains(PermissionKeys.backupRestore)));
    });

    test('manager/accountant cannot restore or manage owner roles', () {
      final manager = AuthorizationPolicy.forRole(RoleKeys.manager);
      final accountant = AuthorizationPolicy.forRole(RoleKeys.accountant);
      expect(manager, contains(PermissionKeys.repairClose));
      expect(manager, isNot(contains(PermissionKeys.backupRestore)));
      expect(manager, isNot(contains(PermissionKeys.roleManage)));
      expect(accountant, contains(PermissionKeys.receiptReverse));
      expect(accountant, contains(PermissionKeys.glView));
      expect(accountant, isNot(contains(PermissionKeys.backupRestore)));
      expect(accountant, isNot(contains(PermissionKeys.roleManage)));
    });
  });

  group('P16 headless audit attribution', () {
    test('missing SharedPreferences plugin does not break business services',
        () async {
      expect(await CurrentUserContext.userId(), isNull);
    });
  });

  group('P16 append-only audit and backup guardian tables', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await P16SecurityTables.ensure(db);
    });

    tearDown(() async => db.close());

    test('audit event cannot be updated or deleted', () async {
      final id = await db.insert('app_audit_events', {
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'action': 'TEST_ACTION',
        'entity_type': 'TEST',
      });
      expect(
        () => db.update(
          'app_audit_events',
          {'action': 'TAMPERED'},
          where: 'id=?',
          whereArgs: [id],
        ),
        throwsA(anything),
      );
      expect(
        () => db.delete(
          'app_audit_events',
          where: 'id=?',
          whereArgs: [id],
        ),
        throwsA(anything),
      );
    });

    test('weekly guardian is seeded and enabled', () async {
      final rows = await db.query('backup_guardian_settings');
      expect(rows, hasLength(1));
      expect(rows.single['weekly_enabled'], 1);
      expect(rows.single['next_due_at'], isNotNull);
    });
  });

  group('P16 source contracts', () {
    String read(String path) => File(path).readAsStringSync();

    test('full encrypted backup contains DB, media manifest and safety restore',
        () {
      final source = read('lib/core/services/backup_service.dart');
      expect(source, contains("'includes_media': true"));
      expect(source, contains("'manifest.json'"));
      expect(source, contains(".yallabackup"));
      expect(source, contains("kind: 'pre_restore'"));
      expect(source, contains('journal.rollback()'));
      expect(source, contains('journal.commit()'));
      expect(source, contains('extractFileToDisk('));
      expect(source, contains('fullChecksumValidation: true'));
      expect(source, contains("const int weeklyRetention = 4"));
      expect(source, contains("excludeTopLevel: const {'backups'}"));
    });

    test('weekly cycle requires external handoff before next seven-day cycle',
        () {
      final guardian = read(
        'lib/features/settings/services/weekly_backup_guardian_service.dart',
      );
      final backup = read('lib/core/services/backup_service.dart');
      expect(guardian,
          contains("'snoozed_until': utc.add(const Duration(days: 1))"));
      expect(backup, contains("'last_external_handoff_at': now"));
      expect(backup, contains("'next_due_at': nextDue"));
      expect(backup, contains('Drive/OneDrive/iCloud'));
    });

    test('sensitive services are protected by service-level guards', () {
      final payment = read(
        'lib/features/finance/payments/services/payment_service.dart',
      );
      final workflow = read(
        'lib/features/repairs/services/repair_workflow_service.dart',
      );
      final purchase = read(
        'lib/features/finance/purchases/services/purchase_invoice_service.dart',
      );
      final costing = read(
        'lib/features/repairs/services/repair_cost_service.dart',
      );
      final cheque = read(
        'lib/features/cheques/services/cheque_accounting_service.dart',
      );
      expect(payment, contains('PermissionKeys.receiptReverse'));
      expect(workflow, contains('PermissionKeys.repairClose'));
      expect(workflow, contains('PermissionKeys.repairReopen'));
      expect(purchase, contains('PermissionKeys.purchaseManage'));
      expect(costing, contains('PermissionKeys.repairCostManage'));
      expect(cheque, contains('PermissionKeys.chequeManage'));
    });

    test('production workshop settings no longer exposes destructive DB reset',
        () {
      final source = read(
        'lib/features/settings/screens/workshop_settings_screen.dart',
      );
      expect(source, isNot(contains('DatabaseMigration.resetDatabase')));
      expect(source, isNot(contains("const Text('Reset DB'")));
    });

    test('Windows migration explicitly avoids blind merge', () {
      final source = read(
        'lib/features/settings/services/windows_migration_service.dart',
      );
      expect(source, contains('no blind merge'));
      expect(source, contains('BackupService.validateDatabaseCandidate'));
      expect(source, contains('safety_backup_path'));
      expect(source, contains("kind: 'pre_windows_folder_import'"));
      expect(source, contains('BackupService.restoreEncryptedFromPath'));
    });

    test('legacy roles stay readable but are not assignable to new users', () {
      expect(RoleKeys.isKnown(RoleKeys.cashier), isTrue);
      expect(RoleKeys.isAssignable(RoleKeys.cashier), isFalse);
      expect(RoleKeys.isAssignable(RoleKeys.readOnly), isFalse);
      expect(RoleKeys.isAssignable(RoleKeys.employee), isFalse);

      final addUser = read('lib/features/auth/widgets/add_user_dialog.dart');
      expect(addUser, contains('String _role = RoleKeys.staff;'));
    });

    test('fresh login enables service-level authorization immediately', () {
      final login = read('lib/features/auth/screens/login_screen.dart');
      expect(login,
          contains('AuthorizationGuard.enableInteractiveEnforcement();'));
    });

    test('current v69 post-init refreshes authorization and P16 tables', () {
      final migration = read('lib/core/services/db/database_migration.dart');
      final postInitMarker = migration.indexOf(
          '// SEC.008 - canonical local authorization catalog and role guards.');
      expect(postInitMarker, greaterThanOrEqualTo(0));
      final tail = migration.substring(postInitMarker);
      expect(tail, contains('await UserAuthorizationTables.ensure(db);'));
      expect(tail, contains('await P16SecurityTables.ensure(db);'));
    });

    test('dismissed external share cannot complete the weekly cycle', () {
      final backup = read('lib/core/services/backup_service.dart');
      final dismissed = backup.indexOf('ShareResultStatus.dismissed');
      final external = backup.indexOf("'last_external_handoff_at': now");
      expect(dismissed, greaterThanOrEqualTo(0));
      expect(external, greaterThan(dismissed));
      expect(
        backup.substring(dismissed, external),
        contains('throw StateError'),
      );
      expect(backup, contains('SHARE_SHEET_UNVERIFIED'));
    });

    test(
        'legacy backup APIs are service-gated and invoice posting needs post permission',
        () {
      final backup = read('lib/core/services/backup_service.dart');
      final invoice =
          read('lib/features/finance/invoices/services/invoice_service.dart');
      expect(backup,
          contains('AuthorizationGuard.require(PermissionKeys.backupCreate)'));
      expect(backup,
          contains('AuthorizationGuard.require(PermissionKeys.backupExport)'));
      expect(backup,
          contains('AuthorizationGuard.require(PermissionKeys.backupRestore)'));
      expect(
          invoice,
          contains(
              'postToGL ? PermissionKeys.invoicePost : PermissionKeys.invoiceCreate'));
    });

    test('new-device restore rewrites media and JSON attachment paths', () {
      final backup = read('lib/core/services/backup_service.dart');
      expect(backup, contains('_rewriteRestoredPaths'));
      expect(backup, contains("'payments', 'id', 'attachments'"));
      expect(backup, contains("'vouchers', 'id', 'attachments'"));
      expect(
          backup,
          contains(
              'decoded.map((value) => rewrite(value.toString())).toList()'));
    });
  });
}
