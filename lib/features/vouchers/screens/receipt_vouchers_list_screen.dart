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

  String _receiptLabel(Map<String, Object?> row) {
    final rawNumber = row["receipt_number"];
    if (rawNumber == null) return row["id"].toString();
    return "RC-${rawNumber.toString().padLeft(6, '0')}";
  }

  String _methodLabel(Object? raw) {
    switch ((raw ?? '').toString().trim().toLowerCase()) {
      case 'cash':
        return 'نقدي';
      case 'bank_transfer':
        return 'تحويل بنكي';
      case 'card':
        return 'بطاقة';
      case 'cheque':
        return 'شيك';
      default:
        final value = (raw ?? '').toString().trim();
        return value.isEmpty ? 'غير محدد' : value;
    }
  }

  Future<void> _exportReceiptPdf(Map<String, Object?> row) async {
    try {
      final rawNumber = row["receipt_number"];
      if (rawNumber != null) {
        final receiptNumber =
            rawNumber is int ? rawNumber : int.tryParse(rawNumber.toString());
        if (receiptNumber != null) {
          final bytes = await P15DocumentService.generateReceiptPdf(
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

      final bytes = await YallaPdfService.generateReceiptVoucherPdf(
        voucherId: row["id"].toString(),
        amount: (row["amount"] as num).toDouble(),
        date: row["date"].toString(),
        clientName: row["clientName"]?.toString() ?? "-",
        method: row["method"]?.toString().toUpperCase() ?? "-",
        notes: row["notes"]?.toString(),
      );
      await YallaPdfService.saveAndOpen(
        bytes: bytes,
        fileName: "receipt_${row["id"]}.pdf",
        module: 'receipts',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء PDF للسند: $e')),
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
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return isPhone ? _phoneMain() : _desktopMain();
  }

  Widget _desktopMain() {
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

  Widget _phoneMain() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'سندات القبض',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: .92,
            children: [
              _phoneKpi(
                  'السندات', filtered.length.toString(), Icons.receipt_long),
              _phoneKpi('اليوم', totalToday.toStringAsFixed(0), Icons.today),
              _phoneKpi(
                  'الشهر', totalMonth.toStringAsFixed(0), Icons.calendar_month),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            onChanged: (value) {
              search = value;
              setState(_applyFilters);
            },
            decoration: InputDecoration(
              hintText: 'ابحث برقم السند أو العميل أو المبلغ',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: filterMethod,
                  decoration: const InputDecoration(
                    labelText: 'طريقة القبض',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    'الكل',
                    'cash',
                    'bank_transfer',
                    'card',
                    'cheque'
                  ]
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                                value == 'الكل' ? value : _methodLabel(value)),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      filterMethod = value;
                      _applyFilters();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'PDF القائمة',
                onPressed: filtered.isEmpty ? null : _exportListPdf,
                icon: const Icon(Icons.picture_as_pdf),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 34, horizontal: 16),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 42, color: Colors.grey),
                    SizedBox(height: 10),
                    Text('لا توجد سندات مطابقة'),
                  ],
                ),
              ),
            )
          else
            ...filtered.map(_phoneReceiptCard),
        ],
      ),
    );
  }

  Widget _phoneKpi(String title, String value, IconData icon) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneReceiptCard(Map<String, Object?> row) {
    final dateText = (row['date'] ?? '').toString();
    final date = dateText.length >= 10 ? dateText.substring(0, 10) : dateText;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final gl = (row['gl_entry_ids'] ?? '').toString().trim();
    final reversed = ((row['reversal_lines'] as num?)?.toInt() ?? 0) > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _receiptLabel(row),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row['clientName']?.toString().trim().isNotEmpty == true
                            ? row['clientName'].toString()
                            : 'بدون اسم عميل',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(date,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_methodLabel(row['method'])),
                ),
                if (gl.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar:
                        const Icon(Icons.account_balance_outlined, size: 16),
                    label: Text('GL $gl'),
                  ),
                if (reversed)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.undo, size: 16),
                    label: Text('يتضمن عكس'),
                  ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => _exportReceiptPdf(row),
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                label: const Text('فتح PDF'),
              ),
            ),
          ],
        ),
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
                          onPressed: () => _exportReceiptPdf(row),
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
