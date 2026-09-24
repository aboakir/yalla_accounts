import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/experience/app_experience_service.dart';
import 'package:yalla_accounts/core/release/release_scope_config.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_sync_status_strip.dart';

/// Mobile-first daily navigation. Destinations follow the selected activities
/// while preserving one canonical route/data model.
class YallaMobileBottomNav extends StatelessWidget {
  final String? currentRoute;
  final VoidCallback onMore;

  const YallaMobileBottomNav({
    super.key,
    required this.currentRoute,
    required this.onMore,
  });

  bool _is(String prefix) => (currentRoute ?? '').startsWith(prefix);

  void _go(BuildContext context, String route) {
    final current = ModalRoute.of(context)?.settings.name;
    if (current == route) return;
    if (!AppRoutes.isRegisteredRoute(route)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('هذا الرابط غير متاح حاليًا.')),
      );
      return;
    }
    Navigator.of(context, rootNavigator: true).pushNamed(route);
  }

  ({String route, IconData icon, IconData selectedIcon, String label}) _primary(
    AppExperienceProfile profile,
  ) {
    if (profile.moduleEnabled(AppModule.repairs)) {
      return (
        route: AppRoutes.repairsDashboard,
        icon: Icons.car_repair_outlined,
        selectedIcon: Icons.car_repair_rounded,
        label: 'الإصلاحات',
      );
    }
    if (profile.moduleEnabled(AppModule.inventory)) {
      return (
        route: AppRoutes.inventory,
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        label: 'المخزون',
      );
    }
    if (ReleaseScopeConfig.insurancePilotVisible &&
        profile.moduleEnabled(AppModule.insurance)) {
      return (
        route: AppRoutes.insuranceAgentHome,
        icon: Icons.verified_user_outlined,
        selectedIcon: Icons.verified_user_rounded,
        label: 'التأمين',
      );
    }
    return (
      route: AppRoutes.financeDashboard,
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
      label: 'المال',
    );
  }

  ({String route, String label}) _quickAdd(AppExperienceProfile profile) {
    if (profile.moduleEnabled(AppModule.repairs)) {
      return (route: AppRoutes.repairsAdd, label: 'إضافة ملف');
    }
    if (profile.moduleEnabled(AppModule.inventory) &&
        profile.moduleEnabled(AppModule.purchases)) {
      return (route: AppRoutes.purchaseCreate, label: 'إضافة شراء');
    }
    if (ReleaseScopeConfig.insurancePilotVisible &&
        profile.moduleEnabled(AppModule.insurance)) {
      return (route: AppRoutes.insuranceAgentAddNew, label: 'إضافة تأمين');
    }
    return (route: AppRoutes.receiptVoucher, label: 'تسجيل قبض');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppExperienceProfile>(
      valueListenable: AppExperienceService.current,
      builder: (context, profile, _) {
        final primary = _primary(profile);
        final quickAdd = _quickAdd(profile);
        final homeSelected = currentRoute == AppRoutes.dashboard ||
            currentRoute == AppRoutes.homeDashboard;
        final primarySelected = _is(primary.route.split('/').take(2).join('/'));

        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.lightGrey.withOpacity(.9)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.05),
                  blurRadius: 14,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const YallaSyncStatusStrip(),
                NavigationBar(
                  height: 68,
                  elevation: 0,
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.lightGreen,
                  selectedIndex: homeSelected ? 0 : (primarySelected ? 1 : 3),
                  onDestinationSelected: (index) {
                    switch (index) {
                      case 0:
                        _go(context, AppRoutes.dashboard);
                        break;
                      case 1:
                        _go(context, primary.route);
                        break;
                      case 2:
                        _go(context, quickAdd.route);
                        break;
                      case 3:
                        onMore();
                        break;
                    }
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(
                        Icons.home_rounded,
                        color: AppColors.primary,
                      ),
                      label: 'الرئيسية',
                    ),
                    NavigationDestination(
                      icon: Icon(primary.icon),
                      selectedIcon: Icon(
                        primary.selectedIcon,
                        color: AppColors.primary,
                      ),
                      label: primary.label,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      selectedIcon: const Icon(
                        Icons.add_circle_rounded,
                        color: AppColors.primary,
                      ),
                      label: quickAdd.label,
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.grid_view_rounded),
                      selectedIcon: Icon(
                        Icons.grid_view_rounded,
                        color: AppColors.primary,
                      ),
                      label: 'المزيد',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
