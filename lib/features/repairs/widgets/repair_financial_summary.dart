import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class RepairFinancialSummary extends StatelessWidget {
  final List<Repair> repairs;
  final VoidCallback onTapRemaining;
  final VoidCallback onTapPaid;

  const RepairFinancialSummary({
    super.key,
    required this.repairs,
    required this.onTapRemaining,
    required this.onTapPaid,
  });

  @override
  Widget build(BuildContext context) {
    // ================================
    //  حساب الإجماليات (النسخة الصحيحة)
    // ================================
    final totalValue =
        repairs.fold<double>(0, (sum, r) => sum + r.totalFileValue.toDouble());

    final totalPaid =
        repairs.fold<double>(0, (sum, r) => sum + r.totalPaidAmount.toDouble());

    final totalRemaining = (totalValue - totalPaid).clamp(0, totalValue);

    // ================================
    // تنسيق الأرقام
    // ================================
    final formatter = NumberFormat.decimalPattern('en_US');

    // نسبة السداد للشريط الرمادي
    final paidRatio = totalValue > 0 ? (totalPaid / totalValue) : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== العنوان =====
          const Text(
            '📊 الملخص المالي',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),

          // ===== الأعمدة المالية =====
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 350;
              return isWide
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSummaryItem(
                          label: 'قيمة الملفات',
                          amount: MoneyFormatter.format(totalValue),
                          color: AppColors.primary,
                          tooltip: 'إجمالي قيمة جميع ملفات الإصلاح',
                        ),
                        GestureDetector(
                          onTap: onTapPaid,
                          child: _buildSummaryItem(
                            label: 'المدفوع',
                            amount: MoneyFormatter.format(totalPaid),
                            color: Colors.green,
                            tooltip: 'إجمالي المبالغ المدفوعة',
                          ),
                        ),
                        GestureDetector(
                          onTap: onTapRemaining,
                          child: _buildSummaryItem(
                            label: 'المتبقي',
                            amount: MoneyFormatter.format(totalRemaining),
                            color: Colors.red,
                            tooltip: 'إجمالي المبالغ المتبقية',
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildSummaryItem(
                          label: 'قيمة الملفات',
                          amount: MoneyFormatter.format(totalValue),
                          color: AppColors.primary,
                          tooltip: 'إجمالي قيمة جميع ملفات الإصلاح',
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: onTapPaid,
                          child: _buildSummaryItem(
                            label: 'المدفوع',
                            amount: MoneyFormatter.format(totalPaid),
                            color: Colors.green,
                            tooltip: 'إجمالي المبالغ المدفوعة',
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: onTapRemaining,
                          child: _buildSummaryItem(
                            label: 'المتبقي',
                            amount: MoneyFormatter.format(totalRemaining),
                            color: Colors.red,
                            tooltip: 'إجمالي المبالغ المتبقية',
                          ),
                        ),
                      ],
                    );
            },
          ),

          const SizedBox(height: 16),

          // ===== شريط التقدم =====
          Tooltip(
            message: 'نسبة الإنجاز: ${(paidRatio * 100).toStringAsFixed(1)}%',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'نسبة السداد',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: paidRatio,
                    minHeight: 8,
                    backgroundColor: Colors.grey[300],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(paidRatio * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // عنصر بطاقة لكل رقم
  Widget _buildSummaryItem({
    required String label,
    required String amount,
    required Color color,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              amount,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
