import 'package:yalla_accounts/features/vouchers/widgets/voucher_list_phone.dart';
// -----------------------------------------------------------------------------
// 📁 lib/features/vouchers/screens/payment_voucher_list_screen.dart
// FINAL DESKTOP SCROLL — Premium v5 (Unified PDF)
// -----------------------------------------------------------------------------
// • تم إلغاء الاعتماد على payment_voucher_pdf.dart بالكامل
// • الآن يتم استخدام الملف المركزي yalla_pdf_service.dart فقط
// • بدون شعار، بدون تحميل صور، بدون مشاكل Assets
// • PDF ثابت وموحد للسندات
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

// الاعتماد الجديد والوحيد للـ PDF
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

/// ============================================================================
/// DESKTOP SCROLL BEHAVIOR — MUST BE OUTSIDE THE CLASS
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
class PaymentVoucherListScreen extends StatefulWidget {
  const PaymentVoucherListScreen({super.key});

  @override
  State<PaymentVoucherListScreen> createState() =>
      _PaymentVoucherListScreenState();
}

class _PaymentVoucherListScreenState extends State<PaymentVoucherListScreen> {
  bool loading = true;

  List<Map<String, Object?>> all = [];
  List<Map<String, Object?>> filtered = [];

  String search = "";
  String filterMethod = "الكل";

  double totalToday = 0;
  double totalMonth = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // =============================================================================
  // LOAD DATA
  // =============================================================================
  Future<void> _load() async {
    final db = await DBService.database;

    all = await db.rawQuery("""
SELECT
v.voucher_number,
v.id,
  v.status,
  v.reversal_reason,
  v.amount,
  v.date,
  v.method,
  v.notes,
  (
    SELECT e.id
    FROM gl_entries e
    WHERE e.source = 'VOUCHER'
      AND e.source_id = v.id
    ORDER BY e.id DESC
    LIMIT 1
  ) AS gl_entry_id,
  v.party_id,
  v.source,
  v.source_id,
  COALESCE(
    (SELECT full_name FROM employees e WHERE e.id = v.party_id LIMIT 1),
    (SELECT name FROM suppliers s WHERE s.id = CAST(v.party_id AS INTEGER) LIMIT 1),
    'مصاريف تشغيلية'
  ) AS party_name
FROM vouchers v
WHERE v.voucher_type = 'PAYMENT'
  AND (
    v.party_type = 'EMPLOYEE'
    OR v.source = 'EMP_ADV'
    OR v.party_type = 'EXPENSE'
    OR v.party_type = 'SUPPLIER'
  )
ORDER BY v.date DESC;
""");

    final today = DateFormat("yyyy-MM-dd").format(DateTime.now());
    final month = DateFormat("yyyy-MM").format(DateTime.now());

    final rowToday = await db.rawQuery("""
SELECT SUM(v.amount) AS s
FROM vouchers v
WHERE v.voucher_type = 'PAYMENT'
  AND COALESCE(v.status,'POSTED') <> 'REVERSED'
  AND substr(v.date,1,10)=?
  AND (
    v.party_type = 'EMPLOYEE'
    OR v.source = 'EMP_ADV'
    OR v.party_type = 'EXPENSE'
    OR v.party_type = 'SUPPLIER'
  );
""", [today]);

    final rowMonth = await db.rawQuery("""
SELECT SUM(v.amount) AS s
FROM vouchers v
WHERE v.voucher_type = 'PAYMENT'
  AND COALESCE(v.status,'POSTED') <> 'REVERSED'
  AND substr(v.date,1,7)=?
  AND (
    v.party_type = 'EMPLOYEE'
    OR v.source = 'EMP_ADV'
    OR v.party_type = 'EXPENSE'
    OR v.party_type = 'SUPPLIER'
  );
""", [month]);

    totalToday = (rowToday.first["s"] as num? ?? 0).toDouble();
    totalMonth = (rowMonth.first["s"] as num? ?? 0).toDouble();

    _applyFilters();
    if (!mounted) return;
    setState(() => loading = false);
  }

  // =============================================================================
  // FILTERS
  // =============================================================================
  void _applyFilters() {
    filtered = all.where((row) {
      final text =
          "${row["voucher_number"]} ${row["amount"]} ${row["notes"]} ${row["party_name"]}"
              .toLowerCase();

      if (!text.contains(search.toLowerCase())) return false;

      final m = (row["method"] ?? "").toString().toLowerCase();
      if (filterMethod != "الكل" && m != filterMethod.toLowerCase()) {
        return false;
      }

      return true;
    }).toList();
  }

  // =============================================================================
  // PDF GENERATION — Unified PDF using YallaPdfService
  // =============================================================================
  Future<void> _generatePdf(Map row) async {
    try {
      final pdfBytes = await YallaPdfService.generatePaymentVoucherPdf(
        voucherId: row["voucher_number"]?.toString() ?? "P-UNNUMBERED",
        date: DateTime.parse(row["date"]),
        amount: (row["amount"] as num).toDouble(),
        method: row["method"].toString(),
        partyName: row["party_name"]?.toString() ?? "—",
        notes: row["notes"]?.toString() ?? "",
        glEntryId: null,
      );

      // فتح PDF مباشرة بدون نافذة طباعة Windows
      await YallaPdfService.saveAndOpen(
        bytes: pdfBytes,
        fileName:
            "payment_voucher_${row["voucher_number"] ?? "P-UNNUMBERED"}.pdf",
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF ERROR: $e")),
      );
    }
  }

  Future<void> _exportListPdf() async {
    try {
      final pdfBytes = await YallaPdfService.generatePaymentVoucherListPdf(
        rows: filtered,
        totalToday: totalToday,
        totalMonth: totalMonth,
        generatedAt: DateTime.now(),
      );

      await YallaPdfService.saveAndOpen(
        bytes: pdfBytes,
        fileName: "payment_vouchers_list.pdf",
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ PDF: $e")),
      );
    }
  }

  // =============================================================================
  // UI BUILD
  // =============================================================================
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const YallaAppBar(
        workshopName: "Yallah Accounts",
        showThemeToggle: false,
        showSearch: false,
      ),
      body: Row(
        children: [
          if (isDesktop)
            const YallaSidebar(currentRoute: '/finance/payment-vouchers'),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ScrollConfiguration(
                    behavior: isDesktop
                        ? const DesktopScrollBehavior()
                        : const MaterialScrollBehavior(),
                    child: _main(),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map row) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AdaptiveAlertDialog(
          title: const Text("إلغاء سند الصرف"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "السند المرحّل لا يُحذف. سيتم إنشاء عكس محاسبي رسمي "
                "مع إبقاء المستند الأصلي محفوظًا.",
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "سبب الإلغاء",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("رجوع"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("تأكيد الإلغاء"),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final reason = controller.text.trim();
    if (reason.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يجب كتابة سبب الإلغاء")),
      );
      return;
    }

    try {
      await VoucherPaymentService.reverseVoucher(
        row["id"].toString(),
        reason: reason,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم إلغاء السند وتسجيل العكس المحاسبي"),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("تعذر إلغاء السند: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =============================================================================
  // MAIN CONTAINER
  // =============================================================================
  Widget _main() {
    if (MediaQuery.sizeOf(context).width < 1024) {
      return VoucherListPhone(
        isReceipt: false,
        rows: filtered,
        today: totalToday,
        month: totalMonth,
        method: filterMethod,
        methods: const ['الكل', 'cash', 'bank', 'cheque', 'transfer'],
        onSearch: (value) {
          search = value;
          setState(_applyFilters);
        },
        onMethod: (value) {
          filterMethod = value;
          setState(_applyFilters);
        },
        onRefresh: _load,
        onExport: _exportListPdf,
        onDocument: _generatePdf,
        onReverse: _confirmDelete,
        numberLabel: (row) => 'سند صرف: ${row['voucher_number'] ?? 'غير مرقم'}',
      );
    }
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
        _kpi("مصروفات اليوم", totalToday.toString(), Icons.today),
        const SizedBox(width: 12),
        _kpi("مصروفات الشهر", totalMonth.toString(), Icons.calendar_month),
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
              items: const ["الكل", "cash", "bank", "cheque", "transfer"]
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(voucherMethodLabel(e)),
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
  // MAIN TABLE
  // =============================================================================
  Widget _table() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: AdaptiveRow(
              children: const [
                Expanded(flex: 1, child: Text("PDF")),
                Expanded(flex: 1, child: Text("إلغاء")),
                Expanded(
                    flex: 2,
                    child: Text("ID",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 3,
                    child: Text("التاريخ",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 4,
                    child: Text("الطرف",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                  flex: 2,
                  child: Text(
                    "النوع",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                    flex: 3,
                    child: Text("المبلغ",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 3,
                    child: Text("الطريقة",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 2,
                    child: Text("الحالة",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),

          // BODY
          Expanded(
            child: Scrollbar(
              controller: PrimaryScrollController.of(context),
              thumbVisibility: true,
              child: ListView.separated(
                controller: PrimaryScrollController.of(context),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => Divider(
                  height: 0,
                  thickness: 0.3,
                  color: Colors.grey.withOpacity(0.3),
                ),
                itemBuilder: (_, i) {
                  final row = filtered[i];
                  final dt = row["date"].toString().substring(0, 10);

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 18),
                    child: AdaptiveRow(
                      children: [
                        Expanded(
                          flex: 1,
                          child: IconButton(
                            icon: const Icon(Icons.picture_as_pdf,
                                color: Colors.red, size: 24),
                            onPressed: () => _generatePdf(row),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: IconButton(
                            icon: const Icon(Icons.cancel_outlined,
                                color: Colors.red),
                            onPressed: () => _confirmDelete(row),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row["voucher_number"]?.toString() ?? "-",
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(dt, textAlign: TextAlign.center),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            row["party_name"]?.toString() ?? "—",
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 8),
                            decoration: BoxDecoration(
                              color: row["source"] == "EMP_ADV"
                                  ? Colors.orange.withOpacity(0.15)
                                  : row["party_name"] == "مصاريف تشغيلية"
                                      ? Colors.grey.withOpacity(0.15)
                                      : Colors.blue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              row["source"] == "EMP_ADV"
                                  ? "سلفة"
                                  : row["party_name"] == "مصاريف تشغيلية"
                                      ? "مصروف"
                                      : "دفع",
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            MoneyFormatter.format(
                                (row["amount"] as num).toDouble()),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              row["method"].toString().toUpperCase(),
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            (row["status"]?.toString().toUpperCase() ==
                                    "REVERSED")
                                ? "ملغي"
                                : "مرحّل",
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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
