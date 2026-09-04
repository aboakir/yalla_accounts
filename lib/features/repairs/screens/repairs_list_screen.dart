// 📁 lib/features/repairs/screens/repairs_list_screen.dart
//
// RepairsListScreen — شاشة قائمة ملفات الإصلاح
// - عرض صورة غلاف thumbnail لكل ملف عبر RepairThumb.
// - التحويل إلى RepairsService.
// - الحفظ والتعديل المحاسبي تلقائيان؛ لا توجد خطوة اعتماد يدوية.
// - تصدير Excel وZIP-PDF عبر RepairExportService.
// - تحديث الصور بعد الرجوع ودعم السحب للتحديث.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db/db_service.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/screens/add_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/edit_repair_screen.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';

import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_export_excel.dart';

import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairsListScreen extends ConsumerStatefulWidget {
  const RepairsListScreen({super.key});

  @override
  ConsumerState<RepairsListScreen> createState() => _RepairsListScreenState();
}

class _RepairsListScreenState extends ConsumerState<RepairsListScreen> {
  List<Repair> repairs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRepairs();
  }

  Future<void> _loadRepairs() async {
    final svc = await RepairsService.instance();
    final result = await svc.list(newestFirst: true);
    if (!mounted) return;
    setState(() {
      repairs = result;
      isLoading = false;
    });
  }

  Future<void> _deleteRepair(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text(
          'سيختفي الملف من القوائم، ويُعكس أثره المحاسبي مع إبقاء سجل التدقيق. '
          'إذا كانت عليه دفعات فيجب معالجتها أولًا.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      final svc = await RepairsService.instance();
      await svc.deleteRepair(id);
      if (!mounted) return;
      setState(() => repairs.removeWhere((repair) => repair.id == id));
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

  Future<void> _exportExcel() async {
    try {
      final file = await RepairExportService.exportExcel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء Excel:\n${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
    }
  }

  Future<void> _exportPdfZip() async {
    try {
      final file = await RepairExportService.exportPdfZip();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء ZIP:\n${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: '/repairs')),
      appBar: AppBar(
        title: const Text('ملفات الإصلاح'),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تصدير Excel',
            icon: const Icon(Icons.table_chart),
            onPressed: _exportExcel,
          ),
          IconButton(
            tooltip: 'تصدير ZIP-PDF',
            icon: const Icon(Icons.archive),
            onPressed: _exportPdfZip,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddRepairScreen()),
          );
          await _loadRepairs();
        },
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        child: const Icon(Icons.add),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/repairs'),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : repairs.isEmpty
                    ? const Center(child: Text('لا توجد ملفات إصلاح حتى الآن.'))
                    : RefreshIndicator(
                        onRefresh: _loadRepairs,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: repairs.length,
                          itemBuilder: (_, index) {
                            final repair = repairs[index];

                            final insDisplay = normalizeOrNull(
                                    repair.insuranceStatus,
                                    kInsuranceFollowups) ??
                                repair.insuranceStatus;

                            final vehicleStatus = normalizeValue(
                                  repair.vehicleStatus,
                                  kVehicleStatuses,
                                  aliases: kVehicleStatusAliases,
                                ) ??
                                repair.vehicleStatus;

                            final paymentStatus = normalizeOrNull(
                                    repair.paymentStatus, kPaymentStatuses) ??
                                repair.paymentStatus;

                            Color statusColor() {
                              if (vehicleStatus == 'تم التسليم') {
                                return Colors.green;
                              }
                              if (vehicleStatus == 'قيد الإصلاح') {
                                return Colors.orange;
                              }
                              if (vehicleStatus == 'جاهزة للتسليم') {
                                return Colors.blueAccent;
                              }
                              return Colors.grey;
                            }

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    leading: FutureBuilder<String?>(
                                      future: DBService.getRepairThumbnailPath(
                                          repair.id),
                                      builder: (context, snap) {
                                        String? thumb = snap.data;

                                        // 1) إذا في thumbnail من قاعدة البيانات – استخدمها
                                        if (thumb != null && thumb.isNotEmpty) {
                                          return ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.file(
                                              File(thumb),
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                            ),
                                          );
                                        }

                                        // 2) fallback للصورة الأولى
                                        final fallback =
                                            repair.imagePaths.isNotEmpty
                                                ? repair.imagePaths.first
                                                : null;

                                        if (fallback != null) {
                                          return ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.file(
                                              File(fallback),
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                            ),
                                          );
                                        }

                                        // 3) أيقونة افتراضية
                                        return Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: AppColors.lightGrey,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                              Icons.directions_car,
                                              color: AppColors.primary),
                                        );
                                      },
                                    ),
                                    title: Text(
                                      '${repair.vehicleType} - ${repair.vehicleModel}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            'الاسم: ${repair.beneficiaryName}'),
                                        Text(
                                          'تاريخ الاستلام: ${DateFormat('yyyy-MM-dd').format(repair.receivedDate)}',
                                        ),
                                        Text(
                                          'الحالة: $vehicleStatus',
                                          style: TextStyle(
                                            color: statusColor(),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'حالة السداد: $paymentStatus',
                                          style: const TextStyle(
                                            color: Colors.teal,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (repair.beneficiaryType ==
                                            'شركة تأمين')
                                          Text(
                                            'متابعة التأمين: ${insDisplay.isNotEmpty ? insDisplay : 'غير محددة'}',
                                            style: const TextStyle(
                                              color: Colors.deepPurple,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: AdaptiveRow(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () async {
                                            await Navigator.push<Repair>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    EditRepairScreen(
                                                        repair: repair),
                                              ),
                                            );
                                            await _loadRepairs(); // تحديث القائمة والصور
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () =>
                                              _deleteRepair(repair.id),
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RepairDetailsScreen(
                                              repair: repair),
                                        ),
                                      );
                                      await _loadRepairs(); // تحديث بعد الرجوع
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
