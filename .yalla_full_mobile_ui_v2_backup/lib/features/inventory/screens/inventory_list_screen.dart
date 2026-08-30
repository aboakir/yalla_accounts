import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/inventory/models/inventory_item.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_service.dart';
import 'inventory_edit_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  List<InventoryItem> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final data = await InventoryService.getAllItems();
    setState(() {
      items = data;
      loading = false;
    });
  }

  void _navigateToAdd() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InventoryEditScreen()),
    );
    if (result == true) {
      _loadItems();
    }
  }

  void _navigateToEdit(InventoryItem item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InventoryEditScreen(item: item)),
    );
    if (result == true) {
      _loadItems();
    }
  }

  void _deleteItem(int id) async {
    await InventoryService.deleteItem(id);
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المخزون'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAdd,
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('لا يوجد عناصر في المخزون'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Text(
                          'الكمية: ${item.quantity} - السعر: ${item.unitPrice}'),
                      trailing: AdaptiveRow(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _navigateToEdit(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteItem(item.id!),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
