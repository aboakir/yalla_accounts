import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('Yalla production identity uses the canonical green everywhere central',
      () {
    final colors = read('lib/core/constants/colors.dart');
    final tokens = read('lib/core/design/yalla_design_tokens.dart');
    final main = read('lib/main.dart');

    expect(colors, contains('Color(0xFF67BC1F)'));
    expect(tokens, contains('static const Color brand = AppColors.primary;'));
    expect(tokens, isNot(contains('59C414')));
    expect(main, contains('colorScheme: const ColorScheme.light('));
    expect(main, contains('primary: AppColors.primary'));
    expect(main, contains('primaryContainer: AppColors.lightGreen'));
    expect(main, isNot(contains('ColorScheme.fromSeed')));
    expect(main, isNot(contains('22C55E')));
  });

  test('production UI exposes one light theme and no sidebar dark-mode toggle',
      () {
    final root = read('lib/main.dart');
    final appTheme = read('lib/theme/app_theme.dart');
    final footer = read('lib/core/widgets/sidebar/sidebar_footer.dart');

    expect(root, contains('brightness: Brightness.light'));
    expect(appTheme, isNot(contains('static ThemeData darkTheme')));
    expect(footer, isNot(contains('ThemeMode.dark')));
    expect(footer, isNot(contains('الوضع الليلي')));
  });

  test('Arabic production root uses the registered Cairo font family', () {
    final pubspec = read('pubspec.yaml');
    final main = read('lib/main.dart');

    expect(pubspec, contains('family: Cairo'));
    expect(pubspec, contains('assets/fonts/Cairo-Regular.ttf'));
    expect(pubspec, contains('assets/fonts/Cairo-Bold.ttf'));
    expect(main, contains("fontFamily: 'Cairo'"));
  });

  test(
      'product source has no raw AlertDialog or DataTable outside adaptive layer',
      () {
    final rawDialog =
        RegExp(r'(^|[^A-Za-z0-9_.])AlertDialog\s*\(', multiLine: true);
    final rawTable =
        RegExp(r'(^|[^A-Za-z0-9_.])DataTable\s*\(', multiLine: true);
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.endsWith('lib/shared/widgets/adaptive_layout.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (rawDialog.hasMatch(source) || rawTable.hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
