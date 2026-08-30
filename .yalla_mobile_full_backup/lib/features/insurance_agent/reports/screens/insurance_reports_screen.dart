import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class InsuranceReportsScreen extends StatelessWidget {
  const InsuranceReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text(
            'التقارير والطباعة',
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
                const Icon(Icons.print, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'التقارير والطباعة',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Placeholder.\n'
                  'لاحقًا: تقرير مبيعات البوالص، تقرير الأرباح، تقرير بوالص منتهية/قريبة الانتهاء، وطباعة قائمة/كشف بوليصة.',
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
