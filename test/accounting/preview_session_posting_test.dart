import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/widgets/authenticated_route_gate.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/services/posting_engine.dart';
import '../support/accounting_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'financial writes follow UI preview user, account switch and logout',
      (tester) async {
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues(
          {'yalla_auth_session_user_v2': 'stale-user'});
      expect(await CurrentUserContext.userId(), isNull);
      final directory =
          await Directory.systemTemp.createTemp('session_posting_');
      final db = await DatabaseMigration.initDatabase(
          pathOverride: '${directory.path}/test.db');
      final session = await startAccountingSession(db, 'current-accountant');
      try {
        await session.loadLoginPreferences();
        expect(
            (await SharedPreferences.getInstance())
                .containsKey('yalla_auth_session_user_v2'),
            isFalse);
        expect(await CurrentUserContext.userId(), 'current-accountant');
        expect((await session.restoreSession())?.id, 'current-accountant');
        final container = ProviderContainer();
        addTearDown(container.dispose);
        AppUser preview(String id) => AppUser(
            id: id,
            name: id,
            email: '',
            role: 'owner',
            isOwner: true,
            status: 'active',
            createdAt: DateTime.now());
        container.read(currentUserProvider.notifier).state =
            preview('preview-owner');
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
                home: AuthenticatedRouteGate(
                    child: Scaffold(body: Text('ready'))))));
        expect(await CurrentUserContext.userId(), isNull);
        await session.startPreviewSession(preview('preview-owner'),
            localUser: false);
        expect(await CurrentUserContext.userId(), 'preview-owner');

        final accounts = await db.query('accounts',
            where: 'code IN (?,?)', whereArgs: ['1000', '4000']);
        final cash = accounts.singleWhere((a) => a['code'] == '1000')['id'];
        final revenue = accounts.singleWhere((a) => a['code'] == '4000')['id'];
        Future<int> post(String source) => db
            .transaction((txn) => PostingEngine.postEntryOn(
                  ex: txn,
                  date: DateTime(2026, 9, 8),
                  source: source,
                  sourceId: 'regression-$source',
                  lines: [
                    {'account_id': cash, 'debit': 10.0, 'credit': 0.0},
                    {'account_id': revenue, 'debit': 0.0, 'credit': 10.0},
                  ],
                ))
            .timeout(const Duration(seconds: 5));
        // Exercise the shared posting boundary used by all reported workflows.
        for (final source in [
          'INVOICE',
          'PURCHASE',
          'VOUCHER',
          'EMPLOYEE_ADVANCE'
        ]) {
          final id = await post(source);
          final entry =
              (await db.query('gl_entries', where: 'id=?', whereArgs: [id]))
                  .single;
          expect(entry['created_by'], 'preview-owner');
        }
        container.read(currentUserProvider.notifier).state =
            preview('second-user');
        expect(await CurrentUserContext.userId(), isNull);
        await session.startPreviewSession(preview('second-user'),
            localUser: false);
        expect(await CurrentUserContext.userId(), 'second-user');
        container.read(currentUserProvider.notifier).state = null;
        expect(await CurrentUserContext.userId(), isNull);
        // The old authenticated session still exists, but UI logout wins.

        await expectLater(post('NO_SESSION'), throwsStateError);
        expect(
            await db.query('gl_entries',
                where: 'source=?', whereArgs: ['NO_SESSION']),
            isEmpty);
      } finally {
        await session.endEphemeralPreviewSession();
        await db.close();
        await directory.delete(recursive: true);
      }
    });
  });
}
