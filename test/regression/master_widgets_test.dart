import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/features/clients/widgets/add_client_dialog.dart';
import 'package:yalla_accounts/features/clients/widgets/edit_client_dialog.dart';
import 'package:yalla_accounts/features/suppliers/models/supplier.dart';
import 'package:yalla_accounts/features/suppliers/services/supplier_service.dart';
import 'package:yalla_accounts/features/suppliers/screens/supplier_form_screen.dart';
import 'workflow_widgets_test.dart' show app, flush, field, tap;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final supplier in [false, true]) {
    testWidgets(
        '${supplier ? 'supplier' : 'customer'} form shows duplicate warning and saves correction',
        (t) async {
      t.view.physicalSize = const Size(430, 932);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      late Directory temp;
      late Database db;
      await t.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        temp = await Directory.systemTemp.createTemp('master_forms_');
        db = await DatabaseMigration.initDatabase(
            pathOverride: '${temp.path}/test.db');
        DatabaseMigration.useDatabaseForTesting(db);
        if (supplier) {
          await SupplierService.insertSupplier(
              Supplier(id: '', pid: '', name: 'Existing'));
        } else {
          await ClientService.insertClient(
              Client(name: 'Existing', type: 'أفراد'));
        }
      });
      try {
        await t.pumpWidget(app(Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => supplier
                                ? const SupplierFormScreen()
                                : const Scaffold(body: AddClientDialog()))),
                    child: const Text('open'))))));
        await tap(t, find.text('open'));
        final name = field(supplier ? 'اسم المورد' : 'اسم العميل');
        await t.enterText(name, 'Existing');
        await tap(t, find.text(supplier ? 'إضافة المورد' : 'حفظ'));
        expect(find.textContaining('موجود مسبقًا'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 5));
        await flush(t);
        await t.enterText(name, 'New Person');
        await tap(t, find.text(supplier ? 'إضافة المورد' : 'حفظ'));
        for (var i = 0; i < 8; i++) {
          await flush(t);
        }
        final names = await t.runAsync(() async =>
            (await db.query(supplier ? 'suppliers' : 'clients'))
                .map((r) => r['name'])
                .toList());
        expect(names!.where((n) => n == 'New Person'), hasLength(1));
        expect(t.takeException(), isNull);
        if (!supplier) {
          final client = await t.runAsync(() async =>
              (await ClientService.search(query: 'New Person')).single);
          await t.pumpWidget(app(Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => EditClientDialog(client: client!)),
                      child: const Text('edit'))))));
          await tap(t, find.text('edit'));
          await t.enterText(field('اسم العميل'), ' new person ');
          await t.enterText(field('رقم الهاتف (اختياري)'), '0599123456');
          await tap(t, find.text('حفظ التعديل'));
          for (var i = 0; i < 8; i++) {
            await flush(t);
          }
          expect(find.byType(EditClientDialog), findsNothing);
          final updated =
              await t.runAsync(() => ClientService.getClientById(client!.id!));
          expect(updated!.phone, '0599123456');
        }
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await flush(t);
        await t.runAsync(() async {
          DatabaseMigration.useDatabaseForTesting(null);
          await db.close();
          await temp.delete(recursive: true);
        });
      }
    });
  }
}
