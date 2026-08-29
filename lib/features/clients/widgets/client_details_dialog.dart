import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// يعرض تفاصيل عميل داخل Dialog.
/// يعيد من Navigator:
/// - 'edit' عند الضغط على تعديل
/// - 'delete' عند الضغط على حذف
/// - null عند الإغلاق العادي
class ClientDetailsDialog extends StatelessWidget {
  final Client client;

  const ClientDetailsDialog({super.key, required this.client});

  // ─── تحويل النوع إلى تسمية عربية للعرض ────────────────────────────────
  String _toUiType(String t) {
    final s = t.trim().toLowerCase();
    if (s == 'insurance' || s == 'شركة تأمين' || s == 'تأمين') {
      return 'شركة تأمين';
    }
    if (s == 'individual' || s == 'أفراد' || s == 'فرد' || s == 'عميل') {
      return 'أفراد';
    }
    return 'أفراد';
  }

  @override
  Widget build(BuildContext context) {
    final typeAr = _toUiType(client.type);
    final isInsurance = typeAr == 'شركة تأمين';

    Widget infoRow(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: AdaptiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget notesBlock(String notes) {
      if (notes.trim().isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Text(
            'الملاحظات',
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Text(
              notes,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ],
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AdaptiveAlertDialog(
        title: AdaptiveRow(
          children: [
            Icon(isInsurance ? Icons.business : Icons.person,
                color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                client.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // شارة النوع
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AdaptiveRow(
                  children: [
                    const Icon(Icons.badge, color: AppColors.primary, size: 18),
                    const SizedBox(width: 6),
                    Text('النوع: $typeAr',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // البيانات الأساسية
              infoRow(Icons.phone, 'الهاتف', client.phone),
              infoRow(Icons.email, 'البريد', client.email),
              infoRow(Icons.location_on, 'العنوان', client.address),

              // الملاحظات (إن وُجدت)
              notesBlock(client.notes),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('تعديل'),
          ),
        ],
      ),
    );
  }
}
