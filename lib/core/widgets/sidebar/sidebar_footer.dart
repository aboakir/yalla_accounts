import 'package:flutter/material.dart';

/// Yallah Accounts uses one canonical light visual identity.
/// The former dark-mode toggle was removed because the production root app
/// does not expose a dark theme and the brand system is intentionally light.
class SidebarFooter extends StatelessWidget {
  final bool isCollapsed;

  const SidebarFooter({super.key, required this.isCollapsed});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
