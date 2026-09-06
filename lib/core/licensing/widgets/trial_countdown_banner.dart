import 'package:flutter/material.dart';

/// Legacy widget retained for source compatibility.
///
/// P18 removed locally calculated trial time. Server-signed commercial state
/// is surfaced by the subscription/licensing screens instead.
class TrialCountdownBanner extends StatelessWidget {
  const TrialCountdownBanner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
