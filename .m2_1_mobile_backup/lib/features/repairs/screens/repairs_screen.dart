// ًں“پ lib/features/repairs/screens/repairs_screen.dart
//
// RepairsScreen â€” ط¥ط¯ط§ط±ط© ظ…ظ„ظپط§طھ ط§ظ„ط¥طµظ„ط§ط­
// ط¥طµظ„ط§ط­ ط®ط·ط£ hit test ط¹ط¨ط± طھط¹ط·ظٹظ„ FAB ط¹ظ†ط¯ظ…ط§ ظ„ط§ طھظƒظˆظ† ط§ظ„ط´ط§ط´ط© current ط£ظˆ ط¨ط¯ظˆظ† ظ‚ظٹظˆط¯ Layout.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
// import 'package:yalla_accounts/features/finance/screens/add_purchase_screen.dart'; // ظ…ط¹ط·ظ‘ظ„ ظ…ط¤ظ‚طھظ‹ط§

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_provider.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/edit_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_finance_service.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_card.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_filter_bar.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_stats_cards.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_summary_section.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_financial_summary.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

// âœ… ط«ظˆط§ط¨طھ ظ…ظˆط­ظ‘ط¯ط©
import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairsScreen extends ConsumerStatefulWidget {
  final bool showAll;

  const RepairsScreen({super.key, this.showAll = false});

  @override
  ConsumerState<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends ConsumerState<RepairsScreen> {
  String searchText = '';
  String selectedStatus = 'ط§ظ„ظƒظ„';
  String selectedType = 'ط§ظ„ظƒظ„';
  DateTime? fromDate;
  DateTime? toDate;
  static const int initialLimit = 10;

  double _fileValue(Repair r) => r.totalFileValue.toDouble();
  double _paidValue(Repair r) => r.totalPaidAmount.toDouble();

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'ظ†ط·ط§ظ‚ ط§ظ„طھط§ط±ظٹط®',
    );
    if (picked != null) {
      setState(() {
        fromDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        toDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
    }
  }

  void _openAddMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ًں”• ط´ط±ط§ط، ظ‚ط·ط¹ ط؛ظٹط§ط± â€” ظ…ط¹ط·ظ‘ظ„ ظ…ط¤ظ‚طھظ‹ط§
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('ًں›’ ط´ط±ط§ط، ظ‚ط·ط¹ ط؛ظٹط§ط±'),
              onTap: () async {
                Navigator.pop(context);
                if (!mounted) {
                  return;
                }
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AdaptiveAlertDialog(
                    title: const Text('ط؛ظٹط± ظ…طھط§ط­ ظ…ط¤ظ‚طھظ‹ط§'),
                    content: const Text(
                      'ظ…ظٹط²ط© "ط´ط±ط§ط، ظ‚ط·ط¹ ط؛ظٹط§ط±" ط³طھظڈظپط¹ظ‘ظ„ ظ„ط§ط­ظ‚ظ‹ط§ ط¨ط¹ط¯ ط¥ط¶ط§ظپط© ط§ظ„ط´ط§ط´ط© ط§ظ„ظ…ط·ظ„ظˆط¨ط©.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('ط­ط³ظ†ظ‹ط§'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.build),
              title: const Text('âڑ™ï¸ڈ ط¥ط¶ط§ظپط© ط¥طµظ„ط§ط­ ط¬ط¯ظٹط¯'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddRepairScreen()),
                ).then(
                  (_) => ref.read(repairListProvider.notifier).loadRepairs(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleQuickFilter(String type) {
    setState(() {
      selectedStatus = (type == 'paid') ? 'ظ…ط³ط¯ط¯' : 'ط؛ظٹط± ظ…ط³ط¯ط¯';
    });
  }

  Future<void> _approveRepairLedger(BuildContext context, Repair repair) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: const Text('طھط£ظƒظٹط¯ ط§ظ„ط§ط¹طھظ…ط§ط¯'),
        content: const Text(
          'ظ‡ظ„ طھط±ظٹط¯ ط§ط¹طھظ…ط§ط¯ ظ‡ط°ط§ ط§ظ„ظ…ظ„ظپ ظˆطھظˆظ„ظٹط¯ ظ‚ظٹط¯ ظ…ط­ط§ط³ط¨ظٹطں',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ط§ط¹طھظ…ط§ط¯'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await RepairFinanceService.approveFinalAmount(repair);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'âœ… طھظ… ط§ط¹طھظ…ط§ط¯ ط§ظ„ظ…ظ„ظپ ظˆطھظˆظ„ظٹط¯ ط§ظ„ظ‚ظٹط¯ ط§ظ„ظ…ط­ط§ط³ط¨ظٹ',
            ),
          ),
        );
        ref.read(repairListProvider.notifier).loadRepairs();
      } catch (e) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('â‌Œ ظپط´ظ„ ط§ظ„ط§ط¹طھظ…ط§ط¯: $e')),
        );
      }
    }
  }

  // ًں§¾ طھطµط¯ظٹط± PDF
  Future<void> exportToPdf(List<Repair> data) async {
    final df = DateFormat('yyyy-MM-dd');

    // طھط¬ظ‡ظٹط² ط¨ظٹط§ظ†ط§طھ ط§ظ„ط¬ط¯ظˆظ„
    final List<List<String>> rows = data.map((r) {
      final fv = _fileValue(r);
      final pv = _paidValue(r);
      final remaining = fv - pv;
      final payStatus =
          normalizeOrNull(r.paymentStatus, kPaymentStatuses) ?? r.paymentStatus;

      return [
        df.format(r.receivedDate),
        r.vehicleType,
        r.vehicleNumber,
        r.beneficiaryName,
        fv.toStringAsFixed(2),
        pv.toStringAsFixed(2),
        MoneyFormatter.format(remaining),
        payStatus ?? '',
      ];
    }).toList();

    // طھظˆظ„ظٹط¯ PDF ط¹ط¨ط± ط§ظ„ظ†ط¸ط§ظ… ط§ظ„ظ…ط±ظƒط²ظٹ
    final bytes = await YallaPdfService.generateTablePdf(
      title: "ظ‚ط§ط¦ظ…ط© ط§ظ„ظ…ط±ظƒط¨ط§طھ",
      headers: [
        'ط§ظ„طھط§ط±ظٹط®',
        'ظ†ظˆط¹ ط§ظ„ظ…ط±ظƒط¨ط©',
        'ط±ظ‚ظ… ط§ظ„ظ…ط±ظƒط¨ط©',
        'ط§ظ„ظ…ط³طھظپظٹط¯',
        'ظ‚ظٹظ…ط© ط§ظ„ظ…ظ„ظپ',
        'ط§ظ„ظ…ط¯ظپظˆط¹',
        'ط§ظ„ظ…طھط¨ظ‚ظٹ',
        'ط­ط§ظ„ط© ط§ظ„ط³ط¯ط§ط¯',
      ],
      rows: rows,
    );

    final file = await YallaPdfService.saveAndOpen(
      bytes: bytes,
      fileName: "vehicles_export.pdf",
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("ًں“„ طھظ… طھظˆظ„ظٹط¯ ط§ظ„ظ…ظ„ظپ: ${file.path}"),
        ),
      );
    }
  }

  // ًں“ٹ طھطµط¯ظٹط± Excel
  Future<void> exportToExcel(List<Repair> data) async {
    final excel = Excel.createExcel();
    final sheet = excel['Vehicles'];
    final df = DateFormat('yyyy-MM-dd');

    sheet.appendRow([
      TextCellValue('ط§ظ„طھط§ط±ظٹط®'),
      TextCellValue('ظ†ظˆط¹ ط§ظ„ظ…ط±ظƒط¨ط©'),
      TextCellValue('ط±ظ‚ظ… ط§ظ„ظ…ط±ظƒط¨ط©'),
      TextCellValue('ط§ظ„ظ…ط³طھظپظٹط¯'),
      TextCellValue('ظ‚ظٹظ…ط© ط§ظ„ظ…ظ„ظپ'),
      TextCellValue('ط§ظ„ظ…ط¯ظپظˆط¹'),
      TextCellValue('ط§ظ„ظ…طھط¨ظ‚ظٹ'),
      TextCellValue('ط­ط§ظ„ط© ط§ظ„ط³ط¯ط§ط¯'),
    ]);

    for (final r in data) {
      final fv = _fileValue(r);
      final pv = _paidValue(r);
      final remaining = fv - pv;
      final payStatus =
          normalizeOrNull(r.paymentStatus, kPaymentStatuses) ?? r.paymentStatus;

      sheet.appendRow([
        TextCellValue(df.format(r.receivedDate)),
        TextCellValue(r.vehicleType),
        TextCellValue(r.vehicleNumber),
        TextCellValue(r.beneficiaryName),
        DoubleCellValue(fv),
        DoubleCellValue(pv),
        DoubleCellValue(remaining),
        TextCellValue(payStatus ?? ''),
      ]);
    }

    final dir = await getDownloadsDirectory();
    final file = File('${dir!.path}/vehicles_export.xlsx');
    file.writeAsBytesSync(excel.encode()!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('âœ… طھظ… ط­ظپط¸ Excel ظپظٹ ${file.path}')),
      );
    }
  }

  void _openQuickActions(Repair r) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('طھط¹ط¯ظٹظ„ ط§ظ„ظ…ظ„ظپ'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditRepairScreen(repair: r),
                  ),
                ).then(
                  (_) => ref.read(repairListProvider.notifier).loadRepairs(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified),
              title: const Text('ط§ط¹طھظ…ط§ط¯ ط§ظ„ظ‚ظٹط¯ ط§ظ„ظ…ط­ط§ط³ط¨ظٹ'),
              onTap: () {
                Navigator.pop(context);
                _approveRepairLedger(context, r);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('ظ‚ظٹظˆط¯ ط§ظ„ظٹظˆظ…ظٹط© ظ„ظ‡ط°ط§ ط§ظ„ظ…ظ„ظپ'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  '/finance/journal',
                  arguments: {'relatedRepairId': r.id},
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments),
              title: const Text('ط¯ظپط¹ط§طھ ظ‡ط°ط§ ط§ظ„ظ…ظ„ظپ'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  '/finance/payments',
                  arguments: {
                    'relatedRepairId': r.id,
                    'clientName': r.beneficiaryName,
                  },
                ).then((updated) {
                  if (updated == true) {
                    ref.read(repairListProvider.notifier).loadRepairs();
                  }
                });
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'ط­ط°ظپ ط§ظ„ظ…ظ„ظپ',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(context);
                await RepairDatabaseService.deleteRepair(r.id);
                ref.read(repairListProvider.notifier).loadRepairs();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===== FAB ط¢ظ…ظ† =====
  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _openAddMenu,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(100),
        side: const BorderSide(color: AppColors.primary, width: 2),
      ),
      child: const Icon(Icons.add),
    );
  }

  void _openRepairDetails(Repair repair) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RepairDetailsScreen(repair: repair)),
    ).then((_) => ref.read(repairListProvider.notifier).loadRepairs());
  }

  Widget _buildPhoneRepairs({
    required List<Repair> filtered,
    required List<Repair> active,
    required List<Repair> activeAll,
    required List<Repair> archived,
    required bool hasMoreActive,
    required bool showFab,
  }) {
    final total = filtered.fold<double>(0, (sum, r) => sum + _fileValue(r));
    final paid = filtered.fold<double>(0, (sum, r) => sum + _paidValue(r));
    final remaining = (total - paid).clamp(0.0, double.infinity);
    final paidRatio = total <= 0 ? 0.0 : (paid / total).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const Drawer(
        child: SafeArea(child: YallaSidebar(currentRoute: '/repairs')),
      ),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ط¥طµظ„ط§ط­ ط§ظ„ظ…ط±ظƒط¨ط§طھ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'date') _selectDateRange();
              if (v == 'analytics') {
                Navigator.pushNamed(context, '/repair-analytics');
              }
              if (v == 'pdf') exportToPdf(filtered);
              if (v == 'excel') exportToExcel(filtered);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'date',
                child: Text('طھط­ط¯ظٹط¯ ط§ظ„ظپطھط±ط©'),
              ),
              PopupMenuItem(
                value: 'analytics',
                child: Text('طھط­ظ„ظٹظ„ ط§ظ„ط¨ظٹط§ظ†ط§طھ'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(value: 'pdf', child: Text('طھطµط¯ظٹط± PDF')),
              PopupMenuItem(value: 'excel', child: Text('طھطµط¯ظٹط± Excel')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(repairListProvider.notifier).loadRepairs(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            TextField(
              onChanged: (v) => setState(() => searchText = v),
              decoration: InputDecoration(
                hintText:
                    'ط§ط¨ط­ط« ط¨ط§ظ„ظ…ط±ظƒط¨ط©طŒ ط§ظ„ط±ظ‚ظ… ط£ظˆ ط§ظ„ظ…ط³طھظپظٹط¯...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _phoneFilterChip('ط§ظ„ظƒظ„'),
                  const SizedBox(width: 8),
                  _phoneFilterChip('ط؛ظٹط± ظ…ط³ط¯ط¯'),
                  const SizedBox(width: 8),
                  _phoneFilterChip('ظ…ط³ط¯ط¯ ط¬ط²ط¦ظٹ'),
                  const SizedBox(width: 8),
                  _phoneFilterChip('ظ…ط³ط¯ط¯'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _phoneFinancialSummary(
              total,
              paid,
              remaining,
              paidRatio,
              filtered.length,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  '${activeAll.length} ظ…ظ„ظپ ظ†ط´ط·',
                  style: const TextStyle(color: Colors.black54),
                ),
                const Spacer(),
                const Text(
                  'ظ…ظ„ظپط§طھ ط§ظ„ط¥طµظ„ط§ط­',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              _phoneEmptyState()
            else ...[
              ...active.map(_phoneRepairCard),
              if (hasMoreActive)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 14),
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RepairsScreen(showAll: true),
                      ),
                    ),
                    child: Text(
                      'ط¹ط±ط¶ ط¬ظ…ظٹط¹ ط§ظ„ظ…ظ„ظپط§طھ (${activeAll.length})',
                    ),
                  ),
                ),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      '${archived.length}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const Spacer(),
                    const Text(
                      'ط§ظ„ظ…ظ„ظپط§طھ ط§ظ„ظ…ط³ط¯ط¯ط©',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...archived.map(_phoneRepairCard),
              ],
            ],
          ],
        ),
      ),
      floatingActionButton: showFab ? _buildFab() : null,
    );
  }

  Widget _phoneFilterChip(String value) {
    final selected = selectedStatus == value;
    return ChoiceChip(
      label: Text(value),
      selected: selected,
      selectedColor: AppColors.lightGreen,
      checkmarkColor: AppColors.primary,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.lightGrey,
      ),
      onSelected: (_) => setState(() => selectedStatus = value),
    );
  }

  Widget _phoneFinancialSummary(
    double total,
    double paid,
    double remaining,
    double ratio,
    int count,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              const Text(
                'ط­ط§ظ„ط© ط§ظ„طھط­طµظٹظ„',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: AppColors.lightGrey,
            color: AppColors.primary,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _phoneMetric('ظ…ط¯ظپظˆط¹', paid)),
              Expanded(child: _phoneMetric('ظ…طھط¨ظ‚ظٹ', remaining)),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'ظ…ظ„ظپ',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phoneMetric(String label, double value) {
    return Column(
      children: [
        Text(
          MoneyFormatter.format(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  Widget _phoneRepairCard(Repair r) {
    final total = _fileValue(r);
    final paid = _paidValue(r);
    final remaining = (total - paid).clamp(0.0, double.infinity);
    final status = normalizeOrNull(r.paymentStatus, kPaymentStatuses) ??
        r.paymentStatus ??
        'ط؛ظٹط± ظ…ط³ط¯ط¯';
    final statusColor = status == 'ظ…ط³ط¯ط¯'
        ? AppColors.success
        : (status == 'ظ…ط³ط¯ط¯ ط¬ط²ط¦ظٹ' ? Colors.orange : AppColors.danger);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openRepairDetails(r),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.lightGrey),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.directions_car_filled_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${r.vehicleType} آ· ${r.vehicleNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${r.beneficiaryName} آ· ${DateFormat('dd/MM/yyyy').format(r.receivedDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'ط¥ط¬ط±ط§ط،ط§طھ ط§ظ„ظ…ظ„ظپ',
                      onPressed: () => _openQuickActions(r),
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(.10),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'ط§ظ„ظ…طھط¨ظ‚ظٹ ${MoneyFormatter.format(remaining)}',
                      style: TextStyle(
                        color: remaining > 0
                            ? AppColors.danger
                            : AppColors.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ ${MoneyFormatter.format(total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: const Column(
        children: [
          Icon(Icons.car_repair_rounded, size: 42, color: AppColors.primary),
          SizedBox(height: 12),
          Text(
            'ظ„ط§ طھظˆط¬ط¯ ظ…ظ„ظپط§طھ ظ…ط·ط§ط¨ظ‚ط©',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final allRepairs = ref.watch(repairListProvider);

    // ظپظ„طھط±ط©
    final filtered = allRepairs.where((r) {
      final q = searchText.trim().toLowerCase();

      final matchesSearch = q.isEmpty
          ? true
          : (r.vehicleNumber.toLowerCase().contains(q) ||
              r.vehicleType.toLowerCase().contains(q) ||
              r.beneficiaryName.toLowerCase().contains(q));

      final normalizedStatus = normalizeOrNull(
        r.paymentStatus,
        kPaymentStatuses,
      );
      final matchesStatus =
          selectedStatus == 'ط§ظ„ظƒظ„' || normalizedStatus == selectedStatus;

      final matchesType = selectedType == 'ط§ظ„ظƒظ„' ||
          r.beneficiaryType.trim() == selectedType;

      final matchesDate = (fromDate == null || toDate == null)
          ? true
          : (!r.receivedDate.isBefore(fromDate!) &&
              !r.receivedDate.isAfter(toDate!));

      return matchesSearch && matchesStatus && matchesType && matchesDate;
    }).toList();
    filtered.sort((a, b) => b.receivedDate.compareTo(a.receivedDate));

    final activeAll = filtered
        .where(
          (r) =>
              normalizeOrNull(r.paymentStatus, kPaymentStatuses) != 'ظ…ط³ط¯ط¯',
        )
        .toList();

    final active =
        widget.showAll ? activeAll : activeAll.take(initialLimit).toList();

    final hasMoreActive = !widget.showAll && activeAll.length > initialLimit;
    final archived = filtered
        .where(
          (r) =>
              normalizeOrNull(r.paymentStatus, kPaymentStatuses) == 'ظ…ط³ط¯ط¯',
        )
        .toList();

    // âœ… ط¥ط¸ظ‡ط§ط± FAB ظپظ‚ط· ط¥ط°ط§ ظƒط§ظ†طھ ط§ظ„ط´ط§ط´ط© current ظˆظ„ظ‡ط§ ظ‚ظٹظˆط¯ ط­ظ‚ظٹظ‚ظٹط©
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final size = MediaQuery.sizeOf(context);
    final hasLayout = size.width > 0 && size.height > 0;
    final showFab = isCurrent && hasLayout;

    if (MediaQuery.sizeOf(context).width < 600) {
      return _buildPhoneRepairs(
        filtered: filtered,
        active: active,
        activeAll: activeAll,
        archived: archived,
        hasMoreActive: hasMoreActive,
        showFab: showFab,
      );
    }

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: '/repairs')),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'ط¥طµظ„ط§ط­ ط§ظ„ظ…ط±ظƒط¨ط§طھ',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'طھط­ط¯ظٹط¯ ط§ظ„ظپطھط±ط©',
            onPressed: _selectDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'طھط­ظ„ظٹظ„ ط§ظ„ط¨ظٹط§ظ†ط§طھ',
            onPressed: () => Navigator.pushNamed(context, '/repair-analytics'),
          ),
        ],
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/repairs'),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  RepairFilterBar(
                    onSearchChanged: (v) => setState(() => searchText = v),
                    onStatusChanged: (v) => setState(() => selectedStatus = v),
                    onTypeChanged: (v) => setState(() => selectedType = v),
                    onReset: () {
                      setState(() {
                        searchText = '';
                        selectedStatus = 'ط§ظ„ظƒظ„';
                        selectedType = 'ط§ظ„ظƒظ„';
                        fromDate = null;
                        toDate = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  RepairFinancialSummary(
                    repairs: filtered,
                    onTapPaid: () => _handleQuickFilter('paid'),
                    onTapRemaining: () => _handleQuickFilter('remaining'),
                  ),
                  const SizedBox(height: 8),
                  const RepairStatsCards(),
                  const SizedBox(height: 12),
                  AdaptiveRow(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ط¬ظ…ظٹط¹ ط§ظ„ظ…ط±ظƒط¨ط§طھ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.download),
                        onSelected: (v) {
                          if (v == 'pdf') exportToPdf(filtered);
                          if (v == 'excel') exportToExcel(filtered);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'pdf', child: Text('ًں“„ PDF')),
                          PopupMenuItem(
                            value: 'excel',
                            child: Text('ًں“ٹ Excel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (allRepairs.isEmpty)
                    const Center(child: Text('ظ„ط§ طھظˆط¬ط¯ ط¨ظٹط§ظ†ط§طھ'))
                  else
                    Column(
                      children: [
                        ...active.map(
                          (r) => RepairCard(
                            repair: r,
                            onTap: () => _openQuickActions(r),
                            onView: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RepairDetailsScreen(repair: r),
                              ),
                            ).then((updated) {
                              ref
                                  .read(repairListProvider.notifier)
                                  .loadRepairs();
                            }),
                            onEdit: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditRepairScreen(repair: r),
                              ),
                            ).then(
                              (_) => ref
                                  .read(repairListProvider.notifier)
                                  .loadRepairs(),
                            ),
                            onDelete: () async {
                              await RepairDatabaseService.deleteRepair(r.id);
                              ref
                                  .read(repairListProvider.notifier)
                                  .loadRepairs();
                            },
                            onApproveFinalAmount: () =>
                                _approveRepairLedger(context, r),
                          ),
                        ),
                        if (hasMoreActive)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.list),
                              label: Text(
                                'ط¹ط±ط¶ ط¬ظ…ظٹط¹ ط§ظ„ظ…ظ„ظپط§طھ (${activeAll.length})',
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RepairsScreen(showAll: true),
                                  ),
                                );
                              },
                            ),
                          ),
                        if (archived.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Divider(),
                          const Text(
                            'ًں“پ ط§ظ„ظ…ظ„ظپط§طھ ط§ظ„ظ…ط¤ط±ط´ظپط©',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Divider(),
                          ...archived.map(
                            (r) => RepairCard(
                              repair: r,
                              onTap: () => _openQuickActions(r),
                              onView: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RepairDetailsScreen(repair: r),
                                ),
                              ),
                              onEdit: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EditRepairScreen(repair: r),
                                ),
                              ).then(
                                (_) => ref
                                    .read(repairListProvider.notifier)
                                    .loadRepairs(),
                              ),
                              onDelete: () async {
                                await RepairDatabaseService.deleteRepair(r.id);
                                ref
                                    .read(repairListProvider.notifier)
                                    .loadRepairs();
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        RepairSummarySection(repairs: filtered),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: showFab ? _buildFab() : null,
    );
  }
}
