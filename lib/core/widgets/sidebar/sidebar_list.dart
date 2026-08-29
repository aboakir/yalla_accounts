import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/data/sidebar_items.dart';
import 'package:yalla_accounts/core/models/menu_item.dart';
import 'sidebar_tile.dart';

class SidebarList extends StatelessWidget {
  final bool isCollapsed;
  final String? currentRoute;
  final String searchQuery;
  final ValueChanged<String> onNavigate;

  const SidebarList({
    super.key,
    required this.isCollapsed,
    required this.currentRoute,
    required this.searchQuery,
    required this.onNavigate,
  });

  bool _matches(MenuItem item) {
    final q = searchQuery.toLowerCase();
    if (q.isEmpty) return true;

    if (item.title.toLowerCase().contains(q)) return true;

    if (item.children != null && item.children!.isNotEmpty) {
      // طابق أيضًا عناوين الأبناء
      if (item.children!.any((c) => c.title.toLowerCase().contains(q))) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = searchQuery.isEmpty
        ? sidebarItems
        : sidebarItems.where(_matches).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        return SidebarTile(
          item: filtered[i],
          isCollapsed: isCollapsed,
          currentRoute: currentRoute,
          onNavigate: onNavigate,
        );
      },
    );
  }
}
