import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as im;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class YallaOptimizedImage {
  const YallaOptimizedImage({
    required this.bytes,
    required this.extension,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String extension;
  final int width;
  final int height;
}

Map<String, Object?> _optimizeImagePayload(Map<String, Object?> input) {
  final bytes = input['bytes'] as Uint8List;
  final extension = (input['extension'] as String? ?? 'jpg').toLowerCase();
  final maxDimension = input['maxDimension'] as int? ?? 1920;
  final quality = input['quality'] as int? ?? 82;

  try {
    final decoded = im.decodeImage(bytes);
    if (decoded == null) {
      return <String, Object?>{
        'bytes': bytes,
        'extension': extension,
        'width': 0,
        'height': 0,
      };
    }

    final width = decoded.width;
    final height = decoded.height;
    final maxSide = width > height ? width : height;
    im.Image working = decoded;

    if (maxSide > maxDimension) {
      working = width >= height
          ? im.copyResize(decoded, width: maxDimension)
          : im.copyResize(decoded, height: maxDimension);
    }

    final encoded = Uint8List.fromList(im.encodeJpg(working, quality: quality));
    final originalIsJpeg = extension == 'jpg' || extension == 'jpeg';
    final keepOriginal = maxSide <= maxDimension &&
        originalIsJpeg &&
        bytes.lengthInBytes <= encoded.lengthInBytes;

    return <String, Object?>{
      'bytes': keepOriginal ? bytes : encoded,
      'extension': keepOriginal ? 'jpg' : 'jpg',
      'width': working.width,
      'height': working.height,
    };
  } catch (_) {
    return <String, Object?>{
      'bytes': bytes,
      'extension': extension,
      'width': 0,
      'height': 0,
    };
  }
}

/// Canonical cross-platform Yallah Accounts file storage.
///
/// Stored DB values should be relative paths such as:
/// repairs/2026/09/images/tucson_9007654_client_...jpg
///
/// Absolute paths from older builds are still resolved and rebased so iOS
/// container UUID changes do not orphan existing media references.
class YallaStorageService {
  YallaStorageService._();

  static Directory? _rootCache;
  static Directory? _testRoot;

  @visibleForTesting
  static void useRootDirectoryForTesting(Directory? directory) {
    _testRoot = directory;
    _rootCache = null;
  }

  static Future<Directory> rootDirectory() async {
    final cached = _rootCache;
    if (cached != null && await cached.exists()) return cached;

    Directory root;
    if (_testRoot != null) {
      root = _testRoot!;
    } else if (Platform.isWindows) {
      final d = Directory(r'D:\');
      root = Directory(
          await d.exists() ? r'D:\YallaAccounts' : r'C:\YallaAccounts');
    } else if (Platform.isIOS || Platform.isAndroid) {
      final support = await getApplicationSupportDirectory();
      root = Directory(p.join(support.path, 'YallaAccounts'));
    } else {
      final docs = await getApplicationDocumentsDirectory();
      root = Directory(p.join(docs.path, 'YallaAccounts'));
    }

    if (!await root.exists()) await root.create(recursive: true);
    _rootCache = root;
    await _ensureBaseFolders(root);
    return root;
  }

  static Future<void> _ensureBaseFolders(Directory root) async {
    for (final rel in const <String>[
      'database',
      'repairs',
      'insurance',
      'documents',
      'exports',
      'backups',
    ]) {
      final dir = Directory(p.join(root.path, rel));
      if (!await dir.exists()) await dir.create(recursive: true);
    }
  }

  static String _safe(String input, {String fallback = 'unknown'}) {
    final s = input.trim().isEmpty ? fallback : input.trim();
    final cleaned = s
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static String _module(String input) {
    final v = input.trim().toLowerCase();
    if (v == 'insurance') return 'insurance';
    return 'repairs';
  }

  static String _toPosix(String value) => value.replaceAll('\\', '/');

  static String _relativeJoin(List<String> parts) =>
      p.posix.joinAll(parts.map(_toPosix));

  /// P17 canonical image optimization gate. All persisted workshop photos
  /// pass through this method so a future screen cannot accidentally store a
  /// 12/48 MP original without resizing. CPU-heavy decode/encode runs off the
  /// UI isolate via [compute].
  static Future<YallaOptimizedImage> optimizeImageBytes({
    required Uint8List bytes,
    required String extension,
    int maxDimension = 1920,
    int quality = 82,
  }) async {
    if (bytes.isEmpty) {
      return YallaOptimizedImage(
        bytes: bytes,
        extension: extension,
        width: 0,
        height: 0,
      );
    }

    final result = await compute<Map<String, Object?>, Map<String, Object?>>(
      _optimizeImagePayload,
      <String, Object?>{
        'bytes': bytes,
        'extension': extension,
        'maxDimension': maxDimension,
        'quality': quality,
      },
    );

    return YallaOptimizedImage(
      bytes: result['bytes'] as Uint8List,
      extension: result['extension'] as String? ?? 'jpg',
      width: result['width'] as int? ?? 0,
      height: result['height'] as int? ?? 0,
    );
  }

  static Future<String> saveImage({
    required XFile image,
    required String module,
    required String vehicleType,
    required String vehicleNumber,
    required String beneficiaryName,
    required DateTime date,
  }) async {
    final bytes = await image.readAsBytes();
    final sourceExt =
        p.extension(image.path).replaceFirst('.', '').toLowerCase();
    final ext =
        RegExp(r'^[a-z0-9]{1,5}$').hasMatch(sourceExt) ? sourceExt : 'jpg';
    return saveImageBytes(
      bytes: bytes,
      extension: ext,
      module: module,
      vehicleType: vehicleType,
      vehicleNumber: vehicleNumber,
      beneficiaryName: beneficiaryName,
      date: date,
    );
  }

  static Future<String> saveImageFromPath({
    required String sourcePath,
    required String module,
    required String vehicleType,
    required String vehicleNumber,
    required String beneficiaryName,
    required DateTime date,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Source image not found', sourcePath);
    }
    final extRaw = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final ext = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extRaw) ? extRaw : 'jpg';
    return saveImageBytes(
      bytes: await source.readAsBytes(),
      extension: ext,
      module: module,
      vehicleType: vehicleType,
      vehicleNumber: vehicleNumber,
      beneficiaryName: beneficiaryName,
      date: date,
    );
  }

  static Future<String> saveImageBytes({
    required Uint8List bytes,
    required String extension,
    required String module,
    required String vehicleType,
    required String vehicleNumber,
    required String beneficiaryName,
    required DateTime date,
  }) async {
    final optimized = await optimizeImageBytes(
      bytes: bytes,
      extension: extension,
    );
    final root = await rootDirectory();
    final safeModule = _module(module);
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final relDir = _relativeJoin([safeModule, year, month, 'images']);
    final dir = Directory(p.joinAll(<String>[root.path, ...relDir.split('/')]));
    if (!await dir.exists()) await dir.create(recursive: true);

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final fileName = '${[
      _safe(vehicleType, fallback: 'vehicle'),
      _safe(vehicleNumber, fallback: 'no_number'),
      _safe(beneficiaryName, fallback: 'client'),
      stamp.toString(),
    ].join('_')}.${_safe(optimized.extension, fallback: 'jpg')}';

    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(optimized.bytes, flush: true);
    return _relativeJoin([relDir, fileName]);
  }

  static Future<String> saveSignature({
    required Uint8List bytes,
    required DateTime date,
  }) async {
    final root = await rootDirectory();
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final relDir = _relativeJoin(['documents', 'signatures', year, month]);
    final dir = Directory(p.joinAll(<String>[root.path, ...relDir.split('/')]));
    if (!await dir.exists()) await dir.create(recursive: true);
    final fileName = 'signature_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(p.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);
    return _relativeJoin([relDir, fileName]);
  }

  static Future<File> savePdf({
    required Uint8List bytes,
    required String module,
    required String fileName,
    DateTime? date,
  }) async {
    final root = await rootDirectory();
    final safeName = _safePdfFileName(fileName);
    final when = date ?? DateTime.now();

    final String relDir;
    if (module == 'repairs' || module == 'insurance') {
      relDir = _relativeJoin([
        module,
        when.year.toString(),
        when.month.toString().padLeft(2, '0'),
        'pdf',
      ]);
    } else {
      relDir = _relativeJoin(['exports']);
    }

    final dir = Directory(p.joinAll(<String>[root.path, ...relDir.split('/')]));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, safeName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _safePdfFileName(String name) {
    final base = p.basename(name.trim().isEmpty ? 'document.pdf' : name.trim());
    final stem = _safe(p.basenameWithoutExtension(base), fallback: 'document');
    return '$stem.pdf';
  }

  /// Resolve a DB-stored relative or legacy absolute path to the current
  /// platform/container absolute path. Returns null if no physical file exists.
  static Future<String?> resolveExistingPath(String? storedPath) async {
    final raw = storedPath?.trim();
    if (raw == null || raw.isEmpty) return null;

    final direct = File(raw);
    if (await direct.exists()) return direct.path;

    final root = await rootDirectory();
    final normalized = _toPosix(raw);

    // New canonical relative paths.
    if (!p.isAbsolute(raw) && !RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      final candidate =
          File(p.joinAll(<String>[root.path, ...normalized.split('/')]));
      if (await candidate.exists()) return candidate.path;
    }

    // Older absolute YallaAccounts paths: preserve only the relative suffix.
    final marker = '/YallaAccounts/';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex >= 0) {
      final suffix = normalized.substring(markerIndex + marker.length);
      final supportCandidate =
          File(p.joinAll(<String>[root.path, ...suffix.split('/')]));
      if (await supportCandidate.exists()) return supportCandidate.path;

      // Old iPhone builds used Documents/YallaAccounts while the canonical
      // mobile root is now Application Support/YallaAccounts.
      if (Platform.isIOS || Platform.isAndroid) {
        final docs = await getApplicationDocumentsDirectory();
        final docsCandidate = File(p.joinAll(
            <String>[docs.path, 'YallaAccounts', ...suffix.split('/')]));
        if (await docsCandidate.exists()) return docsCandidate.path;
      }
    }

    // Legacy P07 intake/signature folders were outside YallaAccounts.
    if (Platform.isIOS || Platform.isAndroid) {
      final support = await getApplicationSupportDirectory();
      for (final legacy in const [
        'repair_intake_photos',
        'repair_signatures'
      ]) {
        final token = '/$legacy/';
        final i = normalized.indexOf(token);
        if (i >= 0) {
          final suffix = normalized.substring(i + token.length);
          final candidate = File(
              p.joinAll(<String>[support.path, legacy, ...suffix.split('/')]));
          if (await candidate.exists()) return candidate.path;
        }
      }
    }

    return null;
  }

  static Future<File?> resolveFile(String? storedPath) async {
    final absolute = await resolveExistingPath(storedPath);
    return absolute == null ? null : File(absolute);
  }

  static Future<void> deleteStoredFile(String? storedPath) async {
    final file = await resolveFile(storedPath);
    if (file != null && await file.exists()) await file.delete();
  }

  /// Convert an absolute path inside the current/legacy Yalla root to a
  /// portable relative DB value. Unknown external paths are returned as-is.
  static Future<String> toStoredPath(String path) async {
    final raw = path.trim();
    if (raw.isEmpty) return raw;
    final root = await rootDirectory();
    final normalized = _toPosix(raw);
    final rootNormalized = _toPosix(root.path).replaceAll(RegExp(r'/$'), '');

    if (normalized.startsWith('$rootNormalized/')) {
      return normalized.substring(rootNormalized.length + 1);
    }

    final marker = '/YallaAccounts/';
    final i = normalized.indexOf(marker);
    if (i >= 0) return normalized.substring(i + marker.length);

    return raw;
  }
}
