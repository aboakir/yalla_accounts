import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/audit_trail_service.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'cloud_auth_config.dart';
import 'supabase_identity_provider.dart';

final cloudConfigProvider = Provider((ref) => CloudAuthConfig.environment());
final supabaseIdentityProvider = Provider((ref) {
  final provider = SupabaseIdentityProvider(ref.watch(cloudConfigProvider));
  ref.onDispose(provider.dispose);
  return provider;
});
final cloudAuthServiceProvider = Provider((ref) => CloudAuthService(
    identityProvider: ref.watch(supabaseIdentityProvider),
    database: () => DBService.database,
    authenticateLocal: ref.read(userServiceProvider).authenticateUser,
    accessAllowed: (user) async =>
        (await ref.read(commercialAccessGateServiceProvider).evaluate(user))
            .allowed,
    createSession: (user) =>
        ref.read(authSessionServiceProvider).createSession(user)));

class CloudAccountNotLinked implements Exception {}

class CloudAuthService {
  CloudAuthService(
      {required this.identityProvider,
      required this.database,
      required this.authenticateLocal,
      required this.accessAllowed,
      required this.createSession});
  final CloudIdentityProvider identityProvider;
  final Future<Database> Function() database;
  final Future<AppUser?> Function(String, String) authenticateLocal;
  final Future<bool> Function(AppUser) accessAllowed;
  final Future<void> Function(AppUser) createSession;

  Future<AppUser> _canonical(DatabaseExecutor db, String userId) async {
    final rows = await db.rawQuery('''SELECT u.* FROM users u
      JOIN identity_accounts a ON a.id = u.identity_account_id
      JOIN organization_identity o ON o.organization_id = u.organization_id
      WHERE u.id = ? AND u.status = 'active' AND o.singleton_id = 1''',
        [userId]);
    if (rows.length != 1) throw StateError('Local identity is unavailable');
    return AppUser.fromMap(rows.single);
  }

  Future<void> link(AppUser expectedUser, String localPassword) async {
    final authenticated =
        await authenticateLocal(expectedUser.name, localPassword);
    if (authenticated == null ||
        authenticated.id != expectedUser.id ||
        authenticated.identityAccountId != expectedUser.identityAccountId ||
        authenticated.organizationId != expectedUser.organizationId ||
        authenticated.mustChangePassword ||
        !await accessAllowed(authenticated)) {
      throw StateError('Local credential verification failed');
    }
    final cloud = await identityProvider.verifyIdentity();
    final db = await database();
    await db.transaction((txn) async {
      final current = await _canonical(txn, authenticated.id);
      if (current.role != authenticated.role ||
          current.identityAccountId != authenticated.identityAccountId ||
          current.organizationId != authenticated.organizationId) {
        throw StateError('Local identity changed');
      }
      final links = await txn.query('cloud_identity_links',
          where: 'issuer = ? AND subject = ?',
          whereArgs: [cloud.issuer, cloud.subject]);
      if (links.isNotEmpty) {
        if (links.single['user_id'] == current.id &&
            links.single['identity_account_id'] == current.identityAccountId &&
            links.single['organization_id'] == current.organizationId) {
          return;
        }
        throw StateError(
            'Cloud identity already belongs to another local account');
      }
      await txn.insert('cloud_identity_links', {
        'issuer': cloud.issuer,
        'subject': cloud.subject,
        'identity_account_id': current.identityAccountId,
        'organization_id': current.organizationId,
        'user_id': current.id,
        'linked_at': DateTime.now().toUtc().toIso8601String()
      });
      await AuditTrailService.log(
          executor: txn,
          actorUserId: current.id,
          actorRole: current.role,
          action: 'CLOUD_IDENTITY_LINKED',
          entityType: 'identity_account',
          entityId: current.identityAccountId,
          after: {
            'issuer': cloud.issuer,
            'subject': cloud.subject,
            'organization_id': current.organizationId
          });
    });
  }

  Future<AppUser> enterLinkedWorkshop({bool createLocalSession = true}) async {
    final cloud = await identityProvider.verifyIdentity();
    final db = await database();
    final links = await db.query('cloud_identity_links',
        where: 'issuer = ? AND subject = ?',
        whereArgs: [cloud.issuer, cloud.subject]);
    if (links.length != 1) throw CloudAccountNotLinked();
    final link = links.single;
    final user = await _canonical(db, link['user_id'] as String);
    if (user.mustChangePassword ||
        user.identityAccountId != link['identity_account_id'] ||
        user.organizationId != link['organization_id'] ||
        !await accessAllowed(user)) {
      throw StateError('Workshop access denied');
    }
    // The gate updates the same Stage46 runtime read-only/write policy.
    if (createLocalSession) {
      await createSession(user);
    }
    return user;
  }
}
