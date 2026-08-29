// TODO Implement this library.
// -----------------------------------------------------------------------------
// 📁 lib/features/home/screens/dashboard/widgets/section_title.dart
// YALLA Identity Special — Section Title Widget
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 60,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.45),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}
