import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_stats_provider.dart';

class PaymentStatusPieChart extends ConsumerWidget {
  const PaymentStatusPieChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(repairsCountByPaymentStatusProvider);

    return asyncData.when(
      data: (data) {
        final total = data.values.fold<int>(0, (sum, v) => sum + v);
        if (total == 0) {
          return const Center(child: Text('لا توجد بيانات للعرض'));
        }

        final colors = [Colors.green, Colors.orange, Colors.red];
        final labels = ['مسدد', 'مسدد جزئي', 'غير مسدد'];
        final values = [
          data['مسدد'] ?? 0,
          data['مسدد جزئي'] ?? 0,
          data['غير مسدد'] ?? 0,
        ];

        return Column(
          children: [
            const Text(
              'توزيع الملفات حسب حالة السداد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sections: List.generate(3, (i) {
                    final percent = (values[i] / total) * 100;
                    return PieChartSectionData(
                      color: colors[i],
                      value: values[i].toDouble(),
                      title: '${percent.toStringAsFixed(1)}%',
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: List.generate(3, (i) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, color: colors[i]),
                    const SizedBox(width: 6),
                    Text('${labels[i]}: ${values[i]}'),
                  ],
                );
              }),
            )
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('خطأ في تحميل البيانات: $err')),
    );
  }
}
