import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/experience/app_experience_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppExperienceService.resetForTesting();
  });

  test('default commercial profile is garage simple mode', () {
    final profile = AppExperienceProfile.defaults;

    expect(profile.activities, <BusinessActivity>{BusinessActivity.garage});
    expect(profile.mode, ExperienceMode.simple);
    expect(profile.moduleEnabled(AppModule.repairs), isTrue);
    expect(profile.moduleEnabled(AppModule.inventory), isTrue);
    expect(profile.moduleEnabled(AppModule.insurance), isFalse);
  });
  test('parts profile exposes stock and purchases without repairs', () {
    const profile = AppExperienceProfile(
      activities: <BusinessActivity>{BusinessActivity.parts},
      mode: ExperienceMode.simple,
    );

    expect(profile.moduleEnabled(AppModule.inventory), isTrue);
    expect(profile.moduleEnabled(AppModule.purchases), isTrue);
    expect(profile.moduleEnabled(AppModule.repairs), isFalse);
    expect(
      profile.isRouteVisible('/inventory', insurancePilotVisible: false),
      isTrue,
    );
    expect(
      profile.isRouteVisible('/repairs', insurancePilotVisible: false),
      isFalse,
    );
  });

  test('simple mode hides advanced accounting but advanced mode exposes it',
      () {
    const simple = AppExperienceProfile(
      activities: <BusinessActivity>{BusinessActivity.garage},
      mode: ExperienceMode.simple,
    );
    const advanced = AppExperienceProfile(
      activities: <BusinessActivity>{BusinessActivity.garage},
      mode: ExperienceMode.advanced,
    );
    for (final route in AppExperienceProfile.advancedAccountingRoutes) {
      expect(
        simple.isRouteVisible(route, insurancePilotVisible: false),
        isFalse,
        reason: route,
      );
      expect(
        advanced.isRouteVisible(route, insurancePilotVisible: false),
        isTrue,
        reason: route,
      );
    }
  });

  test('insurance stays hidden when pilot flag is off', () {
    const profile = AppExperienceProfile(
      activities: <BusinessActivity>{BusinessActivity.insurance},
      mode: ExperienceMode.advanced,
    );

    expect(
      profile.isRouteVisible(
        '/insurance-agent/home',
        insurancePilotVisible: false,
      ),
      isFalse,
    );
    expect(
      profile.isSearchSourceVisible(
        'documents',
        insurancePilotVisible: false,
      ),
      isFalse,
    );
  });
  test('saved profile survives service reload', () async {
    const saved = AppExperienceProfile(
      activities: <BusinessActivity>{
        BusinessActivity.garage,
        BusinessActivity.parts,
      },
      mode: ExperienceMode.advanced,
      moduleOverrides: <AppModule, bool>{
        AppModule.employees: false,
      },
    );

    await AppExperienceService.save(saved);
    final reloaded = await AppExperienceService.load(force: true);

    expect(reloaded.activities, saved.activities);
    expect(reloaded.mode, ExperienceMode.advanced);
    expect(reloaded.moduleEnabled(AppModule.employees), isFalse);
    expect(reloaded.moduleEnabled(AppModule.inventory), isTrue);
  });

  test('module overrides hide routes without deleting activity choice', () {
    const profile = AppExperienceProfile(
      activities: <BusinessActivity>{BusinessActivity.garage},
      mode: ExperienceMode.simple,
      moduleOverrides: <AppModule, bool>{AppModule.repairs: false},
    );

    expect(profile.activities.contains(BusinessActivity.garage), isTrue);
    expect(profile.moduleEnabled(AppModule.repairs), isFalse);
    expect(
      profile.isRouteVisible('/repairs/add', insurancePilotVisible: false),
      isFalse,
    );
  });
}
