// -----------------------------------------------------------------------------
// 📁 lib/features/suppliers/screens/suppliers_screen.dart
//
// شاشة الموردين — قائمة + بحث + فتح كشف حساب المورد + شيكات المورد
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/suppliers/screens/supplier_account_screen.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

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
              inputFormatters: const [YallaDigitNormalizer()],
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

                  Future<void> openActions() async {
                    final value = await showModalBottomSheet<String>(
                      context: context,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (sheetContext) => Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: const Text('كشف حساب المورد'),
                              onTap: () =>
                                  Navigator.pop(sheetContext, 'account'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.payments_outlined),
                              title: const Text('شيكات المورد'),
                              onTap: () =>
                                  Navigator.pop(sheetContext, 'cheques'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!mounted || value == null) return;
                    if (value == 'account') {
                      SupplierAccountScreen.push(
                        context,
                        supplierId: id,
                        supplierName: name,
                      );
                    } else if (value == 'cheques') {
                      Navigator.pushNamed(
                        context,
                        '/suppliers/cheques',
                        arguments: {
                          'supplierPid': id,
                          'supplierName': name,
                        },
                      );
                    }
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: openActions,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              child: Text(
                                name.trim().isEmpty ? 'م' : name.trim()[0],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    name,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (phone.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      phone,
                                      textAlign: TextAlign.right,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                  if (address.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      address,
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.more_horiz),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
