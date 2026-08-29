// 📁 lib/shared/utils/responsive.dart
//
// Utility class for responsive layout detection and breakpoints.
//

import 'package:flutter/material.dart';

/// أنواع الأجهزة المدعومة
enum DeviceType { mobile, tablet, desktop }

/// فئة أدوات عامة لتحديد نوع الجهاز حسب العرض.
class Responsive {
  /// العرض الأقصى للهاتف
  static const double mobileMaxWidth = 600;

  /// العرض الأدنى للتابلت
  static const double tabletMinWidth = 600;

  /// العرض الأدنى للديسكتوب
  static const double desktopMinWidth = 1200;

  /// يُرجع true إذا كان العرض <= حد الموبايل
  static bool isMobile(BuildContext context) {
    final width = _safeWidth(context);
    return width <= mobileMaxWidth;
  }

  /// يُرجع true إذا كان العرض بين التابلت والديسكتوب
  static bool isTablet(BuildContext context) {
    final width = _safeWidth(context);
    return width > tabletMinWidth && width < desktopMinWidth;
  }

  /// يُرجع true إذا كان العرض >= حد الديسكتوب
  static bool isDesktop(BuildContext context) {
    final width = _safeWidth(context);
    return width >= desktopMinWidth;
  }

  /// يُرجع نوع الجهاز الحالي
  static DeviceType deviceType(BuildContext context) {
    final width = _safeWidth(context);
    if (width >= desktopMinWidth) return DeviceType.desktop;
    if (width >= tabletMinWidth) return DeviceType.tablet;
    return DeviceType.mobile;
  }

  /// يختار الواجهة المناسبة تلقائيًا بناءً على نوع الجهاز
  static Widget builder({
    required BuildContext context,
    required Widget mobile,
    Widget? tablet,
    Widget? desktop,
  }) {
    final type = deviceType(context);

    switch (type) {
      case DeviceType.desktop:
        return desktop ?? tablet ?? mobile;
      case DeviceType.tablet:
        return tablet ?? mobile;
      case DeviceType.mobile:
        return mobile;
    }
  }

  /// دالة مساعدة داخلية لقراءة العرض بأمان (في حال عدم وجود MediaQuery)
  static double _safeWidth(BuildContext context) {
    try {
      return MediaQuery.of(context).size.width;
    } catch (_) {
      return mobileMaxWidth; // fallback
    }
  }
}
