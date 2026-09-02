import 'package:flutter/material.dart';

import 'yalla_design_tokens.dart';

class YallaSurfaceCard extends StatelessWidget {
  const YallaSurfaceCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(YallaSpacing.md),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: YallaColors.surface,
        border: Border.all(color: YallaColors.border),
        borderRadius: BorderRadius.circular(YallaRadii.card),
      ),
      child: child,
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YallaRadii.card),
        child: card,
      ),
    );
  }
}

class YallaPrimaryButton extends StatelessWidget {
  const YallaPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.isBusy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final content = isBusy
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon),
                const SizedBox(width: YallaSpacing.xs),
              ],
              Text(label),
            ],
          );

    return SizedBox(
      width: double.infinity,
      height: YallaDimensions.primaryButtonHeight,
      child: ElevatedButton(
        onPressed: isBusy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: YallaColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: YallaColors.border,
          disabledForegroundColor: YallaColors.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YallaRadii.control),
          ),
          elevation: 0,
        ),
        child: content,
      ),
    );
  }
}

class YallaSectionHeader extends StatelessWidget {
  const YallaSectionHeader({
    required this.title,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: YallaColors.text,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

enum YallaStatusTone { success, danger, warning, info, neutral }

class YallaStatusChip extends StatelessWidget {
  const YallaStatusChip({
    required this.label,
    super.key,
    this.tone = YallaStatusTone.neutral,
  });

  final String label;
  final YallaStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      YallaStatusTone.success => (
          YallaColors.successSurface,
          YallaColors.brandDark
        ),
      YallaStatusTone.danger => (YallaColors.dangerSurface, YallaColors.danger),
      YallaStatusTone.warning => (
          YallaColors.warningSurface,
          YallaColors.warning
        ),
      YallaStatusTone.info => (YallaColors.infoSurface, YallaColors.info),
      YallaStatusTone.neutral => (YallaColors.canvas, YallaColors.textMuted),
    };

    return Container(
      constraints: const BoxConstraints(
        minHeight: YallaDimensions.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: YallaSpacing.sm,
        vertical: YallaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(YallaRadii.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
