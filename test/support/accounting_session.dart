import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';

Future<AuthSessionService> startAccountingSession(
    Database db, String id) async {
  final user = AppUser(
      id: id,
      name: id,
      email: '',
      role: 'owner',
      status: 'active',
      createdAt: DateTime.now());
  await db.insert('users', {
    'id': id,
    'name': id,
    'password': 'test-only',
    'role': 'owner',
    'is_owner': 1,
    'status': 'active',
    'created_at': user.createdAt.toIso8601String()
  });
  final session = AuthSessionService(databaseProvider: () async => db);
  await session.createSession(user);
  return session;
}
