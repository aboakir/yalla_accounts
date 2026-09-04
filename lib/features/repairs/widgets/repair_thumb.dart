// 📁 lib/features/repairs/widgets/repair_thumb.dart
//
// نسخة موحّدة — تعتمد دائمًا على thumbnail_path إذا موجود
// وإذا غير موجود → أول صورة من fallbackFirstPath
// تضمن وحدة الصورة في جميع الشاشات

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';

class RepairThumb extends StatelessWidget {
  final String repairId;
  final String? fallbackFirstPath;
  final double size;
  final BorderRadius? borderRadius;

  const RepairThumb({
    super.key,
    required this.repairId,
    this.fallbackFirstPath,
    this.size = 48,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: DBService.getRepairThumbnailPath(repairId),
      builder: (context, snap) {
        String? cover = snap.data;
        if (cover == null || cover.isEmpty) cover = fallbackFirstPath;
        final br = borderRadius ?? BorderRadius.circular(8);
        return YallaStoredImage(
          storedPath: cover,
          width: size,
          height: size,
          borderRadius: br,
          fallback: Container(
            width: size,
            height: size,
            color: AppColors.lightGrey,
            alignment: Alignment.center,
            child: const Icon(
              Icons.directions_car,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }
}
