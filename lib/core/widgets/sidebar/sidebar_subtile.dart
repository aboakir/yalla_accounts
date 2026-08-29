// 📁 lib/core/widgets/sidebar/sidebar_subtile.dart
//
// ✅ SidebarSubTile — نسخة محسّنة + إصلاح أخطاء البناء
// - استيراد LogicalKeyboardKey صحيح.
// - خريطة Shortcuts بدون const لتفادي "Invalid constant value".
// - مفاتيح اختصار Enter و Space فريدة.
// - RTL، Hover، Focus، Tooltip عند الطي.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey; // ← مهم
import 'package:yalla_accounts/core/models/menu_item.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class SidebarSubTile extends StatefulWidget {
  final MenuItem item;
  final bool isSelected;
  final bool isCollapsed;
  final ValueChanged<String> onNavigate;

  const SidebarSubTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isCollapsed,
    required this.onNavigate,
  });

  @override
  State<SidebarSubTile> createState() => _SidebarSubTileState();
}

class _SidebarSubTileState extends State<SidebarSubTile> {
  bool _hovered = false;
  bool _focused = false;

  void _defer(void Function() fn) {
    scheduleMicrotask(() {
      if (!mounted) return;
      fn();
    });
  }

  void _handleActivate() {
    final route = widget.item.route;
    if (route == null) return;
    widget.onNavigate(route);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.item.route != null;
    final selected = widget.isSelected;

    final bgColor = selected
        ? AppColors.primary.withOpacity(0.12)
        : (_hovered ? Colors.grey.withOpacity(0.08) : null);

    final textColor = selected
        ? AppColors.primary
        : (enabled
            ? Theme.of(context).textTheme.bodyMedium?.color
            : Colors.grey);

    final dotColor = selected
        ? AppColors.primary
        : (enabled ? Colors.grey : Colors.grey.shade400);

    final content = InkWell(
      onTap: enabled ? _handleActivate : null,
      borderRadius: BorderRadius.circular(8),
      focusColor: AppColors.primary.withOpacity(0.10),
      hoverColor: Colors.transparent,
      canRequestFocus: enabled,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.isCollapsed ? 16 : 36,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(Icons.circle, size: 6, color: dotColor),
            const SizedBox(width: 8),
            if (!widget.isCollapsed)
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final wrapped = Focus(
      onFocusChange: (v) => _defer(() => setState(() => _focused = v)),
      child: MouseRegion(
        onEnter: (_) => _defer(() => setState(() => _hovered = true)),
        onExit: (_) => _defer(() => setState(() => _hovered = false)),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Shortcuts(
          // ملاحظة: لا تستخدم const هنا
          shortcuts: <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  if (enabled) _handleActivate();
                  return null;
                },
              ),
            },
            child: Semantics(
              button: enabled,
              selected: selected,
              focusable: enabled,
              focused: _focused,
              label: widget.item.title,
              child: content,
            ),
          ),
        ),
      ),
    );

    // Tooltip فقط عند الطي
    if (widget.isCollapsed) {
      return Tooltip(
        message: widget.item.title,
        preferBelow: false,
        child: wrapped,
      );
    }
    return wrapped;
  }
}
