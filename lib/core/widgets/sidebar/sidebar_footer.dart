// SidebarFooter — زر تبديل الثيم مع تلميح في الوضع المطوي + Divider علوي
// SidebarFooter — Theme toggle with collapsed tooltip + top divider
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/theme/theme_provider.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class SidebarFooter extends ConsumerWidget {
  final bool isCollapsed;
  const SidebarFooter({super.key, required this.isCollapsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeSwitcherProvider) == ThemeMode.dark;

    final switchWidget = Switch(
      value: isDark,
      activeColor: AppColors.primary,
      onChanged: (val) {
        // يفضّل وجود Notifier method، لكن نعتمد state مباشرة هنا
        // ignore: invalid_use_of_protected_member
        ref.read(themeSwitcherProvider.notifier).state =
            val ? ThemeMode.dark : ThemeMode.light;
      },
    );

    return Column(
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: isCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (!isCollapsed) ...[
                Row(
                  children: [
                    Icon(isDark ? Icons.dark_mode : Icons.light_mode,
                        color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text('الوضع الليلي'),
                  ],
                ),
                switchWidget,
              ] else
                Tooltip(
                  message: 'تبديل الوضع',
                  child: switchWidget,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
