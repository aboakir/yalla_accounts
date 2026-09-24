import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/experience/app_experience_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/finance/services/financial_overview_service.dart';
import 'package:yalla_accounts/features/home/services/daily_dashboard_service.dart';
import 'package:yalla_accounts/features/home/widgets/first_use_checklist_card.dart';

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

  testWidgets(
      'first-use guide opens a real activity route and can be dismissed',
      (tester) async {
    final now = DateTime(2026, 9, 24);
    final finance = FinancialOverviewSnapshot(
      from: now,
      to: now,
      cashBalance: 0,
      bankBalance: 0,
      customerReceivables: 0,
      customerCredits: 0,
      supplierPayables: 0,
      supplierAdvances: 0,
      payrollPayables: 0,
      revenue: 0,
      expenses: 0,
      collections: 0,
      supplierPayments: 0,
      payrollPayments: 0,
      periodDebit: 0,
      periodCredit: 0,
      integrityIssueCount: 0,
      topAccounts: const [],
      recentEntries: const [],
    );
    final data = DailyDashboardData(
      name: 'ورشتي',
      currency: '₪',
      today: finance,
      period: finance,
      cars: const [],
      collectionItems: const [],
      newFiles: 0,
      previousFiles: 0,
      materials: const [],
      issues: const [],
      now: now,
    );
    String? openedRoute;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstUseChecklistCard(
            profile: AppExperienceProfile.defaults,
            data: data,
            onOpen: (route, _) => openedRoute = route,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ابدأ أول عملية'), findsOneWidget);
    await tester.tap(find.text('أنشئ أول ملف إصلاح'));
    expect(openedRoute, AppRoutes.repairsAdd);
    await tester.tap(find.byTooltip('إخفاء دليل البداية'));
    await tester.pumpAndSettle();
    expect(find.text('ابدأ أول عملية'), findsNothing);
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
