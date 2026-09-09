import 'package:flutter/material.dart';

/// A bounded dialog for searchable lazy lists. Avoid AlertDialog's intrinsic
/// sizing, which cannot measure a ListView with an unbounded preferred width.
class VoucherSelectionDialog extends StatelessWidget {
  const VoucherSelectionDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
        child: LayoutBuilder(builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DefaultTextStyle.merge(
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    child: title,
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: content),
                  const SizedBox(height: 8),
                  OverflowBar(
                      alignment: MainAxisAlignment.end, children: actions),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
