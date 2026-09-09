import 'subscription_access_policy.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/license_validation_tables.dart';

import '../activation/activation_state_repository.dart';
import '../activation/license_envelope_verifier.dart';

typedef RuntimeDatabaseProvider = Future<Database> Function();

class ReadOnlyOperationException implements Exception {
  const ReadOnlyOperationException(this.mode, this.message);

  final String mode;
  final String message;

  @override
  String toString() => 'ReadOnlyOperationException($mode): $message';
}

class LicenseRuntimeDecision {
  const LicenseRuntimeDecision({
    required this.mode,
    required this.reason,
    this.license,
  });

  final String mode;
  final String reason;
  final VerifiedLicense? license;

  bool get isReadOnly => LicenseRuntimeMode.readOnlyModes.contains(mode);
  bool get isWritable => mode == LicenseRuntimeMode.writable;
}

/// SEC.011 operational-access projection.
///
/// The stored runtime row is not a trust source. `refreshFromStoredLicense()`
/// re-verifies the signed envelope and projects its current operational status.
/// Business-table triggers consume only the resulting projection.
class LicenseRuntimeService {
  LicenseRuntimeService({
    RuntimeDatabaseProvider? databaseProvider,
    ActivationStateRepository? activationStateRepository,
  })  : _databaseProvider = databaseProvider ?? (() => DBService.database),
        _activationStateRepository =
            activationStateRepository ?? ActivationStateRepository();

  final RuntimeDatabaseProvider _databaseProvider;
  final ActivationStateRepository _activationStateRepository;

  Future<LicenseRuntimeDecision> refreshFromStoredLicense({
    DateTime? now,
  }) async {
    final db = await _databaseProvider();
    await LicenseRuntimeTables.ensure(db);

    final hasPersistedActivation =
        await _activationStateRepository.hasPersistedActivationState();
    if (!hasPersistedActivation) {
      const decision = LicenseRuntimeDecision(
        mode: LicenseRuntimeMode.activationRequired,
        reason: 'No signed activation receipt is stored for this installation.',
      );
      await _persist(db, decision, source: 'LOCAL_BOOTSTRAP');
      return decision;
    }

    final license = await _activationStateRepository
        .loadAuthenticLicenseForCurrentInstallation(allowExpired: true);
    if (license == null) {
      const decision = LicenseRuntimeDecision(
        mode: LicenseRuntimeMode.readOnlyRevoked,
        reason: 'Stored activation receipt is invalid, tampered, or revoked.',
      );
      await _persist(db, decision, source: 'SIGNED_LICENSE');
      return decision;
    }

    final current = (now ?? DateTime.now()).toUtc();
    final mode = SubscriptionAccessPolicy.mode(license, current);
    final decision = LicenseRuntimeDecision(
        mode: mode,
        reason: SubscriptionAccessPolicy.message(mode),
        license: license);
    await LicenseValidationTables.projectSignedWindow(
      db,
      organizationId: license.organizationId,
      licenseId: license.licenseId,
      validationRequiredAt: license.validationRequiredAt,
      validationGraceUntil: license.validationGraceUntil,
    );
    await _persist(db, decision, source: 'SIGNED_LICENSE');
    return decision;
  }

  Future<LicenseRuntimeDecision> current() async {
    final db = await _databaseProvider();
    await LicenseRuntimeTables.ensure(db);
    final rows = await db.query(
      LicenseRuntimeTables.table,
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (rows.length != 1) {
      return refreshFromStoredLicense();
    }

    final row = rows.single;
    return LicenseRuntimeDecision(
      mode: row['mode']?.toString() ?? LicenseRuntimeMode.activationRequired,
      reason: row['reason']?.toString() ?? '',
    );
  }

  Future<void> requireOperationalWrite([String? operation]) async {
    // Re-evaluate the signed expiry before allowing a high-level write. DB
    // triggers independently provide a second enforcement layer.
    final decision = await refreshFromStoredLicense();
    if (!decision.isWritable) {
      throw ReadOnlyOperationException(
        decision.mode,
        operation == null
            ? decision.reason
            : '$operation is unavailable: ${decision.reason}',
      );
    }
  }

  Future<void> projectServerLifecycleDecision({
    required VerifiedLicense license,
    required DateTime serverTime,
  }) async {
    final db = await _databaseProvider();
    final status = license.operationalStatus.toUpperCase();
    final current = serverTime.toUtc();

    final mode = SubscriptionAccessPolicy.mode(license, current);

    await LicenseValidationTables.projectSignedWindow(
      db,
      organizationId: license.organizationId,
      licenseId: license.licenseId,
      validationRequiredAt: license.validationRequiredAt,
      validationGraceUntil: license.validationGraceUntil,
      serverTime: current,
      markSuccess: true,
    );

    await _persist(
      db,
      LicenseRuntimeDecision(
        mode: mode,
        reason: 'Server lifecycle decision: $status.',
        license: license,
      ),
      source: 'SERVER_LIFECYCLE',
      verifiedAt: current,
    );
  }

  Future<void> _persist(
    Database db,
    LicenseRuntimeDecision decision, {
    required String source,
    DateTime? verifiedAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final license = decision.license;
    await db.insert(
      LicenseRuntimeTables.table,
      <String, Object?>{
        'singleton_id': 1,
        'mode': decision.mode,
        'reason': decision.reason,
        'organization_id': license?.organizationId,
        'subscription_id': license?.subscriptionId,
        'license_id': license?.licenseId,
        'effective_at':
            (verifiedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'license_expires_at': license?.expiresAt.toUtc().toIso8601String(),
        'source': source,
        'last_verified_at': verifiedAt?.toUtc().toIso8601String(),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
