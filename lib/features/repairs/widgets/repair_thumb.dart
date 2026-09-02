// 📁 lib/features/repairs/widgets/repair_thumb.dart
//
// نسخة موحّدة — تعتمد دائمًا على thumbnail_path إذا موجود
// وإذا غير موجود → أول صورة من fallbackFirstPath
// تضمن وحدة الصورة في جميع الشاشات

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

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
        // 1) أول شيء: thumbnail_path من قاعدة البيانات
        String? cover = snap.data;

        // 2) إذا الـ thumbnail_path غير موجود → fallback
        if (cover == null || cover.isEmpty) {
          cover = fallbackFirstPath;
        }

        File? file;
        if (cover != null && cover.isNotEmpty) {
          final f = File(cover);
          if (f.existsSync()) {
            file = f;
          }
        }

        // 3) واجهة العرض
        final widgetContent = SizedBox(
          width: size,
          height: size,
          child: file != null
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                )
              : Container(
                  color: AppColors.lightGrey,
                  alignment: Alignment.center,
                  child: const Icon(Icons.directions_car,
                      color: AppColors.primary),
                ),
        );

        final br = borderRadius ?? BorderRadius.circular(8);
        return ClipRRect(borderRadius: br, child: widgetContent);
      },
    );
  }
}
