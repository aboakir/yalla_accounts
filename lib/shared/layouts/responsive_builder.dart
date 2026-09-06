// lib/shared/layouts/responsive_builder.dart
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/design/yalla_breakpoints.dart' as design;

/// تصنيف أنواع الأجهزة وفق العرض.
enum DeviceType { mobile, tablet, desktop }

/// نقاط توقف قابلة للتخصيص.
/// - أقل من tablet ⇒ Mobile
/// - من tablet إلى أقل من desktop ⇒ Tablet
/// - desktop فأعلى ⇒ Desktop
class Breakpoints {
  final double tablet; // الحد الأدنى لظهور الـ Tablet
  final double desktop; // الحد الأدنى لظهور الـ Desktop

  const Breakpoints({
    this.tablet = design.YallaBreakpoints.tablet,
    this.desktop = design.YallaBreakpoints.desktop,
  }) : assert(tablet > 0 && desktop > tablet,
            'Breakpoints must satisfy: 0 < tablet < desktop');

  DeviceType resolveFromSize(Size size, {bool useShortestSide = false}) {
    final width = useShortestSide ? size.shortestSide : size.width;
    if (width >= desktop) return DeviceType.desktop;
    if (width >= tablet) return DeviceType.tablet;
    return DeviceType.mobile;
  }
}

/// Builder موحّد يأخذ نوع الجهاز.
typedef ResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  DeviceType device,
);

/// ResponsiveBuilder محسّن:
/// - إمّا تمرّر builder موحّد (الأكثر مرونة)
/// - أو تمرّر Widgets منفصلة لكل جهاز (mobile / tablet / desktop)
/// - لديك خيار useShortestSide لجعل القرار أقل حساسية لتغيّر الاتجاه.
/// - يمكنك تخصيص Breakpoints.
class ResponsiveBuilder extends StatelessWidget {
  final ResponsiveWidgetBuilder? builder;

  /// Widgets لكل جهاز (إن لم تستخدم builder).
  final Widget? mobile;
  final Widget? tablet;
  final Widget? desktop;

  /// ويدجت احتياطية عند غياب الواجهات الخاصة (fallback).
  final Widget? fallback;

  /// نقاط التوقف المستخدَمة.
  final Breakpoints breakpoints;

  /// هل نعتمد أقصر ضلع بدلاً من العرض؟ (مفيد للـ Tablets)
  final bool useShortestSide;

  const ResponsiveBuilder({
    super.key,
    this.builder,
    this.mobile,
    this.tablet,
    this.desktop,
    this.fallback,
    this.breakpoints = const Breakpoints(),
    this.useShortestSide = false,
  }) : assert(
          builder != null || mobile != null,
          'Provide either a builder or at least a mobile widget.',
        );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final device = breakpoints.resolveFromSize(
      mq.size,
      useShortestSide: useShortestSide,
    );

    if (builder != null) {
      return builder!(context, device);
    }

    // اختيار تلقائي مع Fallbacks منظم.
    switch (device) {
      case DeviceType.desktop:
        return desktop ?? tablet ?? mobile ?? fallback ?? const _Empty();
      case DeviceType.tablet:
        return tablet ?? mobile ?? fallback ?? const _Empty();
      case DeviceType.mobile:
        return mobile ?? fallback ?? const _Empty();
    }
  }
}

/// ويدجت لإظهار/إخفاء عنصر حسب نوع الجهاز.
/// - استخدم one-of: [visibleOn] أو [hiddenOn].
class ResponsiveVisibility extends StatelessWidget {
  final Widget child;
  final List<DeviceType>? visibleOn;
  final List<DeviceType>? hiddenOn;
  final Breakpoints breakpoints;
  final bool useShortestSide;
  final Widget replacement;

  const ResponsiveVisibility({
    super.key,
    required this.child,
    this.visibleOn,
    this.hiddenOn,
    this.breakpoints = const Breakpoints(),
    this.useShortestSide = false,
    this.replacement = const SizedBox.shrink(),
  }) : assert(
          (visibleOn == null) ^ (hiddenOn == null),
          'Provide exactly one of visibleOn or hiddenOn.',
        );

  @override
  Widget build(BuildContext context) {
    final device = breakpoints.resolveFromSize(
      MediaQuery.of(context).size,
      useShortestSide: useShortestSide,
    );

    final shouldShow = visibleOn != null
        ? visibleOn!.contains(device)
        : !(hiddenOn!.contains(device));

    return shouldShow ? child : replacement;
  }
}

/// امتدادات سريعة على BuildContext.
extension ResponsiveContextX on BuildContext {
  DeviceType deviceType({
    Breakpoints breakpoints = const Breakpoints(),
    bool useShortestSide = false,
  }) {
    final size = MediaQuery.of(this).size;
    return breakpoints.resolveFromSize(size, useShortestSide: useShortestSide);
  }

  bool get isMobile => deviceType() == DeviceType.mobile;
  bool get isTablet => deviceType() == DeviceType.tablet;
  bool get isDesktop => deviceType() == DeviceType.desktop;
}

/// عنصر فارغ افتراضي.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
