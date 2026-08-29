// 📁 lib/core/widgets/under_construction_screen.dart

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// شاشة بسيطة تُظهر رسالة “الصفحة قيد التطوير”
/// وعنوانًا مرسَلًا عبر المتغيّر [title].
/// إذا كانت الشاشة واسعة (عرض >= 900px) فستبقى الـ Sidebar ظاهرة على اليمين،
/// وإلّا يظهر زر “العودة” في الـ AppBar.
class UnderConstructionScreen extends StatelessWidget {
  final String title;

  const UnderConstructionScreen({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    // نعتبر أن أي عرض ≥ 900 نقطة هو Tablet/ Desktop
    final isWide = MediaQuery.of(context).size.width >= 900;
    const sidebar = YallaSidebar(currentRoute: null);

    return Scaffold(
      body: AdaptiveRow(
        children: [
          // إذا الشاشة مُتسعة، نظهر الـ Sidebar دائمًا على اليمين
          if (isWide) const SizedBox(width: 250, child: sidebar),

          // المحتوى الرئيسي
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: Text(title),
                leading: isWide
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.arrow_back_ios),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
              ),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.construction_outlined,
                      size: 80,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'هذه الصفحة قيد التطوير',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '(الجزء: $title)',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
