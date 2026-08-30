import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

/// Global authenticated phone shell.
///
/// It deliberately does not replace feature Scaffolds. It adds only the
/// application-level phone navigation around existing screens, so desktop,
/// business logic, database and feature-specific AppBars remain untouched.
class YallaMobileRouteFrame extends StatelessWidget {
  const YallaMobileRouteFrame({
    super.key,
    required this.routeName,
    required this.child,
  });

  final String routeName;
  final Widget child;

  bool get _screenAlreadyOwnsPhoneNav =>
      routeName == AppRoutes.dashboard ||
      routeName == AppRoutes.homeDashboard ||
      routeName == AppRoutes.repairsDashboard;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) return child;
    if (_screenAlreadyOwnsPhoneNav) return child;

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: YallaSidebar(currentRoute: routeName),
        ),
      ),
      body: child,
      bottomNavigationBar: Builder(
        builder: (navContext) => YallaMobileBottomNav(
          currentRoute: routeName,
          onMore: () => Scaffold.of(navContext).openDrawer(),
        ),
      ),
    );
  }
}
