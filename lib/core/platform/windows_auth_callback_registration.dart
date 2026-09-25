import 'dart:io';

import 'package:flutter/foundation.dart';

/// Registers the private URI scheme used by Supabase email callbacks.
///
/// HKCU is intentional: no administrator rights are required and the protocol
/// follows the currently installed/running Yallah Accounts executable.
Future<bool> ensureWindowsAuthCallbackRegistration() async {
  if (kIsWeb || !Platform.isWindows) return false;

  const root = r'HKCU\Software\Classes\yallaaccounts';
  final executable = Platform.resolvedExecutable;
  final commands = <List<String>>[
    ['add', root, '/ve', '/d', 'URL:Yallah Accounts Protocol', '/f'],
    ['add', root, '/v', 'URL Protocol', '/d', '', '/f'],
    [
      'add',
      '$root\\DefaultIcon',
      '/ve',
      '/d',
      '"$executable",0',
      '/f',
    ],
    [
      'add',
      '$root\\shell\\open\\command',
      '/ve',
      '/d',
      '"$executable" "%1"',
      '/f',
    ],
  ];

  for (final args in commands) {
    final result = await Process.run('reg.exe', args);
    if (result.exitCode != 0) return false;
  }
  return true;
}
