import 'package:flutter/material.dart';
import 'suppliers_payables_list_screen.dart';

/// Compatibility route uses the same ledger-backed supplier balances.
class SuppliersDebtsScreen extends StatelessWidget {
  const SuppliersDebtsScreen({super.key});
  @override
  Widget build(BuildContext context) => const SupplierPayablesListScreen();
}
