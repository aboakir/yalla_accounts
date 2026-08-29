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
    if (path.contains(':')) {
      final f = File(path);
      if (f.existsSync()) return FileImage(f);
    }

    return null;
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
    final scaffold = Scaffold.maybeOf(context);
    final hasDrawer = scaffold?.hasDrawer ?? false;
    if (!hasDrawer) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.menu, color: Colors.white),
      tooltip: 'القائمة الجانبية',
      onPressed: () => _handle(scaffold?.openDrawer),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedImage = _resolveLogo(logoPath);

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
      title: Row(
        children: [
          if (showUserAvatar)
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: resolvedImage == null
                  ? const Icon(Icons.store, color: AppColors.primary)
                  : ClipOval(
                      child: Image(
                        image: resolvedImage,
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                      ),
                    ),
            ),

          if (showUserAvatar) const SizedBox(width: 12),

          Expanded(
            child: Text(
              'أهلاً بعودتك، $workshopName',
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
