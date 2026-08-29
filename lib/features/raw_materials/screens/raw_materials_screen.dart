// 📁 lib/features/raw_materials/screens/raw_materials_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class RawMaterialsScreen extends StatefulWidget {
  const RawMaterialsScreen({super.key});

  @override
  State<RawMaterialsScreen> createState() => _RawMaterialsScreenState();
}

class _RawMaterialsScreenState extends State<RawMaterialsScreen> {
  List<Map<String, dynamic>> materials = [
    {'name': 'حديد', 'supplier': 'المورد الأول', 'quantity': 100},
    {'name': 'خشب', 'supplier': 'المورد الثاني', 'quantity': 50},
    {'name': 'بلاستيك', 'supplier': 'المورد الثالث', 'quantity': 200},
  ];

  void _addNewMaterial() {
    setState(() {
      materials.add({
        'name': 'مادة جديدة',
        'supplier': 'مورد جديد',
        'quantity': 10,
      });
    });
  }

  void _deleteMaterial(int index) {
    setState(() {
      materials.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = Responsive.isDesktop(context);

    Widget bodyContent = materials.isEmpty
        ? const Center(
            child: Text(
              'لا توجد مواد خام',
              style: TextStyle(fontSize: 18),
            ),
          )
        : ListView.builder(
            itemCount: materials.length,
            itemBuilder: (context, index) {
              final material = materials[index];
              return ListTile(
                title: Text(material['name']),
                subtitle: Text(
                    'المورد: ${material['supplier']} - الكمية: ${material['quantity']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteMaterial(index),
                  tooltip: 'حذف المادة',
                ),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('المواد الخام'),
        leading: isLargeScreen
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'فتح القائمة',
                ),
              ),
      ),

      // على الموبايل نستخدم drawer بداخل Scaffold
      drawer: isLargeScreen
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/raw_materials'),
            ),

      body: isLargeScreen
          ? Row(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/raw_materials'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: bodyContent),
              ],
            )
          : bodyContent,

      floatingActionButton: FloatingActionButton(
        onPressed: _addNewMaterial,
        tooltip: 'إضافة مادة خام',
        child: const Icon(Icons.add),
      ),
    );
  }
}
