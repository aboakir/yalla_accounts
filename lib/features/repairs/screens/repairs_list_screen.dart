// 📁 lib/features/repairs/screens/repairs_list_screen.dart
//
// RepairsListScreen — شاشة قائمة ملفات الإصلاح
// - عرض صورة غلاف thumbnail لكل ملف عبر RepairThumb.
// - التحويل إلى RepairsService.
// - الحفظ والتعديل المحاسبي تلقائيان؛ لا توجد خطوة اعتماد يدوية.
// - تصدير Excel وZIP-PDF عبر RepairExportService.
// - تحديث الصور بعد الرجوع ودعم السحب للتحديث.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import 'package:yalla_accounts/shared/widgets/loading.dart';
import 'package:yalla_accounts/shared/widgets/error_widget.dart';
import 'package:yalla_accounts/shared/widgets/empty_state.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';

class RepairsListScreen extends ConsumerStatefulWidget {
  const RepairsListScreen({super.key});

  @override
  ConsumerState<RepairsListScreen> createState() => _RepairsListScreenState();
}

class _RepairsListScreenState extends ConsumerState<RepairsListScreen> {
  static const int _pageSize = 40;

  final ScrollController _scrollController = ScrollController();
  List<Repair> repairs = [];
  bool isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _loadError;
  String? _loadMoreError;
  int _nextOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadRepairs();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _isLoadingMore ||
        isLoading) {
      return;
    }
    if (_scrollController.position.extentAfter < 700) {
      _loadMore();
    }
  }

  Future<void> _loadRepairs() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        _loadError = null;
        _loadMoreError = null;
        _nextOffset = 0;
        _hasMore = true;
      });
    }
    try {
      final svc = await RepairsService.instance();
      final result = await svc.list(
        newestFirst: true,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        repairs = result;
        _nextOffset = result.length;
        _hasMore = result.length == _pageSize;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    try {
      final svc = await RepairsService.instance();
      final result = await svc.list(
        newestFirst: true,
        limit: _pageSize,
        offset: _nextOffset,
      );
      if (!mounted) return;
      setState(() {
        repairs = [...repairs, ...result];
        _nextOffset += result.length;
        _hasMore = result.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = error.toString();
      });
    }
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
      await _loadRepairs();
      if (!mounted) return;
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
                ? const LoadingWidget(message: 'جاري تحميل ملفات الإصلاح...')
                : _loadError != null
                    ? ErrorDisplay(
                        message: 'تعذر تحميل ملفات الإصلاح.\n$_loadError',
                        onRetry: _loadRepairs,
                      )
                    : repairs.isEmpty
                        ? YallaEmptyState(
                            title: 'لا توجد ملفات إصلاح حتى الآن',
                            message: 'ابدأ بإضافة أول مركبة إلى الورشة.',
                            icon: Icons.car_repair_outlined,
                            actionLabel: 'ملف جديد',
                            onAction: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AddRepairScreen(),
                                ),
                              );
                              await _loadRepairs();
                            },
                          )
                        : RefreshIndicator(
                            onRefresh: _loadRepairs,
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: repairs.length + 1,
                              itemBuilder: (_, index) {
                                if (index == repairs.length) {
                                  if (_loadMoreError != null) {
                                    return Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Center(
                                        child: TextButton.icon(
                                          onPressed: _loadMore,
                                          icon: const Icon(Icons.refresh),
                                          label:
                                              const Text('إعادة تحميل المزيد'),
                                        ),
                                      ),
                                    );
                                  }
                                  if (_isLoadingMore) {
                                    return const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return const SizedBox(height: 24);
                                }
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
                                        repair.paymentStatus,
                                        kPaymentStatuses) ??
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        leading: YallaStoredImage(
                                          storedPath: (repair.thumbnailPath ??
                                                      '')
                                                  .trim()
                                                  .isNotEmpty
                                              ? repair.thumbnailPath
                                              : (repair.imagePaths.isNotEmpty
                                                  ? repair.imagePaths.first
                                                  : null),
                                          width: 56,
                                          height: 56,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          fallback: Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              color: AppColors.lightGrey,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.directions_car,
                                              color: AppColors.primary,
                                            ),
                                          ),
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
                                              builder: (_) =>
                                                  RepairDetailsScreen(
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
