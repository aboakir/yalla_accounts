// 📁 lib/features/insurance_agent/policies/widgets/policy_mobile_card.dart
//
// PolicyMobileCard — Single policy card for Mobile/Tablet
// Uses PolicyActionIcon + PolicyDateUtils

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';

import '../utils/policy_date_utils.dart';
import 'policy_action_icon.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PolicyMobileCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateFormat dateFormat;

  final Future<void> Function() onDetails;
  final Future<void> Function() onEdit;
  final Future<void> Function() onPayments;
  final Future<void> Function() onDelete;

  const PolicyMobileCard({
    super.key,
    required this.row,
    required this.dateFormat,
    required this.onDetails,
    required this.onEdit,
    required this.onPayments,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final plate = (row['vehicle_plate'] ?? '').toString();
    final insured = (row['insured_name'] ?? '').toString();
    final phone = (row['insured_phone'] ?? '').toString();
    final company = (row['company_name'] ?? '').toString();
    final isVip = (row['is_vip'] ?? 0) == 1;

    final start = PolicyDateUtils.parsePolicyDate(row['start_date']);
    final end = PolicyDateUtils.parsePolicyDate(row['end_date']);

    final status = PolicyDateUtils.resolvePolicyStatus(row, soonDays: 12);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x10000000),
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AdaptiveRow(
            children: [
              if (isVip)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: const Text(
                    'VIP',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              const Spacer(),
              Text(
                plate,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Actions
          AdaptiveRow(
            children: [
              PolicyActionIcon(
                tip: 'حذف',
                icon: Icons.delete,
                onTap: () => onDelete(),
                color: Colors.red,
              ),
              const SizedBox(width: 8),
              PolicyActionIcon(
                tip: 'الدفعات',
                icon: Icons.payments,
                onTap: () => onPayments(),
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              PolicyActionIcon(
                tip: 'تعديل',
                icon: Icons.edit,
                onTap: () => onEdit(),
                color: Colors.teal,
              ),
              const SizedBox(width: 8),
              PolicyActionIcon(
                tip: 'معاينة',
                icon: Icons.visibility,
                onTap: () => onDetails(),
                color: AppColors.primary,
              ),
              const Spacer(),
            ],
          ),

          const SizedBox(height: 12),

          Text('المؤمَّن له: $insured', textAlign: TextAlign.right),
          Text('الهاتف: $phone', textAlign: TextAlign.right),
          Text('الشركة: $company', textAlign: TextAlign.right),

          const SizedBox(height: 10),

          Text(
            'الحالة: ${status.label}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: status.color,
            ),
          ),

          const SizedBox(height: 6),

          if (start != null)
            Text(
              'بداية: ${dateFormat.format(start)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),

          if (end != null)
            Text(
              'نهاية: ${dateFormat.format(end)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
