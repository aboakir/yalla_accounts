// 📁 lib/features/raw_materials/screens/raw_material_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/raw_materials/providers/raw_material_provider.dart';
import 'package:yalla_accounts/features/raw_materials/screens/raw_material_edit_screen.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class RawMaterialListScreen extends ConsumerWidget {
  const RawMaterialListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final materials = ref.watch(rawMaterialListProvider);

    Widget content = materials.isEmpty
        ? const Center(child: Text('لا توجد مواد خام'))
        : ListView.builder(
            itemCount: materials.length,
            itemBuilder: (context, index) {
              final material = materials[index];
              return ListTile(
                title: Text(material.name),
                subtitle: Text(
                    'المورد: ${material.supplier} - الكمية: ${material.quantity}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RawMaterialEditScreen(
                              material: material,
                              rawMaterial: null,
                            ),
                          ),
                        );
                        if (result == true) {
                          await ref
                              .read(rawMaterialListProvider.notifier)
                              .loadMaterials();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        if (material.id != null) {
                          await ref
                              .read(rawMaterialListProvider.notifier)
                              .deleteMaterial(material.id!);
                          await ref
                              .read(rawMaterialListProvider.notifier)
                              .loadMaterials();
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title:
            const Text('المواد الخام', style: TextStyle(color: Colors.white)),
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
          ? Row(
              children: [
                const SizedBox(
                  width: 260,
                  child: YallaSidebar(currentRoute: '/raw_materials'),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RawMaterialEditScreen(
                  material: null, rawMaterial: null),
            ),
          );
          if (result == true) {
            await ref.read(rawMaterialListProvider.notifier).loadMaterials();
          }
        },
        backgroundColor: AppColors.primary,
        tooltip: 'إضافة مادة خام',
        child: const Icon(Icons.add),
      ),
    );
  }
}
