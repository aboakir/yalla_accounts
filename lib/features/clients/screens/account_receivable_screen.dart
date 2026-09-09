import 'package:flutter/material.dart';
import '../../finance/screens/accounts_receivable_screen.dart';

/// Legacy route shares the canonical ledger-backed receivables screen.
class AccountReceivableScreen extends StatelessWidget {
  const AccountReceivableScreen({super.key});
  @override
  Widget build(BuildContext context) => const AccountsReceivableScreen();
}
