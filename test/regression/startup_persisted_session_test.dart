import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/startup/startup_screen.dart';
import 'package:yalla_accounts/features/auth/widgets/authenticated_route_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final role in ['Owner', 'Employee', 'expired', 'inactive', 'revoked']) {
    testWidgets('cold startup restores real $role; logout protects routes',
        (tester) async {
      await tester.runAsync(() async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        await db.execute(
            'CREATE TABLE users(id TEXT, name TEXT, role TEXT, status TEXT)');
        await db.execute(
            'CREATE TABLE auth_sessions(user_id TEXT, token_hash TEXT, expires_at TEXT, last_seen_at TEXT, revoked_at TEXT)');
        await db.insert('users', {
          'id': 'real',
          'name': 'Workshop user',
          'role': role == 'Employee' ? 'Employee' : 'Owner',
          'status': role == 'inactive' ? 'inactive' : 'active'
        });
        const token = 'fixture-secure-session';
        await db.insert('auth_sessions', {
          'user_id': 'real',
          'token_hash': sha256.convert(utf8.encode(token)).toString(),
          'revoked_at':
              role == 'revoked' ? DateTime.now().toIso8601String() : null,
          'expires_at': DateTime.now()
              .toUtc()
              .add(Duration(days: role == 'expired' ? -1 : 1))
              .toIso8601String()
        });
        SharedPreferences.setMockInitialValues(
            {'yalla_auth_keep_signed_in_v1': true});
        FlutterSecureStorage.setMockInitialValues({
          'yalla_auth_session_token_v3': token,
          'yalla_auth_session_user_v3': 'real'
        });
        final session = AuthSessionService(databaseProvider: () async => db);
        final container = ProviderContainer(overrides: [
          authSessionServiceProvider.overrideWithValue(session),
        ]);
        try {
          await tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: MaterialApp(home: const StartupScreen(), routes: {
                AppRoutes.login: (_) => const Scaffold(body: Text('LOGIN')),
                AppRoutes.dashboard: (_) => const AuthenticatedRouteGate(
                    ownerOnly: true, child: Scaffold(body: Text('OWNER'))),
                AppRoutes.repairsDashboard: (_) => const AuthenticatedRouteGate(
                    child: Scaffold(body: Text('USER'))),
              })));
          for (var i = 0;
              i < 50 && container.read(currentUserProvider) == null;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await tester.pumpAndSettle();
          expect(find.text('LOGIN'), findsOneWidget);
          expect(container.read(currentUserProvider), isNull);
          final restored = await session.restoreSession();
          expect(restored?.id,
              ['Owner', 'Employee'].contains(role) ? 'real' : null);
          await session.logout();
          expect(await session.restoreSession(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          await db.close();
          AuthorizationGuard.disableInteractiveEnforcement();
        }
      });
    });
  }
}
