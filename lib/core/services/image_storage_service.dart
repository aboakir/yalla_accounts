import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';

class ImageStorageService {
  static Future<String> saveImage({
    required XFile image,
    String module = 'repairs',
    required String vehicleType,
    required String vehicleNumber,
    required String beneficiaryName,
    required DateTime receivedDate,
  }) {
    return YallaStorageService.saveImage(
      image: image,
      module: module,
      vehicleType: vehicleType,
      vehicleNumber: vehicleNumber,
      beneficiaryName: beneficiaryName,
      date: receivedDate,
    );
  }

  static Future<void> deleteImage(String path) =>
      YallaStorageService.deleteStoredFile(path);

  static Future<XFile> compressImage(XFile original) async {
    try {
      final extension = p.extension(original.path).replaceFirst('.', '');
      final optimized = await YallaStorageService.optimizeImageBytes(
        bytes: await original.readAsBytes(),
        extension: extension.isEmpty ? 'jpg' : extension,
      );
      return XFile.fromData(
        optimized.bytes,
        name: 'yalla_optimized.${optimized.extension}',
        mimeType: 'image/jpeg',
      );
    } catch (_) {
      return original;
    }
  }

  static Future<String?> resolveStoredPath(String? storedPath) =>
      YallaStorageService.resolveExistingPath(storedPath);

  static Future<File?> resolveStoredFile(String? storedPath) =>
      YallaStorageService.resolveFile(storedPath);

  static Future<String> generateThumbnail(String originalPath) async {
    // V10J uses the selected original image as the profile source. Keeping a
    // duplicate thumbnail file is no longer necessary and avoids stale paths.
    return YallaStorageService.toStoredPath(originalPath);
  }
}
