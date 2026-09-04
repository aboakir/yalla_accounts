import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';

class YallaStoredImage extends StatelessWidget {
  const YallaStoredImage({
    super.key,
    required this.storedPath,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
    this.cacheWidth,
  });

  final String? storedPath;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final fallbackWidget = fallback ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.directions_car_outlined),
        );

    return FutureBuilder<String?>(
      future: YallaStorageService.resolveExistingPath(storedPath),
      builder: (context, snapshot) {
        final path = snapshot.data;
        final child = path == null
            ? fallbackWidget
            : Image.file(
                File(path),
                width: width,
                height: height,
                fit: fit,
                cacheWidth: cacheWidth,
                errorBuilder: (_, __, ___) => fallbackWidget,
              );
        final radius = borderRadius;
        return radius == null
            ? SizedBox(width: width, height: height, child: child)
            : ClipRRect(
                borderRadius: radius,
                child: SizedBox(width: width, height: height, child: child),
              );
      },
    );
  }
}
