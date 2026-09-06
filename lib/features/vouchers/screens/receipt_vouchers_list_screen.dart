// -----------------------------------------------------------------------------
// 📁 lib/features/finance/vouchers/receipt_voucher_list_screen.dart
// FINAL DESKTOP SCROLL SUPPORT — Fixed Class Placement
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/features/documents/services/p15_document_service.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

/// ============================================================================
/// DESKTOP SCROLL BEHAVIOR — MUST BE OUTSIDE ANY CLASS
/// ============================================================================
class DesktopScrollBehavior extends ScrollBehavior {
  const DesktopScrollBehavior();

  @override
  Widget buildScrollbar(context, child, details) {
    return Scrollbar(
      controller: PrimaryScrollController.of(context),
      thumbVisibility: true,
      interactive: true,
      child: child,
    );
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

/// ============================================================================
/// MAIN SCREEN
/// ============================================================================
class ReceiptVoucherListScreen extends StatefulWidget {
  const ReceiptVoucherListScreen({super.key});

  @override
  State<ReceiptVoucherListScreen> createState() =>
      _ReceiptVoucherListScreenState();
}

class _ReceiptVoucherListScreenState extends State<ReceiptVoucherListScreen> {
  bool loading = true;
  WorkshopSettings? settings;

  List<Map<String, Object?>> all = [];
  List<Map<String, Object?>> filtered = [];

  String search = "";
  String filterMethod = "الكل";

  double totalToday = 0;
  double totalMonth = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    settings = await WorkshopSettingsService.instance.getOrDefaults();
    await _load();
  }

  // =============================================================================
  // LOAD DATA
  // =============================================================================
  Future<void> _load() async {
    final db = await DBService.database;

    all = await db.rawQuery("""
      SELECT
        COALESCE(CAST(p.receipt_number AS TEXT), p.id) AS receipt_key,
        p.receipt_number,
        MIN(p.id) AS id,
        SUM(p.amount) AS amount,
        MAX(p.date) AS date,
        MAX(p.method) AS method,
        MAX(p.notes) AS notes,
        MAX(p.client_id) AS client_id,
        MAX(c.name) AS clientName,
        GROUP_CONCAT(p.gl_entry_id) AS gl_entry_ids,
        SUM(CASE WHEN p.reversal_of_payment_id IS NOT NULL THEN 1 ELSE 0 END) AS reversal_lines
      FROM payments p
      LEFT JOIN clients c ON c.id = p.client_id
      WHERE p.isIncome = 1
        AND LOWER(COALESCE(p.method,'')) <> 'customer_credit'
      GROUP BY COALESCE(CAST(p.receipt_number AS TEXT), p.id)
      ORDER BY MAX(p.date) DESC
    """);

    final today = DateFormat("yyyy-MM-dd").format(DateTime.now());
    final month = DateFormat("yyyy-MM").format(DateTime.now());

    final rowToday = await db.rawQuery("""
      SELECT SUM(amount) AS s 
      FROM payments 
      WHERE isIncome = 1
        AND LOWER(COALESCE(method,'')) <> 'customer_credit'
        AND substr(date,1,10)=?
    """, [today]);

    final rowMonth = await db.rawQuery("""
      SELECT SUM(amount) AS s 
      FROM payments 
      WHERE isIncome = 1
        AND LOWER(COALESCE(method,'')) <> 'customer_credit'
        AND substr(date,1,7)=?
    """, [month]);

    totalToday = (rowToday.first["s"] as num? ?? 0).toDouble();
    totalMonth = (rowMonth.first["s"] as num? ?? 0).toDouble();

    _applyFilters();
    setState(() => loading = false);
  }

  // =============================================================================
  // FILTERS
  // =============================================================================
  void _applyFilters() {
    filtered = all.where((row) {
      final txt =
          "${row["receipt_number"] ?? row["id"]} ${row["amount"]} ${row["clientName"]} ${row["notes"]}"
              .toLowerCase();

      if (!txt.contains(search.toLowerCase())) return false;

      final m = (row["method"] ?? "").toString().toLowerCase();
      if (filterMethod != "الكل" && m != filterMethod.toLowerCase()) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _exportListPdf() async {
    try {
      final pdfBytes = await YallaPdfService.generateReceiptVoucherListPdf(
        rows: filtered,
        totalToday: totalToday,
        totalMonth: totalMonth,
        generatedAt: DateTime.now(),
      );

      await YallaPdfService.saveAndOpen(
        bytes: pdfBytes,
        fileName: "receipt_vouchers_list.pdf",
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ PDF: $e")),
      );
    }
  }

  // =============================================================================
  // BUILD UI
  // =============================================================================
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: YallaAppBar(
        workshopName: settings?.workshopName ?? "Yalla Accounts",
        logoPath: settings?.logoPath,
        showThemeToggle: false,
        showSearch: false,
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const YallaSidebar(currentRoute: AppRoutes.receiptVouchersList),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : _main(),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // MAIN WRAPPER
  // =============================================================================
  Widget _main() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _kpiCards(),
          const SizedBox(height: 18),
          _filters(),
          const SizedBox(height: 18),
          Expanded(
            child: ScrollConfiguration(
              behavior: const DesktopScrollBehavior(),
              child: _table(),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // KPI CARDS
  // =============================================================================
  Widget _kpiCards() {
    return AdaptiveRow(
      children: [
        _kpi("عدد السندات", filtered.length.toString(), Icons.receipt_long),
        const SizedBox(width: 12),
        _kpi("مقبوضات اليوم", totalToday.toString(), Icons.today),
        const SizedBox(width: 12),
        _kpi("مقبوضات الشهر", totalMonth.toString(), Icons.calendar_month),
      ],
    );
  }

  Widget _kpi(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Text(title, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  // =============================================================================
  // FILTER BAR
  // =============================================================================
  Widget _filters() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AdaptiveRow(
          children: [
            Expanded(
              child: TextField(
                inputFormatters: const [YallaDigitNormalizer()],
                onChanged: (v) {
                  search = v;
                  setState(_applyFilters);
                },
                decoration: InputDecoration(
                  hintText: "بحث...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: filterMethod,
              underline: const SizedBox(),
              items: const ["الكل", "cash", "bank_transfer", "card", "cheque"]
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.toUpperCase()),
                      ))
                  .toList(),
              onChanged: (v) {
                filterMethod = v!;
                setState(_applyFilters);
              },
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text("PDF القائمة"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: filtered.isEmpty ? null : _exportListPdf,
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================================
  // TABLE — SCROLL + KEYBOARD MOVEMENT
  // =============================================================================
  Widget _table() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: AdaptiveRow(
              children: const [
                Expanded(flex: 1, child: Text("PDF")),
                Expanded(
                    flex: 2, child: Text("السند", textAlign: TextAlign.center)),
                Expanded(
                    flex: 3,
                    child: Text("التاريخ", textAlign: TextAlign.center)),
                Expanded(
                    flex: 4,
                    child: Text("العميل", textAlign: TextAlign.center)),
                Expanded(
                    flex: 3,
                    child: Text("المبلغ", textAlign: TextAlign.center)),
                Expanded(
                    flex: 3,
                    child: Text("الطريقة", textAlign: TextAlign.center)),
                Expanded(
                    flex: 2, child: Text("GL", textAlign: TextAlign.center)),
              ],
            ),
          ),

          // BODY
          Expanded(
            child: ListView.builder(
              controller: PrimaryScrollController.of(context),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final row = filtered[i];
                final dt = row["date"].toString().substring(0, 10);

                return Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.withOpacity(0.2),
                        width: 0.4,
                      ),
                    ),
                  ),
                  child: AdaptiveRow(
                    children: [
                      // PDF
                      Expanded(
                        flex: 1,
                        child: IconButton(
                          icon: const Icon(Icons.picture_as_pdf,
                              color: Colors.red),
                          onPressed: () async {
                            final rawNumber = row["receipt_number"];
                            if (rawNumber != null) {
                              final receiptNumber = rawNumber is int
                                  ? rawNumber
                                  : int.tryParse(rawNumber.toString());
                              if (receiptNumber != null) {
                                final bytes =
                                    await P15DocumentService.generateReceiptPdf(
                                  receiptNumber,
                                );
                                await YallaPdfService.saveAndOpen(
                                  bytes: bytes,
                                  fileName:
                                      "receipt_RC-${receiptNumber.toString().padLeft(6, '0')}.pdf",
                                  module: 'receipts',
                                );
                                return;
                              }
                            }

                            // Legacy rows without a P11 receipt header remain printable.
                            final bytes =
                                await YallaPdfService.generateReceiptVoucherPdf(
                              voucherId: row["id"].toString(),
                              amount: (row["amount"] as num).toDouble(),
                              date: row["date"].toString(),
                              clientName: row["clientName"]?.toString() ?? "-",
                              method: row["method"]?.toString().toUpperCase() ??
                                  "-",
                              notes: row["notes"]?.toString(),
                            );
                            await YallaPdfService.saveAndOpen(
                              bytes: bytes,
                              fileName: "receipt_${row["id"]}.pdf",
                              module: 'receipts',
                            );
                          },
                        ),
                      ),

                      Expanded(
                        flex: 2,
                        child: Text(
                          row["receipt_number"] == null
                              ? row["id"].toString()
                              : "RC-${row["receipt_number"].toString().padLeft(6, '0')}",
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(dt, textAlign: TextAlign.center),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          row["clientName"]?.toString() ?? "-",
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          row["amount"].toString(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            row["method"].toString().toUpperCase(),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          row["gl_entry_ids"]?.toString() ?? "-",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // FOOTER
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
            ),
            child: Text(
              "${filtered.length} سند",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
