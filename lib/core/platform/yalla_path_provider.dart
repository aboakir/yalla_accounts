import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as pp;

export 'package:path_provider/path_provider.dart' hide getDownloadsDirectory;

/// Platform-safe replacement for direct Downloads access.
///
/// Desktop keeps the familiar Downloads behavior. Mobile platforms use an
/// app-owned Exports directory because iOS does not expose a Windows-style
/// Downloads folder and direct assumptions there cause PathNotFoundException.
Future<Directory?> getDownloadsDirectory() async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      final downloads = await pp.getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    } catch (_) {
      // Fall through to the app-owned directory.
    }
  }

  try {
    final docs = await pp.getApplicationDocumentsDirectory();
    final exports = Directory(p.join(docs.path, 'Yallah Accounts', 'Exports'));
    if (!await exports.exists()) {
      await exports.create(recursive: true);
    }
    return exports;
  } catch (_) {
    try {
      final temp = await pp.getTemporaryDirectory();
      final exports =
          Directory(p.join(temp.path, 'Yallah Accounts', 'Exports'));
      if (!await exports.exists()) {
        await exports.create(recursive: true);
      }
      return exports;
    } catch (_) {
      return null;
    }
  }
}
