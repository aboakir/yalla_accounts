import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/inventory/models/inventory_item.dart';
import 'package:yalla_accounts/features/inventory/services/inventory_service.dart';

class InventoryEditScreen extends StatefulWidget {
  final InventoryItem? item;

  const InventoryEditScreen({super.key, this.item});

  @override
  State<InventoryEditScreen> createState() => _InventoryEditScreenState();
}

class _InventoryEditScreenState extends State<InventoryEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _categoryController;
  late TextEditingController _quantityController;
  late TextEditingController _unitPriceController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _categoryController = TextEditingController(text: item?.category ?? '');
    _quantityController =
        TextEditingController(text: item?.quantity.toString() ?? '0');
    _unitPriceController =
        TextEditingController(text: item?.unitPrice.toString() ?? '0.0');
    _descriptionController =
        TextEditingController(text: item?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    final item = InventoryItem(
      id: widget.item?.id,
      name: _nameController.text.trim(),
      category: _categoryController.text.trim(),
      quantity: int.tryParse(_quantityController.text.trim()) ?? 0,
      unitPrice: double.tryParse(_unitPriceController.text.trim()) ?? 0.0,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );

    if (widget.item == null) {
      await InventoryService.insertItem(item);
    } else {
      await InventoryService.updateItem(item);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل عنصر في المخزون' : 'إضافة عنصر جديد'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم العنصر'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال اسم العنصر';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'الفئة'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال الفئة';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(labelText: 'الكمية'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || int.tryParse(value.trim()) == null) {
                    return 'يرجى إدخال كمية صحيحة';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _unitPriceController,
                decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || double.tryParse(value.trim()) == null) {
                    return 'يرجى إدخال سعر صحيح';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'الوصف (اختياري)'),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveItem,
                child: Text(isEditing ? 'تحديث' : 'حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
