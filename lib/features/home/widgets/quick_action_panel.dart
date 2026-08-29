// 📁 lib/features/home/widgets/quick_action_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/providers/quick_actions_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// Panel لعرض الإجراءات السريعة بصورة Docked أسفل الشاشة
class QuickActionPanel extends ConsumerWidget {
  /// دالة تنقل عند اختيار إجراء
  final void Function(QuickActionItem) onActionSelected;

  const QuickActionPanel({
    super.key,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(quickActionsProvider);

    // نظهر أول 3، والباقي تحت "المزيد"
    final visible = actions.length <= 3 ? actions : actions.sublist(0, 3);
    final hidden = actions.length <= 3 ? [] : actions.sublist(3);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AdaptiveRow(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // إجراءات مرئية
          ...visible.map((item) {
            return Expanded(
              child: InkWell(
                onTap: () => onActionSelected(item),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, color: AppColors.primary),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
          // زر المزيد إذا كانت هناك إجراءات مخفية
          if (hidden.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.more_horiz, color: AppColors.primary),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (_) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: hidden.map((item) {
                      return ListTile(
                        leading: Icon(item.icon, color: AppColors.primary),
                        title: Text(item.title),
                        onTap: () {
                          Navigator.pop(context);
                          onActionSelected(item);
                        },
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
