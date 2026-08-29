import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class ProducersPortfoliosScreen extends StatelessWidget {
  const ProducersPortfoliosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text(
            'محافظ المنتجين',
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
                const Icon(Icons.folder_shared, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'محافظ المنتجين',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Placeholder.\n'
                  'هنا سنضيف لاحقًا: قائمة المنتجين، إجمالي المبيعات، عمولة كل منتج، وحالات التحصيل.',
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
