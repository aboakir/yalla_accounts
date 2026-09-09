// 📁 lib/features/repairs/screens/repairs_screen.dart
//
// RepairsScreen — إدارة ملفات الإصلاح
// إصلاح خطأ hit test عبر تعطيل FAB عندما لا تكون الشاشة current أو بدون قيود Layout.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
// import 'package:yalla_accounts/features/finance/screens/add_purchase_screen.dart'; // معطّل مؤقتًا

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/models/repair_list_filter.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_provider.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/edit_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_workflow_service.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_card.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_filter_bar.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_stats_cards.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_summary_section.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_financial_summary.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

// ✅ ثوابت موحّدة
import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class RepairsScreen extends ConsumerStatefulWidget {
  final bool showAll;

  const RepairsScreen({super.key, this.showAll = false});

  @override
  ConsumerState<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends ConsumerState<RepairsScreen> {
  String searchText = '';
  String selectedStatus = 'الكل';
  String selectedType = 'الكل';
  String selectedVehicleStatus = 'الكل';
  RepairArchiveScope selectedArchiveScope = RepairArchiveScope.all;
  DateTime? fromDate;
  DateTime? toDate;
  static const int initialLimit = 10;
  double _fileValue(Repair r) => r.totalFileValue;
  double _paidValue(Repair r) => r.totalPaidAmount;

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'نطاق التاريخ',
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
            // 🔕 شراء قطع غيار — معطّل مؤقتًا
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('🛒 شراء قطع غيار'),
              onTap: () async {
                Navigator.pop(context);
                if (!mounted) {
                  return;
                }
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AdaptiveAlertDialog(
                    title: const Text('غير متاح مؤقتًا'),
                    content: const Text(
                      'ميزة "شراء قطع غيار" ستُفعّل لاحقًا بعد إضافة الشاشة المطلوبة.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('حسنًا'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.build),
              title: const Text('⚙️ إضافة إصلاح جديد'),
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
      selectedStatus = (type == 'paid') ? 'مسدد' : 'غير مسدد';
    });
  }

  Future<void> _deleteRepairSafely(Repair repair) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('حذف ملف الإصلاح'),
        content: const Text(
          'سيختفي الملف من القوائم. إذا كان له أثر محاسبي فسيتم عكسه '
          'وتبقى القيود محفوظة في سجل التدقيق. لا يمكن الحذف قبل معالجة '
          'أي دفعات مسجلة على الملف.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await RepairDatabaseService.deleteRepair(repair.id);
      if (!mounted) return;
      ref.read(repairListProvider.notifier).loadRepairs();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الملف وعكس أثره المالي بأمان.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // 🧾 تصدير PDF
  Future<void> exportToPdf(List<Repair> data) async {
    final df = DateFormat('yyyy-MM-dd');

    // تجهيز بيانات الجدول
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

    // توليد PDF عبر النظام المركزي
    final bytes = await YallaPdfService.generateTablePdf(
      title: "قائمة المركبات",
      headers: [
        'التاريخ',
        'نوع المركبة',
        'رقم المركبة',
        'المستفيد',
        'قيمة الملف',
        'المدفوع',
        'المتبقي',
        'حالة السداد',
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
          content: Text("📄 تم توليد الملف: ${file.path}"),
        ),
      );
    }
  }

  // 📊 تصدير Excel
  Future<void> exportToExcel(List<Repair> data) async {
    final excel = Excel.createExcel();
    final sheet = excel['Vehicles'];
    final df = DateFormat('yyyy-MM-dd');

    sheet.appendRow([
      TextCellValue('التاريخ'),
      TextCellValue('نوع المركبة'),
      TextCellValue('رقم المركبة'),
      TextCellValue('المستفيد'),
      TextCellValue('قيمة الملف'),
      TextCellValue('المدفوع'),
      TextCellValue('المتبقي'),
      TextCellValue('حالة السداد'),
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
        SnackBar(content: Text('✅ تم حفظ Excel في ${file.path}')),
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
              title: const Text('تعديل الملف'),
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
              leading: const Icon(Icons.receipt_long),
              title: const Text('قيود اليومية لهذا الملف'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.journalEntries,
                  arguments: {'relatedRepairId': r.id},
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.manage_history_outlined),
              title: const Text('دفعات الملف / عكس دفعة'),
              subtitle: const Text('عرض دفعات هذا الملف ومعالجة العكس الرسمي'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.payments,
                  arguments: {
                    'repairId': r.id,
                    'allowReverse': true,
                  },
                ).then((_) {
                  ref.read(repairListProvider.notifier).loadRepairs();
                });
              },
            ),
            if (r.remainingAmount > 0.005)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('إضافة دفعة للملف'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(
                    context,
                    AppRoutes.receiptVoucher,
                    arguments: {
                      'repairId': r.id,
                      'clientId': r.clientId,
                      'clientType': r.beneficiaryType,
                    },
                  ).then((updated) {
                    if (updated == true) {
                      ref.read(repairListProvider.notifier).loadRepairs();
                    }
                  });
                },
              ),
            if (r.isArchived && r.status == RepairStatusText.closed)
              ListTile(
                leading: const Icon(
                  Icons.lock_open,
                  color: AppColors.primary,
                ),
                title: const Text('إعادة فتح الملف المغلق'),
                subtitle: const Text('يتطلب سببًا موثقًا ويعيد الملف للتنفيذ'),
                onTap: () {
                  Navigator.pop(context);
                  _reopenClosedRepair(r);
                },
              ),
            if (!r.isArchived) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'إلغاء الملف',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteRepairSafely(r);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reopenClosedRepair(Repair repair) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('إعادة فتح ملف مغلق'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'سبب إعادة الفتح *',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إعادة فتح'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    try {
      await RepairWorkflowService.reopenClosed(
        repairId: repair.id,
        reason: reason.text,
      );
      await ref.read(repairListProvider.notifier).loadRepairs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إعادة فتح الملف بسبب موثق')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      reason.dispose();
    }
  }

  // ===== FAB آمن =====
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
      drawer: Drawer(
        width: MediaQuery.sizeOf(context).width,
        shape: const RoundedRectangleBorder(),
        child: const SafeArea(
          child: YallaSidebar(currentRoute: '/repairs'),
        ),
      ),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'إصلاح المركبات',
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
                child: Text('تحديد الفترة'),
              ),
              PopupMenuItem(
                value: 'analytics',
                child: Text('تحليل البيانات'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(value: 'pdf', child: Text('تصدير PDF')),
              PopupMenuItem(value: 'excel', child: Text('تصدير Excel')),
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
              inputFormatters: const [YallaDigitNormalizer()],
              onChanged: (v) => setState(() => searchText = v),
              decoration: InputDecoration(
                hintText: 'ابحث بالمركبة، الرقم أو المستفيد...',
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
                  _phoneFilterChip('الكل'),
                  const SizedBox(width: 8),
                  _phoneFilterChip('غير مسدد'),
                  const SizedBox(width: 8),
                  _phoneFilterChip('مسدد جزئي'),
                  const SizedBox(width: 8),
                  _phoneFilterChip('مسدد'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _phoneArchiveChip(RepairArchiveScope.all),
                  const SizedBox(width: 8),
                  _phoneArchiveChip(RepairArchiveScope.active),
                  const SizedBox(width: 8),
                  _phoneArchiveChip(RepairArchiveScope.archived),
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
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  '${activeAll.length} ملف نشط',
                  style: const TextStyle(color: Colors.black54),
                ),
                const Text(
                  'ملفات الإصلاح',
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
                      'عرض جميع الملفات (${activeAll.length})',
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
                      'الأرشيف',
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
      bottomNavigationBar: Builder(
        builder: (navContext) => YallaMobileBottomNav(
          currentRoute: '/repairs',
          onMore: () => Scaffold.of(navContext).openDrawer(),
        ),
      ),
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

  Widget _phoneArchiveChip(RepairArchiveScope value) {
    final selected = selectedArchiveScope == value;
    return ChoiceChip(
      avatar: Icon(
        value == RepairArchiveScope.archived
            ? Icons.archive_outlined
            : value == RepairArchiveScope.active
                ? Icons.inventory_2_outlined
                : Icons.all_inbox_outlined,
        size: 16,
      ),
      label: Text(value.label),
      selected: selected,
      selectedColor: AppColors.lightGreen,
      checkmarkColor: AppColors.primary,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.lightGrey,
      ),
      onSelected: (_) => setState(() => selectedArchiveScope = value),
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
                'حالة التحصيل',
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
              Expanded(child: _phoneMetric('مدفوع', paid)),
              Expanded(child: _phoneMetric('متبقي', remaining)),
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
                      'ملف',
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
        'غير مسدد';
    final statusColor = status == 'مسدد'
        ? AppColors.success
        : (status == 'مسدد جزئي' ? Colors.orange : AppColors.danger);
    final profilePath = r.thumbnailPath?.trim();

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
                    YallaStoredImage(
                      storedPath: profilePath,
                      width: 48,
                      height: 48,
                      cacheWidth: 180,
                      borderRadius: BorderRadius.circular(14),
                      fallback: Container(
                        width: 48,
                        height: 48,
                        color: AppColors.lightGreen,
                        child: const Icon(
                          Icons.directions_car_filled_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${r.vehicleType} · ${r.vehicleNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${r.beneficiaryName} · ${DateFormat('dd/MM/yyyy').format(r.receivedDate)}',
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
                      tooltip: 'إجراءات الملف',
                      onPressed: () => _openQuickActions(r),
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.start,
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(.08),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        normalizeValue(
                              r.vehicleStatus,
                              kVehicleStatuses,
                              aliases: kVehicleStatusAliases,
                            ) ??
                            r.vehicleStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'المتبقي ${MoneyFormatter.format(remaining)}',
                          style: TextStyle(
                            color: remaining > 0
                                ? AppColors.danger
                                : AppColors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'الإجمالي ${MoneyFormatter.format(total)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
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
            'لا توجد ملفات مطابقة',
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

    // P06 — canonical repair-list filtering.
    final filter = RepairListFilter(
      search: searchText,
      paymentStatus: selectedStatus,
      beneficiaryType: selectedType,
      vehicleStatus: selectedVehicleStatus,
      archiveScope: selectedArchiveScope,
      from: fromDate,
      to: toDate,
    );

    final filtered = allRepairs.where(filter.matches).toList()
      ..sort((a, b) => b.receivedDate.compareTo(a.receivedDate));

    final activeAll = filtered.where((repair) => !repair.isArchived).toList();

    final active =
        widget.showAll ? activeAll : activeAll.take(initialLimit).toList();

    final hasMoreActive = !widget.showAll && activeAll.length > initialLimit;

    final archived = filtered.where((repair) => repair.isArchived).toList();

    // ✅ إظهار FAB فقط إذا كانت الشاشة current ولها قيود حقيقية
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
          'إصلاح المركبات',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'تحديد الفترة',
            onPressed: _selectDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'تحليل البيانات',
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
                    searchQuery: searchText,
                    selectedPaymentStatus: selectedStatus,
                    selectedType: selectedType,
                    selectedVehicleStatus: selectedVehicleStatus,
                    selectedArchiveScope: selectedArchiveScope,
                    onSearchChanged: (v) => setState(() => searchText = v),
                    onPaymentStatusChanged: (v) =>
                        setState(() => selectedStatus = v),
                    onTypeChanged: (v) => setState(() => selectedType = v),
                    onVehicleStatusChanged: (v) =>
                        setState(() => selectedVehicleStatus = v),
                    onArchiveScopeChanged: (v) =>
                        setState(() => selectedArchiveScope = v),
                    onReset: () {
                      setState(() {
                        searchText = '';
                        selectedStatus = 'الكل';
                        selectedType = 'الكل';
                        selectedVehicleStatus = 'الكل';
                        selectedArchiveScope = RepairArchiveScope.all;
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
                        'جميع المركبات',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.download),
                        onSelected: (v) {
                          if (v == 'pdf') exportToPdf(filtered);
                          if (v == 'excel') exportToExcel(filtered);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'pdf', child: Text('📄 PDF')),
                          PopupMenuItem(
                            value: 'excel',
                            child: Text('📊 Excel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (allRepairs.isEmpty)
                    const Center(child: Text('لا توجد بيانات'))
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
                            onDelete: () => _deleteRepairSafely(r),
                          ),
                        ),
                        if (hasMoreActive)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.list),
                              label: Text(
                                'عرض جميع الملفات (${activeAll.length})',
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
                            '📁 الملفات المؤرشفة',
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
                              onDelete: () => _deleteRepairSafely(r),
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
