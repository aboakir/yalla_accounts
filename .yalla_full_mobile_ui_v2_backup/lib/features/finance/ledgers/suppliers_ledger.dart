import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/finance/models/supplier_model.dart';
import 'package:yalla_accounts/features/finance/services/supplier_service.dart';

class SuppliersLedgerScreen extends StatefulWidget {
  const SuppliersLedgerScreen({super.key});

  @override
  State<SuppliersLedgerScreen> createState() => _SuppliersLedgerScreenState();
}

class _SuppliersLedgerScreenState extends State<SuppliersLedgerScreen> {
  List<SupplierModel> suppliers = [];

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final data = await SupplierService.getAllSuppliers();
    setState(() => suppliers = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دفتر الموردين')),
      body: ListView.separated(
        itemCount: suppliers.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final s = suppliers[index];
          return ListTile(
            title: Text(s.name),
            subtitle: Text('${s.phone} | ${s.address}'),
          );
        },
      ),
    );
  }
}
