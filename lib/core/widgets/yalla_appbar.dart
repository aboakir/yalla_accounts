import 'package:yalla_accounts/features/settings/providers/workshop_settings_provider.dart';
// 📁 lib/core/widgets/yalla_appbar.dart
//
// YallaAppBar — نسخة ثابتة 100% بدون أي أخطاء Assets
// يدعم:
// ✔ إظهار اللوجو من مسار جهاز فقط
// ✔ في حال عدم وجود لوجو → Icon.store
// ✔ بدون AssetImage نهائيًا حتى لا ينتج خطأ
// ---------------------------------------------------------------

import 'dart:io';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_route_frame.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class YallaAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String workshopName;
  final String? logoPath;

  final bool showThemeToggle;
  final bool showUserAvatar;
  final bool showSearch;
  final bool showNotifications;

  final int? notificationsCount;

  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationsTap;

  final List<Widget>? extraActions;
  final List<Widget>? actions;

  final Widget? leading;

  const YallaAppBar({
    super.key,
    required this.workshopName,
    this.logoPath,
    this.showThemeToggle = false,
    this.showUserAvatar = true,
    this.showSearch = false,
    this.showNotifications = false,
    this.notificationsCount,
    this.onSearchTap,
    this.onNotificationsTap,
    this.extraActions,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  // -------------------------------
  // منع انقفال التطبيق بسبب Decoding
  // -------------------------------
  ImageProvider? _resolveLogo(String? path) {
    if (path == null || path.trim().isEmpty) return null;

    // إذا كان مسار جهاز Windows
    if (!path.startsWith('assets/')) {
      final f = File(path);
      if (f.existsSync()) return FileImage(f);
    }

    return null;
  }

  Widget _brandMark() {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Image.asset(
        'assets/branding/yallah_mark.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.store, color: AppColors.primary),
      ),
    );
  }

  Future<void> _touch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastActivity', DateTime.now().millisecondsSinceEpoch);
  }

  void _handle(VoidCallback? cb) async {
    await _touch();
    cb?.call();
  }

  Widget _defaultLeading(BuildContext context) {
    final mobileRouteScope = YallaMobileRouteScope.maybeOf(context);
    if (MediaQuery.sizeOf(context).width < 600 && mobileRouteScope != null) {
      return IconButton(
        key: const Key('yalla_appbar_mobile_menu_button'),
        icon: const Icon(Icons.menu, color: Colors.white),
        tooltip: 'القائمة الجانبية',
        onPressed: () => _handle(mobileRouteScope.openDrawer),
      );
    }

    final scaffold = Scaffold.maybeOf(context);
    if (scaffold == null) return const SizedBox.shrink();

    final hasDrawer = scaffold.widget.drawer != null;
    final hasEndDrawer = scaffold.widget.endDrawer != null;
    if (!hasDrawer && !hasEndDrawer) return const SizedBox.shrink();

    return IconButton(
      key: const Key('yalla_appbar_mobile_menu_button'),
      icon: const Icon(Icons.menu, color: Colors.white),
      tooltip: 'القائمة الجانبية',
      onPressed: () => _handle(() {
        if (hasDrawer) {
          scaffold.openDrawer();
        } else {
          scaffold.openEndDrawer();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(workshopSettingsProvider).valueOrNull;
    final resolvedImage =
        _resolveLogo(identity?.logoPath) ?? _resolveLogo(logoPath);
    final displayName = (identity?.workshopName?.trim().isNotEmpty ?? false)
        ? identity!.workshopName!
        : workshopName;

    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 16,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          overflow: TextOverflow.ellipsis,
        );

    final mergedExtra = <Widget>[
      ...?extraActions,
      ...?actions,
    ];

    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      leading: leading ?? _defaultLeading(context),
      title: AdaptiveRow(
        children: [
          if (showUserAvatar)
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: resolvedImage == null
                  ? _brandMark()
                  : ClipOval(
                      child: Image(
                        image: resolvedImage,
                        errorBuilder: (_, __, ___) => _brandMark(),
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                      ),
                    ),
            ),

          if (showUserAvatar) const SizedBox(width: 12),

          Expanded(
            child: Text(
              'أهلاً بعودتك، $displayName',
              style: titleStyle,
            ),
          ),

          // 🔎 زر البحث
          if (showSearch)
            IconButton(
              tooltip: 'بحث عام',
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () => _handle(onSearchTap),
            ),

          // الإضافات — لا نعرض تنبيهات ولا ثيم حسب طلبك
          ...mergedExtra,
        ],
      ),
    );
  }
}
