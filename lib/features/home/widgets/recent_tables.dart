// 📁 lib/features/home/widgets/recent_tables.dart
//
// RecentTables — جداول "آخر العمليات"
// ------------------------------------
// مصدر الحقيقة: DBService فقط. لا بيانات وهمية.
// يعرض:
//   1) آخر 10 إصلاحات (رقم، مركبة/عميل، الحالة، القيمة، التاريخ)
//   2) آخر 10 حركات GL (تاريخ، مرجع، البيان، مدين، دائن)
// يمكنك تضمينه داخل الـ Dashboard كما هو.
//
// ملاحظات حقول ممكنة:
// - repairs: id, customer_name, vehicle_type, status, total_amount, updated_at
//   (عدّل أسماء الأعمدة إذا اختلفت لديك)
// - gl_lines: date, ref, note, debit, credit
//   (نقوم بالتجميع على ref+note+date لعرض حركة واحدة)
//
// كل الاستعلامات LIMIT 10 للأحدث.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class RecentTables extends StatefulWidget {
  const RecentTables({super.key});

  @override
  State<RecentTables> createState() => _RecentTablesState();
}

class _RecentTablesState extends State<RecentTables> {
  bool loading = true;

  List<_RepairRow> repairs = [];
  List<_GLRow> glRows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DBService.database;

    // ===== آخر 10 إصلاحات =====
    // عدّل أسماء الحقول حسب سكيمتك إن لزم.
    final rRows = await db.rawQuery('''
      SELECT 
        id,
        COALESCE(customer_name, '') AS customer_name,
        COALESCE(vehicle_type, '') AS vehicle_type,
        COALESCE(status, '') AS status,
        COALESCE(total_amount, 0) AS total_amount,
        COALESCE(updated_at, created_at) AS ts
      FROM repairs
      ORDER BY datetime(ts) DESC
      LIMIT 10
    ''');

    repairs = rRows.map((m) {
      final amount = (m['total_amount'] ?? 0) as num;
      return _RepairRow(
        id: (m['id'] ?? '').toString(),
        customer: (m['customer_name'] ?? '') as String,
        vehicle: (m['vehicle_type'] ?? '') as String,
        status: (m['status'] ?? '') as String,
        amount: amount.toDouble(),
        ts: (m['ts'] ?? '').toString(),
      );
    }).toList();

    // ===== آخر 10 قيود GL مجمعة =====
    final gRows = await db.rawQuery('''
      SELECT 
        date,
        COALESCE(ref,'') AS ref,
        COALESCE(note,'') AS note,
        IFNULL(SUM(debit),0)  AS d,
        IFNULL(SUM(credit),0) AS c
      FROM gl_lines
      GROUP BY date, ref, note
      ORDER BY date DESC
      LIMIT 10
    ''');

    glRows = gRows.map((m) {
      return _GLRow(
        date: (m['date'] ?? '').toString(),
        ref: (m['ref'] ?? '').toString(),
        note: (m['note'] ?? '').toString(),
        debit: ((m['d'] ?? 0) as num).toDouble(),
        credit: ((m['c'] ?? 0) as num).toDouble(),
      );
    }).toList();

    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _Skeleton();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'آخر الإصلاحات',
          child: repairs.isEmpty
              ? const _Empty(label: 'لا توجد إصلاحات حديثة')
              : _RepairsTable(rows: repairs),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'آخر الحركات المالية (GL)',
          child: glRows.isEmpty
              ? const _Empty(label: 'لا توجد حركات مالية حديثة')
              : _GLTable(rows: glRows),
        ),
      ],
    );
  }
}

// ======================= Repairs table =======================

class _RepairsTable extends StatelessWidget {
  final List<_RepairRow> rows;
  const _RepairsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0.##');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('رقم')),
          DataColumn(label: Text('العميل')),
          DataColumn(label: Text('المركبة')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('القيمة')),
          DataColumn(label: Text('التاريخ')),
        ],
        rows: rows.map((r) {
          final dateStr = r.ts.length >= 10 ? r.ts.substring(0, 16) : r.ts;
          final statusColor = _statusColor(r.status);
          return DataRow(
            cells: [
              DataCell(Text(r.id)),
              DataCell(Text(r.customer.isEmpty ? '-' : r.customer)),
              DataCell(Text(r.vehicle.isEmpty ? '-' : r.vehicle)),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  r.status.isEmpty ? '-' : r.status,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              )),
              DataCell(Text('${MoneyFormatter.format(r.amount)}')),
              DataCell(Text(dateStr)),
            ],
          );
        }).toList(),
      ),
    );
  }

  static Color _statusColor(String s) {
    final t = s.trim();
    if (t.contains('مغلق') ||
        t.contains('تم التسليم') ||
        t.toUpperCase() == 'CLOSED') {
      return Colors.green;
    }
    if (t.contains('متوقف') ||
        t.contains('معلّق') ||
        t.toUpperCase() == 'ON HOLD') {
      return Colors.orange;
    }
    if (t.isEmpty) return Colors.grey;
    return AppColors.primary;
  }
}

class _RepairRow {
  final String id;
  final String customer;
  final String vehicle;
  final String status;
  final double amount;
  final String ts;

  _RepairRow({
    required this.id,
    required this.customer,
    required this.vehicle,
    required this.status,
    required this.amount,
    required this.ts,
  });
}

// ======================= GL table =======================

class _GLTable extends StatelessWidget {
  final List<_GLRow> rows;
  const _GLTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0.##');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('المرجع')),
          DataColumn(label: Text('البيان')),
          DataColumn(label: Text('مدين')),
          DataColumn(label: Text('دائن')),
        ],
        rows: rows.map((g) {
          final dateStr =
              g.date.length >= 10 ? g.date.substring(0, 10) : g.date;
          return DataRow(
            cells: [
              DataCell(Text(dateStr)),
              DataCell(Text(g.ref.isEmpty ? '-' : g.ref)),
              DataCell(SizedBox(
                width: 280,
                child: Text(
                  g.note.isEmpty ? '-' : g.note,
                  overflow: TextOverflow.ellipsis,
                ),
              )),
              DataCell(Text(nf.format(g.debit))),
              DataCell(Text(nf.format(g.credit))),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _GLRow {
  final String date;
  final String ref;
  final String note;
  final double debit;
  final double credit;

  _GLRow({
    required this.date,
    required this.ref,
    required this.note,
    required this.debit,
    required this.credit,
  });
}

// ======================= Shared UI =======================

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String label;
  const _Empty({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.grey)),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h) => Container(
          height: h,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
        );

    return Column(
      children: [
        box(140),
        const SizedBox(height: 12),
        box(140),
      ],
    );
  }
}
