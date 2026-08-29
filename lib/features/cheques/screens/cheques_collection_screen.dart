// 📁 lib/features/cheques/screens/cheques_collection_screen.dart
//
// ChequesCollectionScreen — الشيكات قيد التحصيل (نسخة نهائية)
// -----------------------------------------------------------
// - لا RTL نهائيًا
// - محاذاة عربية عبر TextAlign.right
// - Sidebar ثابت على الديسكتوب فقط
// - بدون بيانات وهمية

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ChequesCollectionScreen extends ConsumerWidget {
  const ChequesCollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      appBar: const YallaAppBar(
        workshopName: 'Yalla Accounts',
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: isDesktop
          ? null
          : const YallaSidebar(currentRoute: '/cheques/collection'),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const YallaSidebar(currentRoute: '/cheques/collection'),
          Expanded(
            child: Center(
              child: Text(
                'عرض الشيكات قيد التحصيل',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
