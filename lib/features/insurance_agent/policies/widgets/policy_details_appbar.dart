// 📁 lib/features/insurance_agent/policies/widgets/policy_details_appbar.dart
//
// PolicyDetailsAppBar
// - AppBar موحد لصفحة تفاصيل البوليصة
// - يدعم: تحديث + فتح القائمة الجانبية على الموبايل
//
// الاستخدام:
// appBar: PolicyDetailsAppBar(
//   loading: _loading,
//   isDesktopFixed: desktopFixed,
//   onRefresh: _onRefresh,
//   onToggleSidebar: () => _toggleSide(!_sideOpen),
// )

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class PolicyDetailsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final bool loading;
  final bool isDesktopFixed;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleSidebar;

  const PolicyDetailsAppBar({
    super.key,
    required this.loading,
    required this.isDesktopFixed,
    this.onRefresh,
    this.onToggleSidebar,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primary,
      title: const Text(
        'تفاصيل البوليصة',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh, color: Colors.white),
        ),
        if (!isDesktopFixed)
          IconButton(
            tooltip: 'القائمة',
            onPressed: onToggleSidebar,
            icon: const Icon(Icons.menu, color: Colors.white),
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}
