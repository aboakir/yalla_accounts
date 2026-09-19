// 📁 lib/features/cheques/widgets/cheque_card.dart
//
// ChequeCard — بطاقة عرض الشيك (متوسطة الحجم)
// --------------------------------------------------------
// - ألوان حسب الحالة (Pending/Collected/Returned/...)
// - دعم الضغط (onTap) والضغط المطوّل (onLongPress)
// - متوافقة مع الهوية البصرية YALLA
// - تعمل على الهاتف والكمبيوتر
// - بدون أي بيانات وهمية

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ChequeCard extends StatelessWidget {
  final Cheque cheque;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  ChequeCard({
    super.key,
    required this.cheque,
    this.onTap,
    this.onLongPress,
  });

  final _df = DateFormat('yyyy-MM-dd');

  // --------------------------------------------------------
  // ألوان الحالات
  // --------------------------------------------------------
  Color _statusColor(ChequeStatus status) {
    return switch (status) {
      ChequeStatus.pending => Colors.amber.shade700,
      ChequeStatus.received => Colors.teal.shade700,
      ChequeStatus.held => Colors.amber.shade800,
      ChequeStatus.deposited => Colors.blue.shade700,
      ChequeStatus.collected => AppColors.primary,
      ChequeStatus.endorsed => Colors.indigo.shade700,
      ChequeStatus.issued => Colors.deepOrange.shade700,
      ChequeStatus.delivered => Colors.blueGrey.shade700,
      ChequeStatus.presented => Colors.purple.shade700,
      ChequeStatus.cleared => Colors.green.shade700,
      ChequeStatus.returned => Colors.red.shade600,
      ChequeStatus.cancelled => Colors.grey.shade700,
    };
  }

  String _statusLabel(ChequeStatus status) {
    return switch (status) {
      ChequeStatus.pending => 'قديم/معلّق',
      ChequeStatus.received => 'مستلم',
      ChequeStatus.held => 'محتفظ به',
      ChequeStatus.deposited => 'مودع في البنك',
      ChequeStatus.collected => 'مُحصَّل',
      ChequeStatus.endorsed => 'مظهّر',
      ChequeStatus.issued => 'صادر',
      ChequeStatus.delivered => 'مسلّم',
      ChequeStatus.presented => 'مقدم/مستحق',
      ChequeStatus.cleared => 'مصروف من البنك',
      ChequeStatus.returned => 'راجع',
      ChequeStatus.cancelled => 'ملغى',
    };
  }

  String _typeLabel(ChequeType type) {
    switch (type) {
      case ChequeType.incoming:
        return 'وارد';
      case ChequeType.outgoing:
        return 'صادر';
      case ChequeType.collection:
        return 'قيد التحصيل';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(cheque.status);

    return Card(
      elevation: 2,
      color: AppColors.cardBackground,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // --------------------------------------------------------
              // الصف العلوي
              // --------------------------------------------------------
              AdaptiveRow(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // رقم الشيك + نوعه
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'رقم الشيك: ${cheque.chequeNo}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'النوع: ${_typeLabel(cheque.chequeType)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // القيمة
                  Text(
                    '${cheque.amount.toStringAsFixed(2)} ${cheque.currency}',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // --------------------------------------------------------
              // الصف السفلي
              // --------------------------------------------------------
              AdaptiveRow(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // البنك + الفرع
                  Expanded(
                    child: Text(
                      '${cheque.bankName}${cheque.bankBranch.isEmpty ? '' : ' / ${cheque.bankBranch}'}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'تاريخ الاستحقاق: ${_df.format(cheque.dueDate)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor, width: 1),
                        ),
                        child: Text(
                          _statusLabel(cheque.status),
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
