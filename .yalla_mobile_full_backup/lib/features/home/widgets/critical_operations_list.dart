// 📁 lib/features/home/widgets/critical_operations_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/providers/critical_ops_provider.dart';

/// Widget لعرض قائمة "العمليات الحرجة" (متأخرة أو قريبة الانتهاء)
class CriticalOperationsList extends ConsumerWidget {
  /// دالة اختيار عملية للانتقال للتفاصيل
  final void Function(CriticalOperation) onOperationTap;

  const CriticalOperationsList({
    super.key,
    required this.onOperationTap,
    required bool horizontal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opsAsync = ref.watch(criticalOpsProvider);

    return opsAsync.when(
      data: (ops) {
        if (ops.isEmpty) {
          return const Center(
            child: Text('لا توجد عمليات حرجة في الوقت الحالي'),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ops.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final op = ops[index];
            final due = DateFormat('yyyy/MM/dd').format(op.dueDate);
            return ListTile(
              leading: const Icon(Icons.warning, color: Colors.redAccent),
              title: Text('سيارة: ${op.vehicleNumber}'),
              subtitle: Text('الحالة: ${op.status} • موعد التسليم: $due'),
              onTap: () => onOperationTap(op),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => const Center(
        child: Text('خطأ في جلب العمليات الحرجة'),
      ),
    );
  }
}

extension on CriticalOperation {
  get status => null;
}
