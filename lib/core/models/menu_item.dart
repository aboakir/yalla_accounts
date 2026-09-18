// 📁 lib/core/models/menu_item.dart
import 'package:flutter/material.dart';

/// عنصر قائمة للسايدبار.
/// يدعم عقدة رئيسية بلا route مع أبناء، أو عنصر تنقّل بوراثة مباشرة.
class MenuItem {
  final String title;
  final String? route; // قد تكون null لو كان عنصر مجموعة
  final IconData icon;
  final List<MenuItem>? children;

  /// منشئ ثابت لدعم const في شجرة السايدبار.
  const MenuItem({
    required this.title,
    required this.route,
    required this.icon,
    this.children,
  });

  /// هل لديه أبناء؟
  bool get hasChildren => (children != null && children!.isNotEmpty);

  /// هل يصلح للتنقّل؟
  bool get isNavigable => route != null && route!.isNotEmpty;

  /// نسخة معدلة.
  MenuItem copyWith({
    String? title,
    String? route,
    IconData? icon,
    List<MenuItem>? children,
  }) {
    return MenuItem(
      title: title ?? this.title,
      route: route ?? this.route,
      icon: icon ?? this.icon,
      children: children ?? this.children,
    );
  }

  @override
  String toString() =>
      'MenuItem(title: $title, route: $route, children: ${children?.length ?? 0})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MenuItem &&
        other.title == title &&
        other.route == route &&
        other.icon.codePoint == icon.codePoint &&
        other.icon.fontFamily == icon.fontFamily &&
        other.icon.fontPackage == icon.fontPackage &&
        _listEquals(other.children, children);
  }

  @override
  int get hashCode =>
      title.hashCode ^
      (route?.hashCode ?? 0) ^
      icon.codePoint.hashCode ^
      (icon.fontFamily?.hashCode ?? 0) ^
      (icon.fontPackage?.hashCode ?? 0) ^
      (children == null ? 0 : Object.hashAll(children!));

  // بديل خفيف لـ listEquals بدون import إضافي.
  static bool _listEquals(List<MenuItem>? a, List<MenuItem>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
