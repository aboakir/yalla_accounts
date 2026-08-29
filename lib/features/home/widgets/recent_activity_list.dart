import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RecentActivityList extends StatelessWidget {
  const RecentActivityList({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final recentItems = [
      {
        'title': 'إصلاح مركبة هونداي - محمد أحمد',
        'date': '2025-05-20',
        'type': 'repair'
      },
      {
        'title': 'فاتورة جديدة - عميل رقم 232',
        'date': '2025-05-19',
        'type': 'invoice'
      },
      {
        'title': 'إضافة بوليصة تأمين - شركة الأهلية',
        'date': '2025-05-18',
        'type': 'insurance'
      },
      {
        'title': 'إصلاح مركبة تويوتا - خالد سمير',
        'date': '2025-05-17',
        'type': 'repair'
      },
    ];

    IconData getIcon(String type) {
      switch (type) {
        case 'repair':
          return Icons.car_repair;
        case 'invoice':
          return Icons.receipt_long_outlined;
        case 'insurance':
          return Icons.shield_outlined;
        default:
          return Icons.notifications;
      }
    }

    Color getColor(String type) {
      switch (type) {
        case 'repair':
          return Colors.teal;
        case 'invoice':
          return Colors.deepOrange;
        case 'insurance':
          return Colors.indigo;
        default:
          return AppColors.primary;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'الأنشطة الأخيرة',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: AppColors.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentItems.length,
            separatorBuilder: (_, __) => Divider(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final item = recentItems[index];
              final isNew = index == 0;
              final formattedDate = DateFormat('yyyy/MM/dd').format(
                DateTime.tryParse(item['date']!) ?? DateTime.now(),
              );

              return Dismissible(
                key: Key(item['title']!),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.redAccent,
                  child: const Icon(Icons.delete_forever, color: Colors.white),
                ),
                onDismissed: (_) {
                  // مستقبلًا: حذف من قاعدة البيانات + إشعار
                },
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  onTap: () {
                    // مستقبلًا: فتح تفاصيل النشاط
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: getColor(item['type']!).withOpacity(0.15),
                    child: Icon(
                      getIcon(item['type']!),
                      color: getColor(item['type']!),
                      size: 22,
                    ),
                  ),
                  title: AdaptiveRow(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (isNew)
                        const Tooltip(
                          message: 'جديد 🔥',
                          child: Icon(Icons.local_fire_department,
                              color: Colors.redAccent, size: 16),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['title']!,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    formattedDate,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
