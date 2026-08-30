import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

/// الهاتف فقط: تنقل يومي مختصر. بقية النظام يبقى داخل Drawer/More.
/// لا يغيّر routes أو قاعدة البيانات.
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
    Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final repairsSelected = _is('/repairs');
    final homeSelected = currentRoute == AppRoutes.dashboard ||
        currentRoute == AppRoutes.homeDashboard;

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
        child: NavigationBar(
          height: 68,
          elevation: 0,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.lightGreen,
          selectedIndex: homeSelected ? 0 : (repairsSelected ? 1 : 3),
          onDestinationSelected: (index) async {
            switch (index) {
              case 0:
                _go(context, AppRoutes.dashboard);
                break;
              case 1:
                _go(context, AppRoutes.repairs);
                break;
              case 2:
                Navigator.of(context).pushNamed(AppRoutes.repairsAdd);
                break;
              case 3:
                onMore();
                break;
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.primary),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.car_repair_outlined),
              selectedIcon:
                  Icon(Icons.car_repair_rounded, color: AppColors.primary),
              label: 'الإصلاحات',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline_rounded),
              selectedIcon:
                  Icon(Icons.add_circle_rounded, color: AppColors.primary),
              label: 'إضافة',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              selectedIcon:
                  Icon(Icons.grid_view_rounded, color: AppColors.primary),
              label: 'المزيد',
            ),
          ],
        ),
      ),
    );
  }
}
