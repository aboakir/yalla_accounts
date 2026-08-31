import 'dart:io';
// 📁 lib/features/repairs/widgets/repair_thumb.dart
//
// نسخة موحّدة — تعتمد دائمًا على thumbnail_path إذا موجود
// وإذا غير موجود → أول صورة من fallbackFirstPath
// تضمن وحدة الصورة في جميع الشاشات

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/shared/utils/local_media_resolver.dart';

class RepairThumb extends StatelessWidget {
  final String repairId;
  final String? fallbackFirstPath;
  final List<String> fallbackPaths;
  final double size;
  final BorderRadius? borderRadius;

  const RepairThumb({
    super.key,
    required this.repairId,
    this.fallbackFirstPath,
    this.fallbackPaths = const <String>[],
    this.size = 48,
    this.borderRadius,
  });

  Future<File?> _resolveCover() async {
    final dbThumb = await DBService.getRepairThumbnailPath(repairId);
    return LocalMediaResolver.firstExisting([
      dbThumb,
      fallbackFirstPath,
      ...fallbackPaths,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _resolveCover(),
      builder: (context, snap) {
        final file = snap.data;
        final widgetContent = SizedBox(
          width: size,
          height: size,
          child: file != null
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.lightGrey,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.directions_car,
                      color: AppColors.primary,
                    ),
                  ),
                )
              : Container(
                  color: AppColors.lightGrey,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.directions_car,
                    color: AppColors.primary,
                  ),
                ),
        );

        final br = borderRadius ?? BorderRadius.circular(8);
        return ClipRRect(borderRadius: br, child: widgetContent);
      },
    );
  }
}
