import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test sources never reference the live Yallah Accounts database file',
      () {
    const drive = 'D:';
    const spacedRoot = 'Yallah Accounts';
    const legacyRoot = 'YallaAccounts';
    final forbidden = <String>[
      '$drive\\$spacedRoot\\yallah_accounts.db',
      '$drive\\$spacedRoot\\yalla_accounts.db',
      '$drive\\$legacyRoot\\yallah_accounts.db',
      '$drive\\$legacyRoot\\yalla_accounts.db',
    ];

    final offenders = <String>[];
    final self = File(Platform.script.toFilePath()).absolute.path.toLowerCase();

    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.absolute.path.toLowerCase() == self) continue;

      final source = entity.readAsStringSync().toLowerCase();
      for (final path in forbidden) {
        final backslash = path.toLowerCase();
        final slash = backslash.replaceAll(r'\', '/');
        if (source.contains(backslash) || source.contains(slash)) {
          offenders.add('${entity.path}: $path');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Tests must use temporary databases or explicit backup fixtures only.',
    );
  });
}
