// 📁 lib/features/home/widgets/timeline_overview_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/providers/timeline_provider.dart';

/// Widget لعرض الملخص الزمني (Timeline Overview) بشكل مبسط عبر قائمة أحداث مرتبة
class TimelineOverviewWidget extends ConsumerWidget {
  const TimelineOverviewWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineAsync = ref.watch(timelineProvider);

    return timelineAsync.when(
      data: (stats) {
        if (stats.events.isEmpty) {
          return const Center(child: Text('لا توجد أحداث لعرضها'));
        }

        return Column(
          children: stats.events.map((e) {
            final start = DateFormat('yyyy/MM/dd').format(e.start);
            final end = DateFormat('yyyy/MM/dd').format(e.end);
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(e.title),
                subtitle: Text('من $start إلى $end'),
                trailing: Text(
                  e.status,
                  style: TextStyle(
                    color: e.status.toLowerCase() == 'completed'
                        ? Colors.green
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  // navigation to details if needed
                },
              ),
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const SizedBox(
        height: 200,
        child: Center(child: Text('خطأ في تحميل الملخص الزمني')),
      ),
    );
  }
}
