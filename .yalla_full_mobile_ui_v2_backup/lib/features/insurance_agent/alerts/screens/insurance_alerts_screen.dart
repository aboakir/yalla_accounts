import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class InsuranceAlertsScreen extends StatelessWidget {
  const InsuranceAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text(
            'التنبيهات والمتابعة',
            style: TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications_active, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'التنبيهات والمتابعة',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Placeholder.\n'
                  'لاحقًا: تنبيه قبل انتهاء أي بوليصة بـ 12 يوم + حالات المتابعة لدى التأمين + فلترة حسب الشركة/المنتج.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
