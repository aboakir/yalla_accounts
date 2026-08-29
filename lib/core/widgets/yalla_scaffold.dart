// 📁 lib/core/widgets/yalla_scaffold.dart
//
// YallaScaffold — هيكل عام موحّد للشاشات (RTL + متجاوب)
// ------------------------------------------------------
// - يوفّر شريط علوي YallaAppBar + قائمة جانبية YallaSidebar.
// - متجاوب: Drawer في الهاتف، Sidebar ثابت في الديسكتوب.
// - لا يعتمد أي بيانات وهمية، كل شيء حقيقي من النظام.
// - يستخدم نفس الثيم وهوية Yalla الرسمية.

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

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

    return Scaffold(
      appBar: YallaAppBar(
        workshopName: workshopName ?? 'ورشتي',
        logoPath: logoPath,
        showSearch: true,
        showUserAvatar: true,
      ),
      drawer: Responsive.isMobile(context)
          ? Drawer(child: YallaSidebar(currentRoute: routeName))
          : null,
      body: Row(
        children: [
          if (Responsive.isDesktop(context))
            SizedBox(width: 280, child: YallaSidebar(currentRoute: routeName)),
          Expanded(child: body),
        ],
      ),
    );
  }
}
