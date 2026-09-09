import 'package:yalla_accounts/core/services/backup_service.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

/// Credentials grant only a short-lived export session, never application access.
class OwnerDataExportService {
  OwnerDataExportService(
      {UserService? users,
      AuthSessionService? sessions,
      Future<EncryptedBackupResult> Function(String)? create,
      Future<void> Function(String)? share})
      : _users = users ?? UserService(),
        _sessions = sessions ?? AuthSessionService(),
        _create = create ??
            ((password) => BackupService.createEncryptedBackup(
                password: password, kind: 'owner_recovery')),
        _share = share ?? ((path) => BackupService.shareEncryptedBackup(path));
  final UserService _users;
  final AuthSessionService _sessions;
  final Future<EncryptedBackupResult> Function(String) _create;
  final Future<void> Function(String) _share;

  Future<bool> export(
      {required String username,
      required String password,
      required String backupPassword}) async {
    if (backupPassword.length < 10) {
      throw StateError('Backup password too short.');
    }
    final user = await _users.authenticateUser(username.trim(), password);
    if (user == null || !user.isOwner || user.status != 'active') {
      throw StateError('Owner authentication required.');
    }
    try {
      await _sessions.createRecoverySession(user);
      final backup = await _create(backupPassword);
      try {
        await _share(backup.path);
        return true;
      } catch (_) {
        // Creation succeeded; a dismissed/failed share does not erase the copy.
        return false;
      }
    } finally {
      await _sessions.logout();
    }
  }
}
