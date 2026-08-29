// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/suppliers_screen.dart
//
// شاشة الموردين — قائمة + بحث + فتح كشف حساب المورد + شيكات المورد
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/suppliers/screens/supplier_account_screen.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, Object?>> _rows = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // تحميل الموردين من قاعدة البيانات
  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await DBService.database;

    final q = _searchCtrl.text.trim();
    List<Map<String, Object?>> rows;

    if (q.isEmpty) {
      rows = await db.query('suppliers', orderBy: 'LOWER(name) ASC');
    } else {
      rows = await db.query(
        'suppliers',
        where: 'LOWER(name) LIKE ?',
        whereArgs: ['%${q.toLowerCase()}%'],
        orderBy: 'LOWER(name) ASC',
      );
    }

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  // -----------------------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الموردون')),
      body: Column(
        children: [
          // مربع البحث
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ابحث باسم المورد…',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // حالة التحميل
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            const Expanded(
              child: Center(
                child: Text('لا يوجد موردون', textAlign: TextAlign.center),
              ),
            )

          // قائمة الموردين
          else
            Expanded(
              child: ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (context, i) {
                  final r = _rows[i];

                  final id = (r['id'] ?? '').toString();
                  final name = (r['name'] ?? '').toString();
                  final phone = (r['phone'] ?? '').toString();
                  final address = (r['address'] ?? '').toString();

                  return ListTile(
                    title: Text(name, textAlign: TextAlign.right),
                    subtitle: Text(
                      [
                        if (phone.isNotEmpty) phone,
                        if (address.isNotEmpty) address,
                      ].join(' • '),
                      textAlign: TextAlign.right,
                    ),
                    trailing: const Icon(Icons.chevron_left),

                    // --------------------------- MENU ---------------------------
                    onTap: () {
                      showMenu(
                        context: context,
                        position: const RelativeRect.fromLTRB(200, 200, 0, 0),
                        items: const [
                          PopupMenuItem(
                            value: 'account',
                            child: Text("كشف حساب المورد"),
                          ),
                          PopupMenuItem(
                            value: 'cheques',
                            child: Text("شيكات المورد"),
                          ),
                        ],
                      ).then((value) {
                        if (value == 'account') {
                          SupplierAccountScreen.push(
                            context,
                            supplierId: id,
                            supplierName: name,
                          );
                        }

                        if (value == 'cheques') {
                          Navigator.pushNamed(
                            context,
                            '/suppliers/cheques',
                            arguments: {
                              'supplierPid': id,
                              'supplierName': name,
                            },
                          );
                        }
                      });
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
