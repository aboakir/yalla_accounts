// 📁 lib/features/home/widgets/quick_actions_bar.dart
// QuickActionsBar — شريط العمليات السريعة (هاردنيد)

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class QuickActionsBar extends StatelessWidget {
  final List<QuickAction> actions;
  final EdgeInsetsGeometry padding;
  final double itemSize;
  final double spacing;

  const QuickActionsBar({
    super.key,
    required this.actions,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    this.itemSize = 72,
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.08)),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final isWide = c.maxWidth > 680;
          final children = actions
              .map((a) => _ActionButton(
                    icon: a.icon,
                    label: a.label,
                    onTap: a.onTap,
                    size: itemSize,
                  ))
              .toList();

          if (isWide) {
            return AdaptiveRow(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: children
                  .map((w) => Padding(
                        padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                        child: w,
                      ))
                  .toList(),
            );
          }
          return Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: spacing,
            runSpacing: spacing,
            children: children,
          );
        },
      ),
    );
  }
}

class QuickAction {
  final IconData icon;
  final String label;
  final Future<void> Function()? onTap; // يدعم async بهدوء

  const QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Future<void> Function()? onTap;
  final double size;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.size,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _busy = false;

  Future<void> _safeTap() async {
    if (_busy || widget.onTap == null) return;
    setState(() => _busy = true);
    try {
      await widget.onTap!.call();
    } catch (e) {
      if (!mounted) return;
      // حارس هادئ بدون Scaffold.of
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.size * 0.42;

    return Tooltip(
      message: widget.label,
      child: Material(
        // ضروري لرِبل InkWell
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _busy ? null : _safeTap,
          borderRadius: BorderRadius.circular(widget.size),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _busy ? 0.6 : 1.0,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.35),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.18),
                        blurRadius: 14,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(widget.icon,
                          size: iconSize, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: widget.size + 16,
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
