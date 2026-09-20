import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

bool get _supported =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> configureLoginWindow() async {
  if (!_supported) return;
  try {
    await windowManager.ensureInitialized();
    await windowManager.setResizable(true);
    await windowManager.unmaximize();
    await windowManager.setMinimumSize(const Size(560, 620));
    await windowManager.setSize(const Size(620, 700));
    await windowManager.center();
  } catch (_) {
    // Window sizing must never block authentication.
  }
}

Future<void> configureMainAppWindow() async {
  if (!_supported) return;
  try {
    await windowManager.ensureInitialized();
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(1000, 650));
    await windowManager.setSize(const Size(1280, 820));
    await windowManager.center();
    await windowManager.maximize();
  } catch (_) {
    // Window sizing must never block navigation.
  }
}
