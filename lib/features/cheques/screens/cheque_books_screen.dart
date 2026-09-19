import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_book_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class ChequeBooksScreen extends StatefulWidget {
  const ChequeBooksScreen({super.key});

  @override
  State<ChequeBooksScreen> createState() => _ChequeBooksScreenState();
}

class _ChequeBooksScreenState extends State<ChequeBooksScreen> {
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ChequeBookService.list();
  }

  Future<void> _create() async {
    final db = await DBService.database;
    final banks = await db.query(
      'accounts',
      columns: const ['id', 'code', 'name'],
      where: "code='1010' OR code LIKE '1010.%'",
      orderBy: 'code',
    );
    if (!mounted) return;
    if (banks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد حساب بنكي متاح.')),
      );
      return;
    }

    int? bankId = (banks.first['id'] as num).toInt();
    final book = TextEditingController();
    final first = TextEditingController();
    final last = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AdaptiveAlertDialog(
          title: const Text('فتح دفتر شيكات'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: bankId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الحساب البنكي'),
                  items: [
                    for (final bank in banks)
                      DropdownMenuItem(
                        value: (bank['id'] as num).toInt(),
                        child: Text('${bank['code']} — ${bank['name']}'),
                      ),
                  ],
                  onChanged: (v) => setD(() => bankId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: book,
                  decoration: const InputDecoration(labelText: 'رقم الدفتر'),
                ),
                const SizedBox(height: 10),
                AdaptiveRow(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: first,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'أول رقم شيك'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: last,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'آخر رقم شيك'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      book.dispose();
      first.dispose();
      last.dispose();
      return;
    }
    try {
      await ChequeBookService.create(
        bankAccountId: bankId!,
        bookNumber: book.text.trim(),
        firstChequeNumber: int.parse(first.text.trim()),
        lastChequeNumber: int.parse(last.text.trim()),
      );
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.message(e))),
      );
    } finally {
      book.dispose();
      first.dispose();
      last.dispose();
    }
  }

  Future<void> _close(String id) async {
    try {
      await ChequeBookService.close(id);
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.message(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفاتر الشيكات'),
        actions: [
          IconButton(
            onPressed: _create,
            icon: const Icon(Icons.add),
            tooltip: 'فتح دفتر جديد',
          ),
        ],
      ),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequeBooks),
      body: AdaptiveRow(
        children: [
          if (desktop) const YallaSidebar(currentRoute: AppRoutes.chequeBooks),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('تعذر تحميل الدفاتر: ${snap.error}'));
                }
                final rows = snap.data ?? const <Map<String, Object?>>[];
                if (rows.isEmpty) {
                  return Center(
                    child: FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.menu_book),
                      label: const Text('فتح أول دفتر شيكات'),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final row = rows[i];
                    final status = row['status']?.toString() ?? '';
                    return Card(
                      child: ListTile(
                        title: Text(
                            'دفتر ${row['book_number']} — ${row['bank_account_name']}'),
                        subtitle: Text(
                          'النطاق ${row['first_cheque_number']}–${row['last_cheque_number']} • '
                          'التالي ${row['next_available_number']} • مستخدم ${row['used_count']}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(label: Text(status)),
                            if (status == 'OPEN')
                              TextButton(
                                onPressed: () => _close(row['id'].toString()),
                                child: const Text('إغلاق'),
                              ),
                          ],
                        ),
                      ),
                    );
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
