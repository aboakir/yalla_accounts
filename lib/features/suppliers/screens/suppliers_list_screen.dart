// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/supplier_list_screen.dart
// شاشة قائمة الموردين — النسخة النهائية Yalla Accounts
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

import '../models/supplier.dart';
import '../providers/supplier_provider.dart';
import 'supplier_form_screen.dart';
import '../../../core/constants/colors.dart';

class SupplierListScreen extends ConsumerStatefulWidget {
  const SupplierListScreen({super.key});

  @override
  ConsumerState<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends ConsumerState<SupplierListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(filteredSuppliersProvider(_search));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;

          return Scaffold(
            backgroundColor: Colors.white,

            // ===== AppBar مع زر الرجوع فقط على الهاتف =====
            appBar: AppBar(
              backgroundColor: AppColors.primary,
              title:
                  const Text("الموردين", style: TextStyle(color: Colors.white)),
              iconTheme: const IconThemeData(color: Colors.white),
              leading: isDesktop
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
            ),

            // ===== القائمة الجانبية ثابتة على الشاشات الكبيرة =====
            drawer: isDesktop ? null : const Drawer(child: YallaSidebar()),
            body: Row(
              children: [
                if (isDesktop)
                  const SizedBox(
                    width: 260,
                    child: YallaSidebar(),
                  ),

                // ===== محتوى الصفحة كما هو =====
                Expanded(
                  child: Column(
                    children: [
                      // مربع البحث
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: "بحث عن مورد",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),

                      // قائمة الموردين
                      Expanded(
                        child: suppliers.isEmpty
                            ? const Center(
                                child: Text("لا يوجد موردين",
                                    style: TextStyle(fontSize: 16)),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: suppliers.length,
                                itemBuilder: (_, i) =>
                                    _supplierTile(suppliers[i]),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            floatingActionButton: FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () async {
                final ok = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SupplierFormScreen(),
                  ),
                );
                if (ok == true) {
                  ref.invalidate(suppliersNotifierProvider);
                }
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  // ============================================================================
  // عنصر المورد في القائمة
  // ============================================================================
  Widget _supplierTile(Supplier s) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      elevation: 1.5,
      child: ListTile(
        title: Text(
          s.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.phone.isNotEmpty) Text("هاتف: ${s.phone}"),
            if (s.address.isNotEmpty) Text("العنوان: ${s.address}"),
            Text("رقم المورد: ${s.pid}"),
          ],
        ),

        // --------------------------------------------------------------
        // زر كشف المورد
        // --------------------------------------------------------------
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == "edit") {
              // تعديل المورد
              final ok = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SupplierFormScreen(supplier: s),
                ),
              );
              if (ok == true) {
                ref.invalidate(suppliersNotifierProvider);
              }
            }

            if (value == "account") {
              // شاشة كشف حساب المورد (سيتم ربطها لاحقًا)
              // Navigator.pushNamed(context, '/suppliers/account', arguments: s);
            }

            if (value == "payables") {
              // صفحة ذمم المورد (سيتم إضافتها لاحقًا)
              // Navigator.pushNamed(context, '/suppliers/payables', arguments: s);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: "edit",
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text("تعديل"),
                ],
              ),
            ),
            const PopupMenuItem(
              value: "account",
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet, size: 20),
                  SizedBox(width: 8),
                  Text("كشف الحساب"),
                ],
              ),
            ),
            const PopupMenuItem(
              value: "payables",
              child: Row(
                children: [
                  Icon(Icons.receipt_long, size: 20),
                  SizedBox(width: 8),
                  Text("ذمم المورد"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
