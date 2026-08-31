import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves media paths that were persisted by an older iOS app container.
///
/// iOS may move the application sandbox after an update/re-sign/install-over.
/// Absolute paths stored in SQLite can therefore become stale even though the
/// image still exists in the current Documents/Application Support container.
class LocalMediaResolver {
  const LocalMediaResolver._();

  static Future<File?> firstExisting(Iterable<String?> storedPaths) async {
    final rawPaths = storedPaths
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    if (rawPaths.isEmpty) return null;

    // Fast path: the stored absolute path is still valid.
    for (final raw in rawPaths) {
      final direct = File(raw);
      if (await direct.exists()) return direct;
    }

    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final temp = await getTemporaryDirectory();

    final roots = <Directory>[docs, support, temp];
    final markers = <String, Directory>{
      '/Documents/': docs,
      '/Library/Application Support/': support,
      '/tmp/': temp,
    };

    for (final raw in rawPaths) {
      final normalized = raw.replaceAll('\\', '/');

      // Re-anchor the path suffix after a known iOS sandbox marker.
      for (final entry in markers.entries) {
        final index = normalized.indexOf(entry.key);
        if (index < 0) continue;
        final relative = normalized.substring(index + entry.key.length);
        if (relative.isEmpty) continue;
        final candidate = File(p.join(entry.value.path, relative));
        if (await candidate.exists()) return candidate;
      }

      // Last-resort common app media locations using only the basename.
      final name = p.basename(normalized);
      if (name.isEmpty) continue;
      for (final root in roots) {
        for (final relative in <String>[
          name,
          p.join('images', name),
          p.join('repair_images', name),
          p.join('repairs', name),
          p.join('media', name),
        ]) {
          final candidate = File(p.join(root.path, relative));
          if (await candidate.exists()) return candidate;
        }
      }
    }

    return null;
  }
}
