import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_stats_provider.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairStatsCards extends ConsumerWidget {
  const RepairStatsCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalRepairs = ref.watch(totalRepairsCountProvider);
    final completedRepairs =
        ref.watch(repairsCountByStatusProvider('تم التسليم'));
    final totalFileValue = ref.watch(totalFileValueProvider);
    final totalPaid = ref.watch(totalPaidAmountProvider);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildCard(
          title: 'إجمالي الملفات',
          valueWidget: totalRepairs.when(
            data: (val) => Text('$val ملف', style: _valueStyle),
            loading: () => _loadingWidget(),
            error: (_, __) => _errorWidget(),
          ),
          icon: Icons.folder,
          color: AppColors.primary,
        ),
        _buildCard(
          title: 'الملفات المسلمة',
          valueWidget: completedRepairs.when(
            data: (val) => Text('$val ملف', style: _valueStyle),
            loading: () => _loadingWidget(),
            error: (_, __) => _errorWidget(),
          ),
          icon: Icons.done_all,
          color: AppColors.primary,
        ),
        _buildCard(
          title: 'القيمة الإجمالية',
          valueWidget: totalFileValue.when(
            data: (val) => Text(MoneyFormatter.format(val), style: _valueStyle),
            loading: () => _loadingWidget(),
            error: (_, __) => _errorWidget(),
          ),
          icon: Icons.attach_money,
          color: Colors.amber[700]!,
        ),
        _buildCard(
          title: 'المبالغ المدفوعة',
          valueWidget: totalPaid.when(
            data: (val) => Text(MoneyFormatter.format(val), style: _valueStyle),
            loading: () => _loadingWidget(),
            error: (_, __) => _errorWidget(),
          ),
          icon: Icons.payments,
          color: Colors.blueGrey,
        ),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required Widget valueWidget,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 220,
        height: 120,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withOpacity(0.1),
        ),
        child: AdaptiveRow(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  valueWidget,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _valueStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  Widget _loadingWidget() => const CircularProgressIndicator(strokeWidth: 2);
  Widget _errorWidget() => const Icon(Icons.error, color: Colors.red);
}
