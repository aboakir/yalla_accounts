import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import '../utils/policy_date_utils.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PolicyTableRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final int index;
  final DateFormat dateFormat;

  final VoidCallback onDetails;
  final VoidCallback onEdit;
  final VoidCallback onPayments;
  final VoidCallback onDelete;

  const PolicyTableRow({
    super.key,
    required this.row,
    required this.index,
    required this.dateFormat,
    required this.onDetails,
    required this.onEdit,
    required this.onPayments,
    required this.onDelete,
  });

  Widget _cellText(
    String text, {
    Color? color,
    FontWeight? weight,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: color ?? Colors.grey.shade900,
          fontWeight: weight ?? FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _icon({
    required String tip,
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Tooltip(
      message: tip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 20),
        splashRadius: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = PolicyDateUtils.parsePolicyDate(row['start_date']);
    final end = PolicyDateUtils.parsePolicyDate(row['end_date']);

    final status = PolicyDateUtils.resolvePolicyStatus(row, soonDays: 12);
    final isVip = (row['is_vip'] ?? 0) == 1;

    return Container(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFFBFBFB),
        border: const Border(
          bottom: BorderSide(color: Color(0x11000000)),
        ),
      ),
      child: AdaptiveRow(
        children: [
          Expanded(flex: 12, child: _cellText('${row['vehicle_plate'] ?? ''}')),
          Expanded(flex: 15, child: _cellText('${row['insured_name'] ?? ''}')),
          Expanded(flex: 12, child: _cellText('${row['insured_phone'] ?? ''}')),
          Expanded(flex: 13, child: _cellText('${row['company_name'] ?? ''}')),
          Expanded(
            flex: 10,
            child: _cellText(start == null ? '-' : dateFormat.format(start)),
          ),
          Expanded(
            flex: 10,
            child: _cellText(end == null ? '-' : dateFormat.format(end)),
          ),
          Expanded(
            flex: 10,
            child: _cellText(
              status.label,
              color: status.color,
              weight: FontWeight.w900,
            ),
          ),
          Expanded(flex: 6, child: _cellText(isVip ? 'نعم' : 'لا')),

          // ✅ إجراءات: نفس السطر دائمًا + بدون مربعات
          Expanded(
            flex: 13,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 150),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: AdaptiveRow(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _icon(
                          tip: 'حذف',
                          icon: Icons.delete,
                          onTap: onDelete,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 6),
                        _icon(
                          tip: 'الدفعات',
                          icon: Icons.payments,
                          onTap: onPayments,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        _icon(
                          tip: 'تعديل',
                          icon: Icons.edit,
                          onTap: onEdit,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 6),
                        _icon(
                          tip: 'معاينة',
                          icon: Icons.visibility,
                          onTap: onDetails,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
