// 📁 lib/features/home/widgets/smart_alerts_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/providers/smart_alerts_provider.dart';

/// Banner لعرض التنبيهات الذكية أعلى الشاشة
class SmartAlertsBanner extends ConsumerWidget {
  /// عند الضغط على التنبيه
  final void Function(SmartAlert) onAlertTap;

  const SmartAlertsBanner({
    super.key,
    required this.onAlertTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(smartAlertsProvider);

    return alertsAsync.when(
      data: (alerts) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        // نعرض أول تنبيه أو ملخص للعدد
        final first = alerts.first;
        return Container(
          width: double.infinity,
          color: first.type == AlertType.critical
              ? Colors.red.shade50
              : first.type == AlertType.warning
                  ? Colors.orange.shade50
                  : Colors.blue.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GestureDetector(
            onTap: () => onAlertTap(first),
            child: Row(
              children: [
                Icon(
                  first.type == AlertType.critical
                      ? Icons.error_outline
                      : first.type == AlertType.warning
                          ? Icons.warning_amber_outlined
                          : Icons.info_outline,
                  color: first.type == AlertType.critical
                      ? Colors.red
                      : first.type == AlertType.warning
                          ? Colors.orange
                          : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    first.message,
                    style: TextStyle(
                      color: first.type == AlertType.critical
                          ? Colors.red.shade800
                          : first.type == AlertType.warning
                              ? Colors.orange.shade800
                              : Colors.blue.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (alerts.length > 1) ...[
                  const SizedBox(width: 8),
                  Text(
                    '+${alerts.length - 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }
}
