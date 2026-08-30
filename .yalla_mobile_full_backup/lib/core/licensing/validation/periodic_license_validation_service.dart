import 'dart:async';

import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_lifecycle_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/core/services/db/tables/license_validation_tables.dart';

class PeriodicValidationResult {
  const PeriodicValidationResult({
    required this.status,
    required this.message,
    this.validationRequiredAt,
    this.validationGraceUntil,
  });

  final String status;
  final String message;
  final DateTime? validationRequiredAt;
  final DateTime? validationGraceUntil;
}

class LicenseValidationWindow {
  const LicenseValidationWindow({
    required this.requiredAt,
    required this.graceUntil,
  });

  final DateTime requiredAt;
  final DateTime graceUntil;

  factory LicenseValidationWindow.fromLicense(VerifiedLicense license) {
    return LicenseValidationWindow(
      requiredAt: license.validationRequiredAt,
      graceUntil: license.validationGraceUntil,
    );
  }

  bool isDue(DateTime now) => !requiredAt.isAfter(now.toUtc());
  bool isGraceExpired(DateTime now) => !graceUntil.isAfter(now.toUtc());
}

/// SEC.012 periodic validation coordinator.
///
/// Default commercial policy is minted server-side as 30 days + 7 days grace.
/// New signed licenses carry concrete `validation_required_at` and
/// `validation_grace_until` timestamps. A legacy SEC.006-SEC.011 license is
/// supported only through the verifier's fixed transition defaults until its
/// next successful online validation replaces it with a current envelope.
class PeriodicLicenseValidationService {
  PeriodicLicenseValidationService({
    ActivationStateRepository? activationStateRepository,
    LicenseLifecycleService? lifecycleService,
    LicenseRuntimeService? runtimeService,
  })  : _activationStateRepository =
            activationStateRepository ?? ActivationStateRepository(),
        _lifecycleService = lifecycleService ?? LicenseLifecycleService(),
        _runtimeService = runtimeService ?? LicenseRuntimeService();

  final ActivationStateRepository _activationStateRepository;
  final LicenseLifecycleService _lifecycleService;
  final LicenseRuntimeService _runtimeService;

  Future<PeriodicValidationResult> evaluate({
    DateTime? now,
    String reason = 'PERIODIC',
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final license = await _activationStateRepository
        .loadAuthenticLicenseForCurrentInstallation(allowExpired: true);
    if (license == null) {
      await _runtimeService.refreshFromStoredLicense(now: current);
      return const PeriodicValidationResult(
        status: 'NO_AUTHENTIC_LICENSE',
        message: 'No authentic signed license is available for validation.',
      );
    }

    final window = LicenseValidationWindow.fromLicense(license);
    final db = await DBService.database;
    await LicenseValidationTables.projectSignedWindow(
      db,
      organizationId: license.organizationId,
      licenseId: license.licenseId,
      validationRequiredAt: window.requiredAt,
      validationGraceUntil: window.graceUntil,
    );

    if (!window.isDue(current)) {
      await _runtimeService.refreshFromStoredLicense(now: current);
      return PeriodicValidationResult(
        status: 'NOT_DUE',
        message: 'Online validation is not due yet.',
        validationRequiredAt: window.requiredAt,
        validationGraceUntil: window.graceUntil,
      );
    }

    if (!_lifecycleService.isConfigured) {
      await LicenseValidationTables.recordFailure(
        db,
        reason: 'Licensing server/trust anchor is not configured ($reason).',
        attemptedAt: current,
      );
      final runtime =
          await _runtimeService.refreshFromStoredLicense(now: current);
      return PeriodicValidationResult(
        status: runtime.isReadOnly ? 'GRACE_EXPIRED' : 'DUE_OFFLINE_GRACE',
        message: runtime.reason,
        validationRequiredAt: window.requiredAt,
        validationGraceUntil: window.graceUntil,
      );
    }

    try {
      final refreshed = await _lifecycleService.validateNow();
      await LicenseValidationTables.projectSignedWindow(
        db,
        organizationId: refreshed.organizationId,
        licenseId: refreshed.licenseId,
        validationRequiredAt: refreshed.validationRequiredAt,
        validationGraceUntil: refreshed.validationGraceUntil,
        serverTime: refreshed.issuedAt,
        markSuccess: true,
      );
      await _runtimeService.refreshFromStoredLicense();
      return PeriodicValidationResult(
        status: 'VALIDATED',
        message: 'Periodic online validation succeeded.',
        validationRequiredAt: refreshed.validationRequiredAt,
        validationGraceUntil: refreshed.validationGraceUntil,
      );
    } catch (error) {
      await LicenseValidationTables.recordFailure(
        db,
        reason: error.toString(),
        attemptedAt: current,
      );
      final runtime =
          await _runtimeService.refreshFromStoredLicense(now: current);
      return PeriodicValidationResult(
        status:
            runtime.isReadOnly ? 'GRACE_EXPIRED' : 'VALIDATION_FAILED_GRACE',
        message: runtime.reason,
        validationRequiredAt: window.requiredAt,
        validationGraceUntil: window.graceUntil,
      );
    }
  }
}

class PeriodicLicenseValidationScheduler {
  PeriodicLicenseValidationScheduler._();

  static Timer? _timer;
  static bool _running = false;

  static void start() {
    if (_running) return;
    _running = true;
    final service = PeriodicLicenseValidationService();
    unawaited(_safeEvaluate(service, 'STARTUP'));
    _timer ??= Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(_safeEvaluate(service, 'HOURLY_RUNTIME'));
    });
  }

  static Future<void> _safeEvaluate(
    PeriodicLicenseValidationService service,
    String reason,
  ) async {
    try {
      await service.evaluate(reason: reason);
    } catch (_) {
      // DB-level signed-deadline enforcement remains active even if an
      // unexpected scheduler exception occurs. The next cycle retries.
    }
  }

  static void stopForTesting() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }
}
