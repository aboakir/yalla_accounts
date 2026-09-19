// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/screens/cheques_dashboard_screen.dart
//
// ChequesDashboardScreen — FINAL PRO VERSION (FULL-B SYSTEM)
// -----------------------------------------------------------------------------
// • إحصائيات كاملة + مجموع القيم + عدد حسب الحالة والنوع
// • عرض أعلى 5 شيكات خطرة (استحقاق قريب ≤ 7 أيام)
// • تنبيه شيكات مستحقة قريباً
// • زر "تقرير الشيكات"
// • زر فتح تفاصيل الشيك مباشرة
// • دعم Desktop + Mobile مع Sidebar / Drawer
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import '../models/cheque.dart';
import 'cheque_details_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class ChequesDashboardScreen extends ConsumerWidget {
  const ChequesDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      appBar: const YallaAppBar(
        workshopName: "Yallah Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop
          ? null
          : const YallaSidebar(currentRoute: '/cheques/dashboard'),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(currentRoute: '/cheques/dashboard'),
          const Expanded(child: _DashboardBody()),
        ],
      ),
    );
  }
}

// ============================================================================
// BODY
// ============================================================================
class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  Future<List<Cheque>> _loadCheques() async {
    final db = await DBService.database;
    final rows = await db.query(
      'cheques',
      orderBy: 'due_date ASC',
    );
    return rows.map(Cheque.fromMap).toList();
  }

  String _fmt(double v) => NumberFormat('#,##0.##', 'ar').format(v);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Cheque>>(
      future: _loadCheques(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          debugPrint('Cheques dashboard load failed: ${snap.error}');
          return const Center(
            child: Text(
              "تعذر تحميل الشيكات. أعد المحاولة.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        final list = snap.data ?? [];

        // ----------------------------------------------------------------------
        // حساب الإحصائيات
        // ----------------------------------------------------------------------
        final total = list.length;
        final sum = list.fold<double>(0.0, (s, c) => s + c.amount);

        final incoming =
            list.where((c) => c.chequeType == ChequeType.incoming).length;
        final outgoing =
            list.where((c) => c.chequeType == ChequeType.outgoing).length;
        final collection =
            list.where((c) => c.status == ChequeStatus.deposited).length;

        final pending =
            list.where((c) => c.status == ChequeStatus.pending).length;
        final returned =
            list.where((c) => c.status == ChequeStatus.returned).length;
        final collected =
            list.where((c) => c.status == ChequeStatus.collected).length;
        final cancelled =
            list.where((c) => c.status == ChequeStatus.cancelled).length;
        final deposited =
            list.where((c) => c.status == ChequeStatus.deposited).length;

        // ----------------------------------------------------------------------
        // شيكات مستحقة قريباً (خلال 7 أيام)
        // ----------------------------------------------------------------------
        final now = DateTime.now();
        final soon = now.add(const Duration(days: 7));

        final dueSoon = list
            .where((c) =>
                c.dueDate.isAfter(now) &&
                c.dueDate.isBefore(soon) &&
                c.status == ChequeStatus.pending)
            .toList();

        dueSoon.sort((a, b) => a.dueDate.compareTo(b.dueDate));

        final top5soon = dueSoon.take(5).toList();

        final viewportWidth = MediaQuery.sizeOf(context).width;
        final grid = viewportWidth >= 1024 ? 4 : 2;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================================================================
              // HEADER + REPORT BUTTON
              // ==================================================================
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text(
                    "لوحة إدارة الشيكات",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("تقرير الشيكات"),
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.chequesReport),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              const Text(
                "نظرة عامة على جميع الشيكات داخل النظام.",
                textAlign: TextAlign.right,
              ),

              const SizedBox(height: 24),

              // ==================================================================
              // KPIs GRID
              // ==================================================================
              Expanded(
                child: GridView.count(
                  crossAxisCount: grid,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: viewportWidth >= 1024 ? 2.6 : 1.35,
                  children: [
                    _kpi("إجمالي الشيكات", "$total", Icons.list_alt),
                    _kpi("إجمالي القيمة", _fmt(sum), Icons.payments),
                    _kpi("وارد", "$incoming", Icons.call_received),
                    _kpi("صادر", "$outgoing", Icons.call_made),
                    _kpi("قيد التحصيل", "$collection", Icons.more_time),
                    _kpi("معلّق", "$pending", Icons.pending),
                    _kpi("محصّل", "$collected", Icons.verified),
                    _kpi("راجع", "$returned", Icons.undo),
                    _kpi("ملغى", "$cancelled", Icons.cancel),
                    _kpi("مودع", "$deposited", Icons.account_balance),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ==================================================================
              // تنبيه الشيكات المستحقة
              // ==================================================================
              if (dueSoon.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "تنبيه: لديك ${dueSoon.length} شيكات مستحقة خلال 7 أيام!",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ==================================================================
              // أعلى 5 شيكات خطرة (استحقاق قريب)
              // ==================================================================
              if (top5soon.isNotEmpty) _dangerTable(context, top5soon),
            ],
          ),
        );
      },
    );
  }

  // ====================================================================
  // WIDGETS
  // ====================================================================

  Widget _kpi(String title, String value, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdaptiveRow(
          children: [
            Icon(icon, size: 30, color: AppColors.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, textAlign: TextAlign.right),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _dangerTable(BuildContext context, List<Cheque> items) {
    final df = DateFormat('yyyy-MM-dd');

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              "أعلى 5 شيكات مستحقة قريباً",
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Table(
              border: TableBorder.all(color: Colors.grey.shade300),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade200),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text("رقم الشيك", textAlign: TextAlign.center),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text("القيمة", textAlign: TextAlign.center),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text("الاستحقاق", textAlign: TextAlign.center),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text("فتح", textAlign: TextAlign.center),
                    ),
                  ],
                ),
                ...items.map(
                  (c) => TableRow(
                    children: [
                      _cell(c.chequeNo),
                      _cell("${c.amount} ${c.currency}"),
                      _cell(df.format(c.dueDate)),
                      IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChequeDetailsScreen(cheque: c),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _cell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: TextAlign.center,
      ),
    );
  }
}
