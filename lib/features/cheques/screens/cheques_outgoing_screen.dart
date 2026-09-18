// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/screens/cheques_outgoing_screen.dart
//
// ChequesOutgoingScreen — النسخة النهائية (OUT + Endorsed)
// -----------------------------------------------------------------------------
// • عرض جميع OUT + الشيكات المظهّرة تلقائيًا
// • يعتمد على chequeProvider (live updated)
// • تصميم احترافي للموبايل + الديسكتوب
// • يعرض بيانات التظهير: isEndorsed + endorsedAt + supplierPid
// • فتح تفاصيل / تعديل / حذف
// • زر إضافة شيك OUT جديد
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import '../models/cheque.dart';
import '../providers/cheque_provider.dart';
import 'cheque_add_screen.dart';
import 'cheque_details_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ChequesOutgoingScreen extends ConsumerWidget {
  const ChequesOutgoingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);

    // جميع الشيكات (Live)
    final cheques = ref.watch(chequeProvider);

    // فلترة: فقط OUT (يشمل المظهّرة لأنها أصبحت OUT)
    final outList =
        cheques.where((c) => c.chequeType == ChequeType.outgoing).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const YallaAppBar(
        workshopName: "Yallah Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop
          ? null
          : const YallaSidebar(currentRoute: '/cheques/outgoing'),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(currentRoute: '/cheques/outgoing'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "الشيكات الصادرة / المظهّرة",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: outList.isEmpty
                        ? const Center(
                            child: Text(
                              "لا توجد شيكات صادرة حالياً",
                              style: TextStyle(fontSize: 18),
                            ),
                          )
                        : isDesktop
                            ? _buildTable(context, ref, outList)
                            : _buildCards(context, ref, outList),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ChequeAddScreen(),
            ),
          );
          ref.invalidate(chequeProvider);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DESKTOP TABLE
  // ---------------------------------------------------------------------------
  Widget _buildTable(BuildContext context, WidgetRef ref, List<Cheque> list) {
    final df = DateFormat('yyyy-MM-dd');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columnSpacing: 22,
        headingRowColor:
            MaterialStateColor.resolveWith((_) => AppColors.primary),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        columns: const [
          DataColumn(label: Text("رقم الشيك")),
          DataColumn(label: Text("المستفيد")),
          DataColumn(label: Text("البنك")),
          DataColumn(label: Text("الفرع")),
          DataColumn(label: Text("القيمة")),
          DataColumn(label: Text("العملة")),
          DataColumn(label: Text("الإصدار")),
          DataColumn(label: Text("الاستحقاق")),
          DataColumn(label: Text("التظهير")),
          DataColumn(label: Text("إجراءات")),
        ],
        rows: list.map((c) {
          return DataRow(
            cells: [
              DataCell(Text(c.chequeNo)),
              DataCell(Text(c.supplierPid ?? c.drawerName)),
              DataCell(Text(c.bankName)),
              DataCell(Text(c.bankBranch)),
              DataCell(Text("${c.amount}")),
              DataCell(Text(c.currency)),
              DataCell(Text(df.format(c.issueDate))),
              DataCell(Text(df.format(c.dueDate))),
              DataCell(_endorsementStatusCell(c)),
              DataCell(
                AdaptiveRow(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      onPressed: () => _openDetails(context, c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openEdit(context, c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _delete(context, ref, c),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE CARDS
  // ---------------------------------------------------------------------------
  Widget _buildCards(BuildContext context, WidgetRef ref, List<Cheque> list) {
    final df = DateFormat('yyyy-MM-dd');

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final c = list[i];

        return Card(
          margin: const EdgeInsets.only(bottom: 18),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "رقم الشيك: ${c.chequeNo}",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text("المستفيد: ${c.supplierPid ?? c.drawerName}"),
                Text("القيمة: ${c.amount} ${c.currency}"),
                Text("البنك: ${c.bankName} / ${c.bankBranch}"),
                Text("الإصدار: ${df.format(c.issueDate)}"),
                Text("الاستحقاق: ${df.format(c.dueDate)}"),
                const SizedBox(height: 6),
                _endorsementStatusCell(c),
                const SizedBox(height: 12),
                AdaptiveRow(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      onPressed: () => _openDetails(context, c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openEdit(context, c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _delete(context, ref, c),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ENDORSEMENT STATUS
  // ---------------------------------------------------------------------------
  Widget _endorsementStatusCell(Cheque c) {
    if (c.isEndorsed == 1) {
      final date = (c.endorsedAt ?? "").split("T").first;
      return Text(
        "مظهّر — $date",
        style: const TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    return const Text(
      "غير مظهّر",
      style: TextStyle(color: Colors.grey),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------
  void _openDetails(BuildContext context, Cheque c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChequeDetailsScreen(cheque: c)),
    );
  }

  void _openEdit(BuildContext context, Cheque c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChequeAddScreen(editCheque: c)),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Cheque c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text("حذف الشيك"),
        content: const Text("سيتم حذف الشيك نهائيًا. هل أنت متأكد؟"),
        actions: [
          TextButton(
            child: const Text("إلغاء"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("حذف"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(chequeProvider.notifier).deleteCheque(c.id!);
    }
  }
}
