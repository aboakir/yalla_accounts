import 'package:flutter/material.dart';

class YallaMobilePage extends StatelessWidget {
  const YallaMobilePage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) return child;

    return ColoredBox(
      color: const Color(0xFFF7F8FA),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2),
        ),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            final focus = FocusManager.instance.primaryFocus;
            if (focus != null && !focus.hasPrimaryFocus) {
              focus.unfocus();
            }
          },
          child: child,
        ),
      ),
    );
  }
}
