import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class YallaScaffold extends StatelessWidget {
  final Widget body;
  final String? currentRoute;
  final String? workshopName;
  final String? logoPath;

  const YallaScaffold({
    super.key,
    required this.body,
    this.currentRoute,
    this.workshopName,
    this.logoPath,
  });

  @override
  Widget build(BuildContext context) {
    final routeName = currentRoute ?? ModalRoute.of(context)?.settings.name;
    final isDesktop = context.isDesktopWidth;
    final isPhone = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      appBar: YallaAppBar(
        workshopName: workshopName ?? 'ورشتي',
        logoPath: logoPath,
        showSearch: !isPhone,
        showUserAvatar: true,
      ),
      drawer: !isDesktop
          ? Drawer(
              child: SafeArea(
                child: YallaSidebar(currentRoute: routeName),
              ),
            )
          : null,
      body: SafeArea(
        child: AdaptiveRow(
          children: [
            if (isDesktop)
              SizedBox(
                width: 300,
                child: YallaSidebar(currentRoute: routeName),
              ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: isPhone
          ? Builder(
              builder: (navContext) => YallaMobileBottomNav(
                currentRoute: routeName,
                onMore: () => Scaffold.of(navContext).openDrawer(),
              ),
            )
          : null,
    );
  }
}
