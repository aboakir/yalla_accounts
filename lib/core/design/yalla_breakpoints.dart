import 'package:flutter/widgets.dart';

enum YallaDeviceClass { phone, tablet, desktop }

abstract final class YallaBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;

  static YallaDeviceClass deviceClassFor(double width) {
    if (width < tablet) {
      return YallaDeviceClass.phone;
    }
    if (width < desktop) {
      return YallaDeviceClass.tablet;
    }
    return YallaDeviceClass.desktop;
  }

  static YallaDeviceClass of(BuildContext context) {
    return deviceClassFor(MediaQuery.sizeOf(context).width);
  }

  static bool isPhone(BuildContext context) {
    return of(context) == YallaDeviceClass.phone;
  }

  static bool isTablet(BuildContext context) {
    return of(context) == YallaDeviceClass.tablet;
  }

  static bool isDesktop(BuildContext context) {
    return of(context) == YallaDeviceClass.desktop;
  }
}

abstract final class YallaPageInsets {
  static EdgeInsets forWidth(double width) {
    return switch (YallaBreakpoints.deviceClassFor(width)) {
      YallaDeviceClass.phone => const EdgeInsets.symmetric(horizontal: 16),
      YallaDeviceClass.tablet => const EdgeInsets.symmetric(horizontal: 24),
      YallaDeviceClass.desktop => const EdgeInsets.symmetric(horizontal: 32),
    };
  }

  static EdgeInsets of(BuildContext context) {
    return forWidth(MediaQuery.sizeOf(context).width);
  }
}
