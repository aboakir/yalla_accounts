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
    this.cacheHeight,
  });

  final String? storedPath;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;
  final int? cacheWidth;
  final int? cacheHeight;

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

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final effectiveCacheWidth =
        cacheWidth ?? (width * dpr).ceil().clamp(64, 2048).toInt();
    final effectiveCacheHeight =
        cacheHeight ?? (height * dpr).ceil().clamp(64, 2048).toInt();

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
                cacheWidth: effectiveCacheWidth,
                cacheHeight: effectiveCacheHeight,
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
