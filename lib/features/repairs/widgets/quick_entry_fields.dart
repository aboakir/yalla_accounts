import 'package:flutter/material.dart';

/// Owns quick-entry controllers for the entire dialog lifetime, including the
/// reverse route transition after Navigator.pop completes its result future.
class QuickEntryFields extends StatefulWidget {
  const QuickEntryFields(
      {super.key, required this.count, required this.builder});
  final int count;
  final Widget Function(List<TextEditingController>) builder;

  @override
  State<QuickEntryFields> createState() => _QuickEntryFieldsState();
}

class _QuickEntryFieldsState extends State<QuickEntryFields> {
  late final controllers =
      List.generate(widget.count, (_) => TextEditingController());

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(controllers);
}
