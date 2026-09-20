import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Yallah product source uses only canonical green identity colors', () {
    final offenders = <String>[];
    final rawGreen = RegExp(
      r'(?<![A-Za-z0-9_])Colors\.(green|lightGreen|greenAccent)',
    );
    final pdfGreen = RegExp(r'PdfColors\.green\w*');
    final hex = RegExp(r'0xFF([0-9A-Fa-f]{6})');
    const allowedGreenHex = <String>{'67BC1F', 'DFF5D2', 'EAF7E4'};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      if (rawGreen.hasMatch(source) || pdfGreen.hasMatch(source)) {
        offenders.add(entity.path);
        continue;
      }

      for (final match in hex.allMatches(source)) {
        final value = match.group(1)!.toUpperCase();
        final r = int.parse(value.substring(0, 2), radix: 16);
        final g = int.parse(value.substring(2, 4), radix: 16);
        final b = int.parse(value.substring(4, 6), radix: 16);
        final greenish = g >= r + 20 && g >= b + 20;
        if (greenish && !allowedGreenHex.contains(value)) {
          offenders.add('${entity.path}:#$value');
          break;
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Dark/non-canonical green escaped the Yallah design tokens.',
    );
  });

  test('Yallah theme does not auto-generate dark green shades', () {
    final main = File('lib/main.dart').readAsStringSync();
    final appTheme = File('lib/theme/app_theme.dart').readAsStringSync();
    final tokens =
        File('lib/core/design/yalla_design_tokens.dart').readAsStringSync();

    expect(main, contains('colorScheme: const ColorScheme.light('));
    expect(appTheme, contains('colorScheme: const ColorScheme.light('));
    expect(main, isNot(contains('ColorScheme.fromSeed')));
    expect(appTheme, isNot(contains('ColorScheme.fromSeed')));
    expect(tokens, contains('static const Color brandDark = brand;'));
  });

  test('brand placements do not force a white logo background', () {
    final sidebar =
        File('lib/core/widgets/sidebar/sidebar_header.dart').readAsStringSync();
    final appBar =
        File('lib/core/widgets/yalla_appbar.dart').readAsStringSync();
    final splash = File('lib/features/splash/screens/splash_screen.dart')
        .readAsStringSync();
    final login =
        File('lib/features/auth/screens/login_screen.dart').readAsStringSync();
    final unlock = File(
      'lib/features/auth/screens/device_unlock_screen.dart',
    ).readAsStringSync();

    expect(sidebar, contains('color: AppColors.lightGreen'));
    expect(appBar, contains('backgroundColor: AppColors.lightGreen'));
    expect(splash, contains('backgroundColor: AppColors.scaffoldBg'));
    expect(login, contains('color: YallaColors.successSurface'));
    expect(unlock, contains('color: AppColors.lightGreen'));
  });

  test('system icon PNGs have no white corner background', () {
    final paths = <String>[
      'assets/branding/yallah_app_icon.png',
      ...Directory('android/app/src/main/res')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.png') &&
              f.uri.pathSegments.last.startsWith('ic_launcher'))
          .map((f) => f.path),
      ...Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .map((f) => f.path),
      ...Directory('macos/Runner/Assets.xcassets/AppIcon.appiconset')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .map((f) => f.path),
      ...Directory('web')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) {
        final name = f.uri.pathSegments.last;
        return f.path.endsWith('.png') &&
            (name.contains('Icon') || name == 'favicon.png');
      }).map((f) => f.path),
    ];

    for (final path in paths) {
      final decoded = img.decodePng(File(path).readAsBytesSync());
      expect(decoded, isNotNull, reason: 'Could not decode $path');
      final image = decoded!;
      final corners = [
        image.getPixel(0, 0),
        image.getPixel(image.width - 1, 0),
        image.getPixel(0, image.height - 1),
        image.getPixel(image.width - 1, image.height - 1),
      ];
      for (final pixel in corners) {
        final white =
            pixel.a > 0 && pixel.r >= 245 && pixel.g >= 245 && pixel.b >= 245;
        expect(
          white,
          isFalse,
          reason: 'White icon background found in $path',
        );
      }
    }
  });
}
