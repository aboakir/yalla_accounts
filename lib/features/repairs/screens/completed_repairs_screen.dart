import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_workflow_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class CompletedRepairsScreen extends ConsumerStatefulWidget {
  const CompletedRepairsScreen({super.key});

  @override
  ConsumerState<CompletedRepairsScreen> createState() =>
      _CompletedRepairsScreenState();
}

class _CompletedRepairsScreenState
    extends ConsumerState<CompletedRepairsScreen> {
  late Future<List<Repair>> _future;
  final _date = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = RepairDatabaseService.getAllRepairs().then(
      (items) => items
          .where((repair) =>
              repair.isArchived && repair.status == RepairStatusText.closed)
          .toList(),
    );
  }

  Future<void> _reopen(Repair repair) async {
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
      if (!mounted) return;
      setState(_reload);
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

  Widget _content() {
    return FutureBuilder<List<Repair>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('تعذر تحميل الملفات المغلقة: ${snapshot.error}'));
        }
        final repairs = snapshot.data ?? const <Repair>[];
        if (repairs.isEmpty) {
          return const Center(
            child: Text('لا توجد ملفات مغلقة رسميًا حتى الآن'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _future;
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: repairs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final repair = repairs[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.lock_outline),
                  ),
                  title: Text(
                    '${repair.vehicleType} ${repair.vehicleModel}'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('رقم المركبة: ${repair.vehicleNumber}'),
                      Text('المستفيد: ${repair.beneficiaryName}'),
                      Text('استلام: ${_date.format(repair.receivedDate)}'),
                      Text(
                          'قيمة الملف: ${MoneyFormatter.format(repair.fileValue)}'),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'open') {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RepairDetailsScreen(repair: repair),
                          ),
                        );
                        if (mounted) setState(_reload);
                      } else if (value == 'reopen') {
                        await _reopen(repair);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'open',
                        child: Text('عرض الملف'),
                      ),
                      PopupMenuItem(
                        value: 'reopen',
                        child: Text('إعادة فتح بسبب موثق'),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RepairDetailsScreen(repair: repair),
                      ),
                    );
                    if (mounted) setState(_reload);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/repairs/completed'),
            ),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'المركبات المغلقة',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/repairs/completed'),
            ),
          Expanded(child: _content()),
        ],
      ),
    );
  }
}
