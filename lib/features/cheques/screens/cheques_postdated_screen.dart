// 📁 lib/features/cheques/screens/cheques_postdated_screen.dart
//
// ChequesPostdatedScreen — الشيكات الآجلة (POSTDATED)
// ----------------------------------------------------
// - داتا حقيقية من جدول cheques.
// - فلترة status = 'POSTDATED' (كودياً: postdated).
// - بدون RTL (نستخدم TextAlign.right فقط).
// - Sidebar ثابت للديسكتوب، Drawer للموبايل.
// - تصميم متناسق مع Incoming / Outgoing / Dashboard.
//

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class ChequesPostdatedScreen extends ConsumerWidget {
  const ChequesPostdatedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      appBar: const YallaAppBar(
        workshopName: "Yalla Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop
          ? null
          : const YallaSidebar(currentRoute: '/cheques/postdated'),
      body: Row(
        children: [
          if (isDesktop) const YallaSidebar(currentRoute: '/cheques/postdated'),
          const Expanded(child: _PostdatedBody()),
        ],
      ),
    );
  }
}

class _PostdatedBody extends StatelessWidget {
  const _PostdatedBody();

  Future<List<Map<String, dynamic>>> _load() async {
    final db = await DBService.database;
    return await db.rawQuery("SELECT * FROM cheques");
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return "";
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw)
          .toIso8601String()
          .split("T")
          .first;
    }
    if (raw is String) {
      final d = DateTime.tryParse(raw);
      return d == null ? raw : d.toIso8601String().split("T").first;
    }
    return raw.toString();
  }

  String _fmtAmount(dynamic raw) {
    if (raw == null) return "";
    final f = NumberFormat('#,##0.##', 'ar');
    if (raw is num) return f.format(raw);
    final v = double.tryParse(raw.toString().replaceAll(',', ''));
    return v == null ? raw.toString() : f.format(v);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Text(
              "خطأ في تحميل الشيكات:\n${snap.error}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        // فلترة الشيكات الآجلة فقط (status = POSTDATED / postdated)
        List<Map<String, dynamic>> rows = (snap.data ?? [])
            .where((r) =>
                (r['status'] ?? '').toString().toUpperCase() == 'POSTDATED')
            .toList();

        if (rows.isEmpty) {
          return const Center(
            child: Text(
              "لا توجد شيكات آجلة حالياً",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          );
        }

        // ----------------------------
        // Mobile → Cards
        // ----------------------------
        if (!isDesktop) {
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (ctx, i) {
              final r = rows[i];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(
                    "رقم الشيك: ${r['cheque_no'] ?? r['cheque_number'] ?? ''}",
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "المحرر: ${r['drawer_name'] ?? ''}\n"
                    "البنك: ${r['bank_name'] ?? ''}\n"
                    "المبلغ: ${_fmtAmount(r['amount'])}\n"
                    "الاستحقاق: ${_fmtDate(r['due_date'])}",
                    textAlign: TextAlign.right,
                  ),
                ),
              );
            },
          );
        }

        // ----------------------------
        // Desktop → DataTable
        // ----------------------------
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 44,
            columns: const [
              DataColumn(label: Text("رقم الشيك")),
              DataColumn(label: Text("اسم المحرر")),
              DataColumn(label: Text("البنك")),
              DataColumn(label: Text("الفرع")),
              DataColumn(label: Text("المبلغ")),
              DataColumn(label: Text("العملة")),
              DataColumn(label: Text("تاريخ الإصدار")),
              DataColumn(label: Text("تاريخ الاستحقاق")),
              DataColumn(label: Text("الحالة")),
            ],
            rows: rows.map((r) {
              return DataRow(cells: [
                DataCell(Text(
                    (r['cheque_no'] ?? r['cheque_number'] ?? '').toString())),
                DataCell(Text((r['drawer_name'] ?? '').toString())),
                DataCell(Text((r['bank_name'] ?? '').toString())),
                DataCell(
                    Text((r['bank_branch'] ?? r['branch'] ?? '').toString())),
                DataCell(Text(_fmtAmount(r['amount']))),
                DataCell(Text((r['currency'] ?? '').toString())),
                DataCell(Text(_fmtDate(r['issue_date']))),
                DataCell(Text(_fmtDate(r['due_date']))),
                DataCell(Text((r['status'] ?? '').toString())),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }
}
