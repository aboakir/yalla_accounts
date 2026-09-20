import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';

void main() {
  test('FINAL SWEEP masks technical exception content', () {
    expect(
      UserFacingError.message(
        Exception('DatabaseException: no such column: totalFileValue'),
      ),
      'تعذر تنفيذ العملية. حاول مرة أخرى.',
    );
    expect(
      UserFacingError.message(
        Exception(r'PathNotFoundException: C:\Users\luay\Downloads\x.pdf'),
      ),
      'تعذر تنفيذ العملية. حاول مرة أخرى.',
    );
    expect(
      UserFacingError.message(StateError('المبلغ غير صالح')),
      'المبلغ غير صالح',
    );
  });

  test('FINAL SWEEP has no legacy totalFileValue SQL column', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final legacySql = RegExp(
        r'SELECT[^;]*totalFileValue',
        caseSensitive: false,
        dotAll: true,
      ).hasMatch(source);
      final legacyMap = source.contains("m['totalFileValue']") ||
          source.contains('m["totalFileValue"]');
      final legacyJoin = source.contains('COALESCE(r.totalFileValue') ||
          source.contains('receivedDate, totalFileValue FROM repairs');
      if (legacySql || legacyMap || legacyJoin) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: 'Legacy DB column refs: $offenders');
  });

  test('FINAL SWEEP hides raw exceptions and filesystem paths from UI', () {
    final offenders = <String>[];
    final rawException = RegExp(
      r'(Text\((?:e|error)\.toString\(\)\)|'
      r'SnackBar\([^\n]*\$(?:e|error)\b|'
      r'Text\([^\n]*(?:DatabaseException|PathNotFoundException|'
      r'FileSystemException|no such column|no such table))',
      caseSensitive: false,
    );
    final rawPath = RegExp(
      r'(SnackBar[^\n]*(?:file|dir)\.path|'
      r'content:\s*Text\([^\n]*(?:file|dir)\.path|'
      r'Downloads:\\n\$path)',
      caseSensitive: false,
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (rawException.hasMatch(source) || rawPath.hasMatch(source)) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: 'Unsafe user-facing errors: $offenders');
  });

  test('FINAL SWEEP all Downloads calls use Yallah platform wrapper', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.endsWith('/core/platform/yalla_path_provider.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (!source.contains('getDownloadsDirectory()')) continue;
      if (!source.contains('core/platform/yalla_path_provider.dart')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: 'Unsafe Downloads imports: $offenders');
  });
}
