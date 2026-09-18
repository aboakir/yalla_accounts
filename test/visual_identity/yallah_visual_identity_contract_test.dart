import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Iterable<File> dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

String source(String path) => File(path).readAsStringSync();

void expectCornerNotWhite(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  expect(decoded, isNotNull, reason: 'Cannot decode $path');
  final pixel = decoded!.getPixel(0, 0);
  final white =
      pixel.a > 250 && pixel.r > 250 && pixel.g > 250 && pixel.b > 250;
  expect(
    white,
    isFalse,
    reason: 'Logo/icon must never have a white background: $path',
  );
}

void main() {
  test('Yallah uses one canonical green and no raw dark-green UI colors', () {
    final offenders = <String>[];
    const forbiddenHex = <String>[
      '0xFF2F6F38',
      '0xFF2E7D32',
      '0xFF1B5E20',
      '0xFF388E3C',
      '0xFF43A047',
    ];

    for (final file in dartFilesUnder('lib')) {
      final content = file.readAsStringSync();
      final withoutTokens = content.replaceAll('AppColors.', '');
      if (withoutTokens.contains('Colors.green') ||
          withoutTokens.contains('Colors.greenAccent') ||
          withoutTokens.contains('Colors.lightGreen')) {
        offenders.add(file.path);
      }
      for (final hex in forbiddenHex) {
        if (content.contains(hex)) offenders.add('${file.path}:$hex');
      }
    }

    expect(offenders, isEmpty,
        reason: 'All green UI must use AppColors tokens.');
    final colors = source('lib/core/constants/colors.dart');
    expect(colors, contains('0xFF67BC1F'));
    final tokens = source('lib/core/design/yalla_design_tokens.dart');
    expect(tokens, contains('static const Color brandDark = brand;'));

    final main = source('lib/main.dart');
    expect(main, isNot(contains('ColorScheme.fromSeed(')));
    expect(main, contains('primary: AppColors.primary'));
  });

  test('Yallah branding images never carry a white background', () {
    expectCornerNotWhite('assets/branding/yallah_app_icon.png');

    final mark = img.decodeImage(
      File('assets/branding/yallah_mark.png').readAsBytesSync(),
    )!;
    final horizontal = img.decodeImage(
      File('assets/branding/yallah_logo_horizontal.png').readAsBytesSync(),
    )!;
    expect(mark.getPixel(0, 0).a, equals(0));
    expect(horizontal.getPixel(0, 0).a, equals(0));

    final platformPngs = <File>[
      ...Directory('android/app/src/main/res')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('ic_launcher.png')),
      ...Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png')),
      ...Directory('macos/Runner/Assets.xcassets/AppIcon.appiconset')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png')),
      File('web/favicon.png'),
    ];
    for (final file in platformPngs) {
      expectCornerNotWhite(file.path);
    }
  });

  test('Every in-app Yallah logo sits on non-white identity surface', () {
    final sidebar = source('lib/core/widgets/sidebar/sidebar_header.dart');
    expect(sidebar, contains('color: AppColors.lightGreen'));

    final appBar = source('lib/core/widgets/yalla_appbar.dart');
    expect(appBar, contains('backgroundColor: AppColors.lightGreen'));

    final splash = source('lib/features/splash/screens/splash_screen.dart');
    expect(splash, contains('backgroundColor: AppColors.scaffoldBg'));

    final login = source('lib/features/auth/screens/login_screen.dart');
    expect(login, contains('color: YallaColors.successSurface'));

    final unlock =
        source('lib/features/auth/screens/device_unlock_screen.dart');
    expect(unlock, contains('color: AppColors.lightGreen'));
  });
}
