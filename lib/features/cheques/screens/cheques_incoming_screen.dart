import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/screens/cheques_incoming_screen.dart
//
// ChequesIncomingScreen — FINAL C (ENDORSEMENT-READY)
// -----------------------------------------------------------------------------
// • عرض الشيكات الواردة فقط (incoming)
// • زر "تظهير" يعمل مع chequeProvider.notifier.endorseCheque()
// • Dialog اختيار مورّد + تاريخ
// • تحديث مباشر للقائمة فور نجاح التظهير
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import '../models/cheque.dart';
import '../providers/cheque_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class ChequesIncomingScreen extends ConsumerStatefulWidget {
  const ChequesIncomingScreen({super.key});

  @override
  ConsumerState<ChequesIncomingScreen> createState() =>
      _ChequesIncomingScreenState();
}

class _ChequesIncomingScreenState extends ConsumerState<ChequesIncomingScreen> {
  Future<List<Map<String, dynamic>>> _load() async {
    final db = await DBService.database;
    return await db.query(
      'cheques',
      where: "cheque_type = ? AND is_endorsed = 0",
      whereArgs: ['incoming'],
      orderBy: "due_date ASC",
    );
  }

  String _fmtDate(String? raw) {
    if (raw == null) return "";
    final d = DateTime.tryParse(raw);
    return d == null ? raw : d.toIso8601String().split("T").first;
  }

  String _fmtAmount(dynamic raw) {
    if (raw == null) return "";
    final f = NumberFormat('#,##0.##', 'ar');
    if (raw is num) return f.format(raw);
    final v = double.tryParse(raw.toString().replaceAll(",", ""));
    return v == null ? raw.toString() : f.format(v);
  }

  // ---------------------------------------------------------------------------
  // اختيار المورد + التاريخ
  // ---------------------------------------------------------------------------
  Future<void> _showEndorseDialog(Map<String, dynamic> r, Cheque cheque) async {
    final suppliers = await _loadSuppliers();
    if (!mounted) return;

    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("لا يوجد موردين لإتمام عملية التظهير"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    /// نحدد قيمة ابتدائية مضمونة (أول مورد)
    String selectedSupplier =
        suppliers.first['pid'] ?? suppliers.first['id'].toString();
    DateTime endorsementDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AdaptiveAlertDialog(
              title: const Text("تظهير الشيك", textAlign: TextAlign.center),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration:
                          const InputDecoration(labelText: "اختر المورد"),
                      value: selectedSupplier,
                      isExpanded: true,
                      items: suppliers.map((s) {
                        final pid = s['pid']?.toString() ?? s['id'].toString();
                        return DropdownMenuItem(
                          value: pid,
                          child: Text(s['name']),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setStateDialog(() {
                          selectedSupplier = v;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    AdaptiveRow(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("تاريخ التظهير:"),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              initialDate: endorsementDate,
                            );
                            if (picked != null) {
                              setStateDialog(() {
                                endorsementDate = picked;
                              });
                            }
                          },
                          child: Text(
                            endorsementDate.toIso8601String().split("T").first,
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text("إلغاء"),
                  onPressed: () => Navigator.pop(ctx),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text("تظهير"),
                  onPressed: () async {
                    Navigator.pop(ctx);

                    await _endorseCheque(
                      cheque: cheque,
                      supplierPid: selectedSupplier,
                      endorsementDate: endorsementDate,
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadSuppliers() async {
    final db = await DBService.database;
    return await db.rawQuery("""
SELECT 
  COALESCE(pid, id, '') AS pid,
  name
FROM suppliers
ORDER BY name ASC
""");
  }

  // ---------------------------------------------------------------------------
  // تنفيذ عملية التظهير الفعلية عبر المزود
  // ---------------------------------------------------------------------------
  Future<void> _endorseCheque({
    required Cheque cheque,
    required String supplierPid,
    required DateTime endorsementDate,
  }) async {
    try {
      final notifier = ref.read(chequeProvider.notifier);

      await notifier.endorseCheque(
        cheque: cheque,
        supplierPid: supplierPid,
        endorsementDate: endorsementDate,
      );
      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم تظهير الشيك بنجاح"),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ أثناء التظهير: ${UserFacingError.message(e)}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const YallaAppBar(
        workshopName: "Yallah Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop
          ? null
          : const YallaSidebar(currentRoute: '/cheques/incoming'),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(currentRoute: '/cheques/incoming'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _load(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rows = snap.data ?? [];
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                      "لا توجد شيكات واردة حالياً",
                      style: TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                // تحويل Map → Cheque Model
                final cheques = rows.map((m) => Cheque.fromMap(m)).toList();

                if (!isDesktop) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: cheques.length,
                    itemBuilder: (ctx, i) {
                      final c = cheques[i];
                      return Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "رقم الشيك: ${c.chequeNo}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text("المحرر: ${c.drawerName}"),
                              Text("البنك: ${c.bankName}/${c.bankBranch}"),
                              Text(
                                  "المبلغ: ${_fmtAmount(c.amount)} ${c.currency}"),
                              Text(
                                  "الاستحقاق: ${_fmtDate(c.dueDate.toIso8601String())}"),
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: () => _showEndorseDialog(rows[i], c),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary),
                                child: const Text("تظهير"),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }

                // DESKTOP TABLE
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  scrollDirection: Axis.horizontal,
                  child: AdaptiveDataTable(
                    columns: const [
                      DataColumn(label: Text("رقم الشيك")),
                      DataColumn(label: Text("اسم المحرر")),
                      DataColumn(label: Text("البنك")),
                      DataColumn(label: Text("الفرع")),
                      DataColumn(label: Text("المبلغ")),
                      DataColumn(label: Text("العملة")),
                      DataColumn(label: Text("الاستحقاق")),
                      DataColumn(label: Text("إجراء")),
                    ],
                    rows: List.generate(cheques.length, (i) {
                      final c = cheques[i];
                      return DataRow(
                        cells: [
                          DataCell(Text(c.chequeNo)),
                          DataCell(Text(c.drawerName)),
                          DataCell(Text(c.bankName)),
                          DataCell(Text(c.bankBranch)),
                          DataCell(Text(_fmtAmount(c.amount))),
                          DataCell(Text(c.currency)),
                          DataCell(Text(_fmtDate(c.dueDate.toIso8601String()))),
                          DataCell(
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary),
                              onPressed: () => _showEndorseDialog(rows[i], c),
                              child: const Text("تظهير"),
                            ),
                          ),
                        ],
                      );
                    }),
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
