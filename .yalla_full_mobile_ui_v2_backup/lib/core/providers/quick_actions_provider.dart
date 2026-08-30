// 📁 lib/core/providers/quick_actions_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// نموذج عنصر إجراء سريع
class QuickActionItem {
  final String id;
  final String title;
  final IconData icon;
  final String route;

  QuickActionItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.route,
  });
}

/// StateNotifier لإدارة قائمة الإجراءات السريعة القابلة للتخصيص
class QuickActionsNotifier extends StateNotifier<List<QuickActionItem>> {
  QuickActionsNotifier() : super(_initialActions());

  /// قائمة افتراضية بالإجراءات
  static List<QuickActionItem> _initialActions() => [
        QuickActionItem(
          id: 'repair',
          title: 'إصلاح مركبة',
          icon: Icons.directions_car,
          route: '/repairs/add',
        ),
        QuickActionItem(
          id: 'receivePayment',
          title: 'قبض دفعة',
          icon: Icons.download,
          route: '/finance/receive_payment',
        ),
        QuickActionItem(
          id: 'pay',
          title: 'دفع',
          icon: Icons.upload,
          route: '/finance/payments',
        ),
        QuickActionItem(
          id: 'purchase',
          title: 'شراء',
          icon: Icons.shopping_cart,
          route: '/finance/purchases',
        ),
        QuickActionItem(
          id: 'sell',
          title: 'بيع',
          icon: Icons.storefront,
          route: '/sales/sell',
        ),
      ];

  /// إعادة ترتيب الإجراءات
  void reorder(int oldIndex, int newIndex) {
    final items = [...state];
    if (newIndex > oldIndex) newIndex--;
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    state = items;
  }

  /// إضافة إجراء جديد
  void addAction(QuickActionItem action) {
    state = [...state, action];
  }

  /// إزالة إجراء بحسب المعرف
  void removeAction(String id) {
    state = state.where((x) => x.id != id).toList();
  }

  /// تحديث إجراء موجود
  void updateAction(QuickActionItem updated) {
    state = state.map((x) => x.id == updated.id ? updated : x).toList();
  }
}

/// Provider للوصول إلى قائمة الإجراءات السريعة
final quickActionsProvider =
    StateNotifierProvider<QuickActionsNotifier, List<QuickActionItem>>(
  (ref) => QuickActionsNotifier(),
);
