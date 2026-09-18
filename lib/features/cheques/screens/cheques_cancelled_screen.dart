// 📁 lib/features/cheques/screens/cheques_cancelled_screen.dart
//
// ChequesCancelledScreen — الشيكات الملغاة (نسخة نهائية)
// --------------------------------------------------------
// - لا RTL نهائيًا
// - محاذاة عربية باستخدام TextAlign.right
// - Sidebar ثابت على الديسكتوب فقط
// - بدون بيانات وهمية أو مخالفات

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ChequesCancelledScreen extends ConsumerWidget {
  const ChequesCancelledScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      appBar: const YallaAppBar(
        workshopName: 'Yallah Accounts',
        showThemeToggle: false,
        showSearch: false,
      ),

      // السايدبار فقط على الديسكتوب
      drawer: isDesktop
          ? null
          : const YallaSidebar(currentRoute: '/cheques/cancelled'),

      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(currentRoute: '/cheques/cancelled'),
          Expanded(
            child: Center(
              child: Text(
                'عرض الشيكات الملغاة',
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
