import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

/// P03 phone navigation: daily destinations stay visible while the complete
/// product remains reachable from More/Drawer.
class YallaMobileBottomNav extends StatelessWidget {
  const YallaMobileBottomNav({
    super.key,
    required this.currentRoute,
    required this.onMore,
    this.onAdd,
  });

  final String? currentRoute;
  final VoidCallback onMore;
  final VoidCallback? onAdd;

  bool _is(String prefix) => (currentRoute ?? '').startsWith(prefix);

  void _go(BuildContext context, String route) {
    final current = ModalRoute.of(context)?.settings.name;
    if (current == route) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      route,
      (candidate) => candidate.settings.name == AppRoutes.startup,
    );
  }

  void _openAdd(BuildContext context) {
    if (onAdd != null) {
      onAdd!();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'إضافة جديدة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            _AddDestination(
              icon: Icons.add_road_rounded,
              label: 'إصلاح جديد',
              route: AppRoutes.repairsAdd,
              parentContext: context,
              sheetContext: sheetContext,
            ),
            _AddDestination(
              icon: Icons.payments_outlined,
              label: 'سند قبض',
              route: AppRoutes.receiptVoucher,
              parentContext: context,
              sheetContext: sheetContext,
            ),
            _AddDestination(
              icon: Icons.person_add_alt_1_rounded,
              label: 'إضافة عميل',
              route: AppRoutes.clientAdd,
              parentContext: context,
              sheetContext: sheetContext,
            ),
            _AddDestination(
              icon: Icons.edit_calendar_rounded,
              label: 'إضافة شيك',
              route: AppRoutes.chequesAdd,
              parentContext: context,
              sheetContext: sheetContext,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final homeSelected = currentRoute == AppRoutes.dashboard ||
        currentRoute == AppRoutes.homeDashboard;
    final repairsSelected = _is('/repairs');
    final financeSelected = _is('/finance');

    final selectedIndex = homeSelected
        ? 0
        : repairsSelected
            ? 1
            : financeSelected
                ? 3
                : 4;

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
          height: 72,
          elevation: 0,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.lightGreen,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            switch (index) {
              case 0:
                _go(context, AppRoutes.dashboard);
                break;
              case 1:
                _go(context, AppRoutes.repairs);
                break;
              case 2:
                _openAdd(context);
                break;
              case 3:
                _go(context, AppRoutes.financeDashboard);
                break;
              case 4:
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
              icon: Icon(Icons.add_circle_outline_rounded, size: 30),
              selectedIcon:
                  Icon(Icons.add_circle_rounded, color: AppColors.primary),
              label: 'إضافة',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.primary,
              ),
              label: 'المالية',
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

class _AddDestination extends StatelessWidget {
  const _AddDestination({
    required this.icon,
    required this.label,
    required this.route,
    required this.parentContext,
    required this.sheetContext,
  });

  final IconData icon;
  final String label;
  final String route;
  final BuildContext parentContext;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 54,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        label,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: () {
        Navigator.pop(sheetContext);
        Navigator.of(parentContext).pushNamed(route);
      },
    );
  }
}
