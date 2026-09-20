import 'package:yalla_accounts/features/auth/models/app_user.dart';

/// Special owner-only build mode.
///
/// Enabled only with:
/// --dart-define=YALLA_OWNER_LOCAL_FULL_ACCESS=true
///
/// Commercial/customer builds keep this disabled by default.
class OwnerLocalAccess {
  OwnerLocalAccess._();

  static const bool enabled = bool.fromEnvironment(
    'YALLA_OWNER_LOCAL_FULL_ACCESS',
    defaultValue: false,
  );

  static AppUser get user => AppUser(
        id: 'owner-local-full-access',
        name: 'المالك',
        email: 'owner@local.yallah',
        role: 'owner',
        status: 'active',
        createdAt: DateTime.utc(2026, 1, 1),
        organizationId: 'owner-local',
        identityAccountId: 'owner-local',
        isOwner: true,
        mustChangePassword: false,
      );
}
