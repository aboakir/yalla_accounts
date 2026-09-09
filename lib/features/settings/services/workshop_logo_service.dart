import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';

/// Stores branding under the portable application root, never gallery cache.
class WorkshopLogoService {
  WorkshopLogoService({Future<Directory> Function()? rootProvider})
      : _rootProvider = rootProvider ?? YallaStorageService.rootDirectory;
  final Future<Directory> Function() _rootProvider;

  Future<File?> resolve(String? stored) async {
    if (stored == null ||
        stored.trim().isEmpty ||
        stored.startsWith('assets/')) {
      return null;
    }
    final direct = File(stored);
    if (await direct.exists()) return direct;
    final root = await _rootProvider();
    final normalized = stored.replaceAll('\\', '/');
    final marker = normalized.lastIndexOf('/YallaAccounts/');
    final relative = marker >= 0
        ? normalized.substring(marker + '/YallaAccounts/'.length)
        : normalized;
    if (p.isAbsolute(relative)) return null;
    final candidate = File(p.join(root.path, relative));
    return await candidate.exists() ? candidate : null;
  }

  Future<String?> persist(String? source) async {
    if (source == null ||
        source.trim().isEmpty ||
        source.startsWith('assets/')) {
      return source;
    }
    final file = await resolve(source);
    if (file == null) {
      throw StateError('صورة الشعار غير موجودة؛ اخترها مجددًا.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('ملف الشعار فارغ.');
    final extension = p.extension(file.path).toLowerCase();
    final relative = 'documents/branding/${sha256.convert(bytes)}$extension';
    final root = await _rootProvider();
    final target = File(p.join(root.path, relative));
    if (!await target.exists()) {
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
    }
    return relative;
  }
}
