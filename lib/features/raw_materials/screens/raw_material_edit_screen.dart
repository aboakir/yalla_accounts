// 📁 lib/features/raw_materials/screens/raw_material_edit_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/raw_materials/models/raw_material.dart';
import 'package:yalla_accounts/features/raw_materials/providers/raw_material_provider.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RawMaterialEditScreen extends ConsumerStatefulWidget {
  final RawMaterial? material;

  const RawMaterialEditScreen({super.key, this.material, required rawMaterial});

  @override
  ConsumerState<RawMaterialEditScreen> createState() =>
      _RawMaterialEditScreenState();
}

class _RawMaterialEditScreenState extends ConsumerState<RawMaterialEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _supplierController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    final material = widget.material;
    _nameController = TextEditingController(text: material?.name ?? '');
    _supplierController = TextEditingController(text: material?.supplier ?? '');
    _quantityController =
        TextEditingController(text: material?.quantity.toString() ?? '0');
    _unitPriceController =
        TextEditingController(text: material?.unitPrice.toString() ?? '0.0');
    _descriptionController =
        TextEditingController(text: material?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _supplierController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveMaterial() async {
    if (!_formKey.currentState!.validate()) return;

    final material = RawMaterial(
      id: widget.material?.id,
      name: _nameController.text.trim(),
      supplier: _supplierController.text.trim(),
      quantity: int.tryParse(_quantityController.text.trim()) ?? 0,
      unitPrice: double.tryParse(_unitPriceController.text.trim()) ?? 0.0,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );

    if (widget.material == null) {
      await ref.read(rawMaterialListProvider.notifier).addMaterial(material);
    } else {
      await ref.read(rawMaterialListProvider.notifier).updateMaterial(material);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final isEditing = widget.material != null;

    Widget formContent = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'اسم المادة'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال اسم المادة';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _supplierController,
              decoration: const InputDecoration(labelText: 'المورد'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال اسم المورد';
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
              onPressed: _saveMaterial,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(isEditing ? 'تحديث' : 'حفظ'),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          isEditing ? 'تعديل مادة خام' : 'إضافة مادة خام',
          style: const TextStyle(color: Colors.white),
        ),
        leading: isDesktop
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'فتح القائمة',
                ),
              ),
      ),
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/raw_materials'),
            ),
      body: isDesktop
          ? AdaptiveRow(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/raw_materials'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: formContent),
              ],
            )
          : formContent,
    );
  }
}
