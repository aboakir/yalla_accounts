import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
// Standalone, isolated Android reliability harness; never targets customer data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair_intake_draft.dart';
import 'package:yalla_accounts/features/repairs/services/repair_intake_service.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import '../test/support/accounting_session.dart';

RepairIntakeDraft draft(String name) => RepairIntakeDraft(
    clientName: name,
    clientType: 'individual',
    vehicleNumber: name,
    vehicleType: 'Car',
    vehicleModel: '2020',
    receivedDate: DateTime(2026, 9, 9),
    odometer: 100,
    fuelLevel: 50,
    previousDamage: '',
    photoPaths: [],
    customerSignaturePath: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final package = await PackageInfo.fromPlatform();
  if (package.packageName != 'ps.yalla.accounts.reliabilitytest') {
    throw StateError(
        'Refusing to run outside the isolated reliability package');
  }
  final root = await getApplicationSupportDirectory();
  final result = File('${root.path}/reliability-result.json');
  Future<void> report(Map<String, Object?> value) async {
    await result.writeAsString(jsonEncode(value), flush: true);
    runApp(MaterialApp(
        home: Scaffold(body: SafeArea(child: Text(jsonEncode(value))))));
  }

  try {
    final commandFile = File('${root.path}/reliability-command');
    final command = await commandFile.exists()
        ? (await commandFile.readAsString()).trim()
        : 'seed';
    final db = await DBService.database;
    final state = File('${root.path}/reliability-state.json');
    if (command == 'seed') {
      if (await state.exists()) throw StateError('Already seeded');
      await startAccountingSession(db, 'probe-owner');
      await db.update('owner_bootstrap_state', {
        'status': 'COMPLETED',
        'owner_user_id': 'probe-owner',
        'completed_at': DateTime.now().toIso8601String()
      });
      final client = await ClientService.insertClient(
          Client(name: 'Persisted client', type: 'individual'));
      await RepairIntakeService.save(draft('Persisted repair'));
      await PaymentService.insertCanonicalReceipt(
          database: db,
          operationId: 'probe-receipt',
          clientId: client,
          customerName: 'Persisted client',
          method: 'cash',
          date: DateTime(2026, 9, 9),
          allocations: [],
          unallocatedAmount: 100);
      await VoucherPaymentService.insertAndPost(
          database: db,
          partyName: 'Expense',
          voucher: VoucherPayment(
              id: 'probe-payment',
              voucherType: 'PAYMENT',
              partyType: 'EXPENSE',
              amount: 20,
              currency: 'ILS',
              date: DateTime(2026, 9, 9),
              method: 'CASH'));
      final tempLogo = File('${root.path}/temporary-logo.png');
      await tempLogo.writeAsBytes(
          (await rootBundle.load('assets/logo/logo.png')).buffer.asUint8List());
      await WorkshopSettingsService.instance.saveSettings(
          WorkshopSettings.defaults().copyWith(
              workshopName: 'Persistence workshop',
              phone1: '0599000000',
              logoPath: tempLogo.path));
      await tempLogo.delete();
      final backup = await BackupService.createEncryptedBackup(
          password: 'Reliability-test-2026');
      await state.writeAsString(
          jsonEncode({'backup': backup.path, 'client': client}),
          flush: true);
      await report({'status': 'SEEDED', 'backupBytes': backup.sizeBytes});
    } else if (command == 'restore') {
      final saved = jsonDecode(await state.readAsString()) as Map;
      await AuthSessionService().createSession(AppUser.fromMap(
          (await db.query('users', where: 'id=?', whereArgs: ['probe-owner']))
              .single));
      await db.update('clients', {'name': 'Changed after backup'},
          where: 'id=?', whereArgs: [saved['client']]);
      await BackupService.restoreEncryptedFromPath(saved['backup'] as String,
          password: 'Reliability-test-2026');
      await report({'status': 'RESTORED'});
    } else if (command.startsWith('crash')) {
      await db.transaction((tx) async {
        if (command == 'crash-repair') {
          await RepairIntakeService.saveOn(tx, draft('UNCOMMITTED'));
        } else {
          await tx.update('clients', {'name': 'UNCOMMITTED'});
        }
        await report({'status': 'UNCOMMITTED_READY'});
        await Completer<void>().future;
      });
    } else {
      final ws = await WorkshopSettingsService.instance.getOrDefaults();
      final clients = await db.query('clients');
      final repairs = await db.query('repairs');
      final payments = await db.query('payments');
      final vouchers = await db.query('vouchers');
      final gl =
          await db.rawQuery('SELECT SUM(debit) d, SUM(credit) c FROM gl_lines');
      final passed = clients.any((c) => c['name'] == 'Persisted client') &&
          !clients.any((c) => c['name'] == 'UNCOMMITTED') &&
          repairs.length == 1 &&
          payments.length == 2 &&
          (await db.query('receipt_headers')).length == 1 &&
          vouchers.length == 1 &&
          ws.workshopName == 'Persistence workshop' &&
          await File(ws.logoPath!).exists() &&
          gl.single['d'] == gl.single['c'];
      await report({
        'status': passed ? 'PASS' : 'FAIL',
        'clients': clients.length,
        'repairs': repairs.length,
        'payments': payments.length,
        'vouchers': vouchers.length,
        'logoExists': await File(ws.logoPath!).exists(),
        'gl': gl
      });
    }
  } catch (error, stack) {
    await report({'status': 'ERROR', 'error': '$error', 'stack': '$stack'});
  }
}
