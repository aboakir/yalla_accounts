// 📁 lib/features/insurance_agent/policies/widgets/policy_sidebar_overlay.dart
//
// PolicySidebarOverlay
// - Sidebar ثابت Desktop + Overlay Mobile/Tablet
//
// الاستخدام داخل الشاشة:
// Stack(
//   children: [
//     body,
//     PolicySidebarOverlay(
//       desktopFixed: desktopFixed,
//       sideOpen: _sideOpen,
//       onToggle: (v) => setState(() => _sideOpen = v),
//     ),
//   ],
// )

import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class PolicySidebarOverlay extends StatelessWidget {
  final bool desktopFixed;
  final bool sideOpen;
  final ValueChanged<bool> onToggle;
  final double width;

  const PolicySidebarOverlay({
    super.key,
    required this.desktopFixed,
    required this.sideOpen,
    required this.onToggle,
    this.width = 320,
  });

  Widget _rightSidebar() {
    return SizedBox(
      width: width,
      child: const Material(
        elevation: 10,
        child: YallaSidebar(currentRoute: AppRoutes.insurancePoliciesList),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (desktopFixed) {
      return Align(
        alignment: Alignment.centerRight,
        child: _rightSidebar(),
      );
    }

    // Mobile/Tablet overlay
    return Stack(
      children: [
        if (sideOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => onToggle(false),
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          top: 0,
          bottom: 0,
          right: sideOpen ? 0 : -width,
          width: width,
          child: _rightSidebar(),
        ),
      ],
    );
  }
}
