// 📁 lib/core/widgets/sidebar/sidebar_tile.dart
//
// ✅ SidebarTile — نسخة محسّنة بدون تغيير البنية الأصلية
// - دعم أفضل لـ RTL
// - لون نص عند التحديد
// - تفعيل Tooltip عند الوضع المختصر
// - تحسين hover و active state
// - ضمان استمرار الأنيميشن بشكل صحيح (مع تأجيل setState عن أحداث الماوس)

import 'dart:async';
import 'package:flutter/material.dart';
import 'sidebar_subtile.dart';
import 'package:yalla_accounts/core/models/menu_item.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SidebarTile extends StatefulWidget {
  final MenuItem item;
  final bool isCollapsed;
  final String? currentRoute;
  final ValueChanged<String> onNavigate;

  const SidebarTile({
    super.key,
    required this.item,
    required this.isCollapsed,
    required this.currentRoute,
    required this.onNavigate,
  });

  @override
  State<SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<SidebarTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expCtrl;
  late final Animation<double> _rot;
  bool _hovered = false;

  bool get _isExpanded =>
      widget.item.children != null &&
      widget.currentRoute != null &&
      widget.item.children!.any((c) => c.route == widget.currentRoute);

  @override
  void initState() {
    super.initState();
    _expCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _rot = Tween<double>(begin: 0, end: 0.5).animate(_expCtrl);

    if (_isExpanded) {
      _expCtrl.value = 1;
    }
  }

  @override
  void dispose() {
    _expCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.item.children != null) {
      if (_expCtrl.isCompleted) {
        _expCtrl.reverse();
      } else {
        _expCtrl.forward();
      }
    }
  }

  // ✨ مهم: تأجيل تغييرات الحالة عن حدث الماوس لتفادي assert في mouse_tracker
  void _deferSetHovered(bool v) {
    // استخدم microtask لسرعة الاستجابة، أو addPostFrameCallback؛ الاثنان آمنان
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() => _hovered = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool selected =
        widget.currentRoute == widget.item.route || _isExpanded;

    final Color textColor = selected ? AppColors.primary : Colors.black87;
    final Color? bg = selected
        ? AppColors.primary.withOpacity(0.12)
        : (_hovered ? Colors.grey.withOpacity(0.12) : null);

    final tile = InkWell(
      onTap: () {
        if (widget.item.children != null) {
          _toggle();
        } else if (widget.item.route != null) {
          widget.onNavigate(widget.item.route!);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.isCollapsed ? 8 : 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: AdaptiveRow(
          textDirection: TextDirection.rtl,
          children: [
            Icon(
              widget.item.icon,
              size: 22,
              color: selected ? AppColors.primary : Colors.grey[800],
            ),
            if (!widget.isCollapsed) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.item.children != null)
                RotationTransition(
                  turns: _rot,
                  child: const Icon(Icons.expand_more, size: 18),
                ),
            ],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          // ❌ كان: setState مباشرة داخل حدث الماوس
          // ✅ الآن: نؤجل التغيير لتجنب '_debugDuringDeviceUpdate'
          onEnter: (_) => _deferSetHovered(true),
          onExit: (_) => _deferSetHovered(false),
          child: widget.isCollapsed
              ? Tooltip(
                  message: widget.item.title,
                  child: tile,
                )
              : tile,
        ),

        // ---- Sub Items ----
        if (widget.item.children != null)
          SizeTransition(
            sizeFactor: _expCtrl,
            child: Column(
              children: widget.item.children!
                  .map(
                    (sub) => SidebarSubTile(
                      item: sub,
                      isSelected: widget.currentRoute == sub.route,
                      isCollapsed: widget.isCollapsed,
                      onNavigate: widget.onNavigate,
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
