import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/reports/pages/ar_aging_page.dart';

/// P12 canonical AR aging route.
///
/// The previous screen recalculated balances from invoices-payments. P10 made
/// GL the source of truth, so P12 routes aging exclusively through the GL/FIFO
/// provider used by [ARAgingPage].
class ARAgingScreen extends StatelessWidget {
  const ARAgingScreen({super.key});

  @override
  Widget build(BuildContext context) => const ARAgingPage();
}
