// 📁 lib/core/widgets/responsive_scaffold.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

class ResponsiveScaffold extends StatelessWidget {
  /// المحتوى الرئيسي في الجهة اليسرى (أو أولاً قبل الشريط الجانبي على الشاشات العريضة).
  final Widget content;

  /// عنوان AppBar.
  final String title;

  /// المسار الحالي لإبرازه داخل الشريط الجانبي.
  final String currentRoute;

  /// زر عائم اختياري.
  final Widget? floatingActionButton;

  /// نقطة الفصل بين الموبايل/التابلت وبين الديسكتوب لعرض الشريط الجانبي الدائم.
  final double breakpoint;

  /// عرض الشريط الجانبي على الشاشات العريضة.
  final double sidebarWidth;

  /// عناصر إضافية على الـ AppBar (أزرار يمين العنوان).
  final List<Widget>? appBarActions;

  const ResponsiveScaffold({
    super.key,
    required this.content,
    required this.title,
    required this.currentRoute,
    this.floatingActionButton,
    this.breakpoint = 800,
    this.sidebarWidth = 260,
    this.appBarActions,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= breakpoint;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: appBarActions,
        // عند الشاشات الضيقة نُظهر زر الفتح من اليمين (endDrawer)
        leading: !isWide
            ? Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                  tooltip: 'القائمة',
                ),
              )
            : null,
      ),

      // Drawer يظهر على الشاشات الضيقة فقط
      endDrawer: !isWide
          ? Drawer(
              child: SafeArea(
                child: YallaSidebar(currentRoute: currentRoute),
              ),
            )
          : null,

      body: SafeArea(
        child: Row(
          children: [
            // المحتوى الرئيسي يتمدّد
            Expanded(child: content),

            // الشريط الجانبي ثابت على الشاشات العريضة
            if (isWide)
              Container(
                width: sidebarWidth,
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? Colors.black : Colors.black12)
                          .withOpacity(0.06),
                      blurRadius: 6,
                      offset: const Offset(-2, 0),
                    ),
                  ],
                ),
                child: YallaSidebar(currentRoute: currentRoute),
              ),
          ],
        ),
      ),

      floatingActionButton: floatingActionButton,
    );
  }
}
