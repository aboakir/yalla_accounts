import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all active PDF print entry points use the print-safe service', () {
    final violations = <String>[];
    final helper = RegExp(r'yalla_pdf_print_service\.dart$');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          helper.hasMatch(entity.path)) {
        continue;
      }

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trimLeft();
        if (code.startsWith('//')) continue;
        if (code.contains('Printing.layoutPdf(')) {
          violations.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Direct Printing.layoutPdf bypasses Arabic-safe raster printing.',
    );
  });

  test('print-safe service rasterizes before opening the printer dialog', () {
    final source = File(
      'lib/core/pdf/yalla_pdf_print_service.dart',
    ).readAsStringSync();

    expect(source, contains('Printing.raster('));
    expect(source, contains('rasterDpi = 216'));
    expect(source, contains('dynamicLayout: false'));
  });
}
