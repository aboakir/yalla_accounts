import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/licensing/entitlements/commercial_entitlement_policy.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/subscription_access_policy.dart';
import 'package:yalla_accounts/core/services/db/tables/license_runtime_tables.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

final workshopOnboardingServiceProvider = Provider<WorkshopOnboardingService>(
  (ref) => WorkshopOnboardingService(),
);

class WorkshopOnboardingService {
  WorkshopOnboardingService({
    Future<Database> Function()? databaseProvider,
    ActivationStateRepository? activation,
  })  : _database = databaseProvider ?? (() => DBService.database),
        _activation = activation ?? ActivationStateRepository();

  final Future<Database> Function() _database;
  final ActivationStateRepository _activation;

  Future<VerifiedLicense?> loadSetupLicense() async {
    final license =
        await _activation.loadAuthenticLicenseForCurrentInstallation(
      allowExpired: true,
    );
    if (license == null || !canStart(license)) return null;
    return license;
  }

  static bool canStart(VerifiedLicense license, {DateTime? now}) =>
      license.subscriptionId.trim().isNotEmpty &&
      license.organizationId.trim().isNotEmpty &&
      license.deviceId.trim().isNotEmpty &&
      license.installationId.trim().isNotEmpty &&
      CommercialEntitlementPolicy.evaluate(license).valid &&
      SubscriptionAccessPolicy.mode(license, now ?? DateTime.now().toUtc()) ==
          LicenseRuntimeMode.writable;

  Future<bool> needsCompletion(AppUser user) async {
    if (!user.isOwner || user.organizationId == null) return false;
    final db = await _database();
    final rows = await db.query(
      'workshop_onboarding_state',
      columns: ['status'],
      where: 'owner_user_id = ? AND organization_id = ?',
      whereArgs: [user.id, user.organizationId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['status'] == 'PENDING';
  }

  Future<CommercialSettings> loadCommercialSettings() async =>
      CommercialSettingsService.instance.get(executor: await _database());

  Future<void> saveCurrency(CountryPreset selected) async {
    final db = await _database();
    final current = await CommercialSettingsService.instance.get(executor: db);
    await CommercialSettingsService.instance.save(
      CommercialSettings(
        countryCode: current.countryCode,
        baseCurrencyCode: selected.currencyCode,
        currencySymbol: selected.currencySymbol,
        currencyDecimals: selected.decimals,
        defaultVatRate: current.defaultVatRate,
        pricesIncludeVat: current.pricesIncludeVat,
        taxRegistrationNumber: current.taxRegistrationNumber,
      ),
      executor: db,
    );
  }

  Future<void> complete(AppUser user, {required bool openBackup}) async {
    if (!user.isOwner || user.organizationId == null) {
      throw StateError('إكمال الإعداد متاح لمالك الورشة فقط.');
    }
    final db = await _database();
    final changed = await db.update(
      'workshop_onboarding_state',
      {
        'status': 'COMPLETED',
        'backup_choice': openBackup ? 'open_settings' : 'later',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'owner_user_id = ? AND organization_id = ? AND status = ?',
      whereArgs: [user.id, user.organizationId, 'PENDING'],
    );
    if (changed != 1) throw StateError('تعذر حفظ تقدم إعداد الورشة.');
  }
}
