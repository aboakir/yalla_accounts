import 'package:yalla_accounts/core/commercial_backend/commercial_backend_environment.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/entitlements/commercial_entitlement_policy.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';

typedef CommercialAccessDatabaseProvider = Future<Database> Function();

final commercialAccessGateServiceProvider =
    Provider<CommercialAccessGateService>(
  (ref) => CommercialAccessGateService(),
);

class CommercialAccessDecision {
  const CommercialAccessDecision._({
    required this.allowed,
    required this.readOnly,
    required this.requiresActivation,
    required this.code,
    required this.message,
    this.license,
  });

  final bool allowed;
  final bool readOnly;
  final bool requiresActivation;
  final String code;
  final String message;
  final VerifiedLicense? license;

  const CommercialAccessDecision.allow({
    required bool readOnly,
    required String code,
    required String message,
    VerifiedLicense? license,
  }) : this._(
          allowed: true,
          readOnly: readOnly,
          requiresActivation: false,
          code: code,
          message: message,
          license: license,
        );

  const CommercialAccessDecision.deny({
    required String code,
    required String message,
    bool requiresActivation = false,
  }) : this._(
          allowed: false,
          readOnly: false,
          requiresActivation: requiresActivation,
          code: code,
          message: message,
        );
}

/// Stage 02 commercial identity-chain gate.
///
/// This gate deliberately ignores legacy per-user trial/payment fields and
/// local subscription rows. Protected access is derived only from the current
/// authenticated local user plus the canonical organization/RBAC tables and a
/// cryptographically authentic license bound to this device + installation.
///
/// Chain enforced:
/// User -> Organization -> Role -> Subscription -> License -> Device -> Installation.
class CommercialAccessGateService {
  CommercialAccessGateService({
    CommercialAccessDatabaseProvider? databaseProvider,
    ActivationStateRepository? activationStateRepository,
  })  : _databaseProvider = databaseProvider ?? (() => DBService.database),
        _activationStateRepository =
            activationStateRepository ?? ActivationStateRepository();

  final CommercialAccessDatabaseProvider _databaseProvider;
  final ActivationStateRepository _activationStateRepository;

  Future<CommercialAccessDecision> evaluate(AppUser sessionUser) async {
    if (sessionUser.status != 'active') {
      return const CommercialAccessDecision.deny(
        code: 'USER_DISABLED',
        message: 'حساب المستخدم غير فعال.',
      );
    }

    final db = await _databaseProvider();
    final userRows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [sessionUser.id],
      limit: 2,
    );
    if (userRows.length != 1) {
      return const CommercialAccessDecision.deny(
        code: 'USER_NOT_CANONICAL',
        message: 'تعذر إثبات حساب المستخدم داخل المنشأة الحالية.',
      );
    }

    final canonicalUser = AppUser.fromMap(userRows.single);
    if (canonicalUser.status != 'active') {
      return const CommercialAccessDecision.deny(
        code: 'USER_DISABLED',
        message: 'حساب المستخدم غير فعال.',
      );
    }

    if (canonicalUser.role != sessionUser.role ||
        canonicalUser.organizationId != sessionUser.organizationId ||
        canonicalUser.identityAccountId != sessionUser.identityAccountId ||
        canonicalUser.isOwner != sessionUser.isOwner) {
      return const CommercialAccessDecision.deny(
        code: 'SESSION_IDENTITY_STALE',
        message: 'تغيرت صلاحيات الحساب. سجّل الدخول من جديد.',
      );
    }

    final accountId = canonicalUser.identityAccountId;
    final accounts = accountId == null
        ? <Map<String, Object?>>[]
        : await db.query('identity_accounts',
            columns: ['id'], where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (accounts.isEmpty) {
      return const CommercialAccessDecision.deny(
        code: 'PERSON_IDENTITY_MISSING',
        message: 'تعذر إثبات هوية الحساب. أعد فتح التطبيق ثم سجّل الدخول.',
      );
    }

    final organizationId = canonicalUser.organizationId?.trim() ?? '';
    if (organizationId.isEmpty) {
      return const CommercialAccessDecision.deny(
        code: 'ORGANIZATION_MISSING',
        message: 'الحساب غير مرتبط بمنشأة مرخصة.',
      );
    }

    final identityRows = await db.query(
      'organization_identity',
      columns: ['organization_id'],
      where: 'singleton_id = 1',
      limit: 2,
    );
    if (identityRows.length != 1 ||
        identityRows.single['organization_id']?.toString() != organizationId) {
      return const CommercialAccessDecision.deny(
        code: 'ORGANIZATION_MISMATCH',
        message: 'الحساب لا ينتمي إلى المنشأة المرتبطة بهذا التثبيت.',
      );
    }

    final organizationRows = await db.query(
      'organizations',
      columns: ['id', 'status'],
      where: 'id = ?',
      whereArgs: [organizationId],
      limit: 2,
    );
    if (organizationRows.length != 1) {
      return const CommercialAccessDecision.deny(
        code: 'ORGANIZATION_NOT_FOUND',
        message: 'المنشأة المرتبطة بالحساب غير موجودة.',
      );
    }
    final organizationStatus =
        organizationRows.single['status']?.toString().toLowerCase() ?? '';
    if (organizationStatus != 'active') {
      return const CommercialAccessDecision.deny(
        code: 'ORGANIZATION_SUSPENDED',
        message: 'المنشأة موقوفة حاليًا.',
      );
    }

    final roleRows = await db.query(
      'auth_roles',
      columns: ['role_key'],
      where: 'role_key = ?',
      whereArgs: [canonicalUser.role],
      limit: 2,
    );
    if (roleRows.length != 1) {
      return const CommercialAccessDecision.deny(
        code: 'ROLE_INVALID',
        message: 'دور المستخدم غير معتمد.',
      );
    }

    final rolePermissionRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM auth_role_permissions
      WHERE role_key = ?
      ''',
      [canonicalUser.role],
    );
    final permissionCount = rolePermissionRows.isEmpty
        ? 0
        : ((rolePermissionRows.first['c'] as num?)?.toInt() ?? 0);
    if (permissionCount == 0) {
      return const CommercialAccessDecision.deny(
        code: 'ROLE_WITHOUT_PERMISSIONS',
        message: 'الدور الحالي لا يملك سياسة صلاحيات معتمدة.',
      );
    }

    final ownerRole = canonicalUser.role == 'owner';
    if (ownerRole != canonicalUser.isOwner) {
      return const CommercialAccessDecision.deny(
        code: 'OWNER_ROLE_MISMATCH',
        message: 'رابط المالك والصلاحيات غير متطابق.',
      );
    }

    final bootstrapRows = await db.query(
      'owner_bootstrap_state',
      columns: ['organization_id', 'status', 'owner_user_id'],
      where: 'singleton_id = 1',
      limit: 2,
    );
    if (bootstrapRows.length != 1 ||
        bootstrapRows.single['organization_id']?.toString() != organizationId ||
        bootstrapRows.single['status']?.toString() != 'COMPLETED') {
      return const CommercialAccessDecision.deny(
        code: 'OWNER_BOOTSTRAP_INCOMPLETE',
        message: 'إعداد المالك الأول للمنشأة غير مكتمل.',
      );
    }
    if (canonicalUser.isOwner &&
        bootstrapRows.single['owner_user_id']?.toString() != canonicalUser.id) {
      return const CommercialAccessDecision.deny(
        code: 'OWNER_LINK_MISMATCH',
        message: 'حساب المالك لا يطابق مالك المنشأة المعتمد.',
      );
    }

    if (CommercialBackendEnvironment.enabled) {
      final runtimeOrganization =
          CommercialBackendRuntimeAccess.organizationId?.trim() ?? '';
      final runtimeSubscription =
          CommercialBackendRuntimeAccess.subscriptionId?.trim() ?? '';
      if (!CommercialBackendRuntimeAccess.canRead) {
        return const CommercialAccessDecision.deny(
          code: 'PHP_ACCESS_BLOCKED',
          message: 'الحساب أو الاشتراك غير متاح حاليًا.',
          requiresActivation: true,
        );
      }
      if (runtimeOrganization.isEmpty ||
          runtimeOrganization != organizationId) {
        return const CommercialAccessDecision.deny(
          code: 'PHP_ORGANIZATION_MISMATCH',
          message: 'ترخيص الخادم لا يطابق المنشأة الحالية.',
          requiresActivation: true,
        );
      }
      if (runtimeSubscription.isEmpty) {
        return const CommercialAccessDecision.deny(
          code: 'PHP_SUBSCRIPTION_MISSING',
          message: 'لا يوجد اشتراك خادم معتمد لهذه المنشأة.',
          requiresActivation: true,
        );
      }
      final readOnly = !CommercialBackendRuntimeAccess.canWrite;
      return CommercialAccessDecision.allow(
        readOnly: readOnly,
        code: readOnly ? 'PHP_READ_ONLY' : 'PHP_WRITABLE',
        message: readOnly
            ? 'الحساب مرتبط بالخادم ويعمل حاليًا بوضع القراءة فقط.'
            : 'تم التحقق من المستخدم والمنشأة والترخيص عبر PHP Backend.',
      );
    }

    final license = await _activationStateRepository
        .loadAuthenticLicenseForCurrentInstallation(allowExpired: true);
    if (license == null) {
      return const CommercialAccessDecision.deny(
        code: 'ACTIVATION_REQUIRED',
        message: 'يلزم تفعيل موثّق لهذا الجهاز قبل الدخول.',
        requiresActivation: true,
      );
    }

    if (license.organizationId != organizationId) {
      return const CommercialAccessDecision.deny(
        code: 'LICENSE_ORGANIZATION_MISMATCH',
        message: 'الترخيص لا يخص المنشأة المسجّل عليها المستخدم.',
      );
    }
    if (license.subscriptionId.trim().isEmpty) {
      return const CommercialAccessDecision.deny(
        code: 'SUBSCRIPTION_MISSING',
        message: 'الترخيص الموقّع لا يحتوي على اشتراك معتمد.',
      );
    }
    if (license.licenseId.trim().isEmpty ||
        license.deviceId.trim().isEmpty ||
        license.installationId.trim().isEmpty) {
      return const CommercialAccessDecision.deny(
        code: 'LICENSE_BINDING_INCOMPLETE',
        message: 'ربط الترخيص بالجهاز والتثبيت غير مكتمل.',
      );
    }

    final entitlementDecision = CommercialEntitlementPolicy.evaluate(license);
    if (!entitlementDecision.valid) {
      return CommercialAccessDecision.deny(
        code: entitlementDecision.code,
        message: 'بيانات صلاحيات الاشتراك الموقّعة غير صالحة.',
      );
    }

    final status =
        SubscriptionAccessPolicy.normalize(license.operationalStatus);
    if (!SubscriptionAccessPolicy.statuses.contains(status)) {
      return const CommercialAccessDecision.deny(
          code: 'LICENSE_STATUS_INVALID',
          message: 'حالة الترخيص الموقّعة غير معتمدة.');
    }
    final readOnly =
        SubscriptionAccessPolicy.mode(license, DateTime.now().toUtc()) !=
            LicenseRuntimeMode.writable;
    return CommercialAccessDecision.allow(
      readOnly: readOnly,
      code: readOnly ? 'BOUND_READ_ONLY' : 'BOUND_WRITABLE',
      message: readOnly
          ? 'الحساب مرتبط تجاريًا، لكن حالة الترخيص الحالية للقراءة فقط.'
          : 'تم التحقق من سلسلة المستخدم والمنشأة والترخيص والجهاز.',
      license: license,
    );
  }
}
