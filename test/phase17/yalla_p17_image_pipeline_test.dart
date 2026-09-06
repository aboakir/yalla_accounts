import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P17 canonical image pipeline caps the longest side', () async {
    final source = im.Image(width: 2600, height: 1800);
    final encoded = Uint8List.fromList(im.encodeJpg(source, quality: 96));

    final optimized = await YallaStorageService.optimizeImageBytes(
      bytes: encoded,
      extension: 'jpg',
      maxDimension: 1200,
      quality: 80,
    );

    final decoded = im.decodeImage(optimized.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width <= 1200, isTrue);
    expect(decoded.height <= 1200, isTrue);
    expect(optimized.extension, 'jpg');
  });

  test('P17 image pipeline tolerates undecodable legacy bytes', () async {
    final source = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    final optimized = await YallaStorageService.optimizeImageBytes(
      bytes: source,
      extension: 'jpg',
    );
    expect(optimized.bytes, orderedEquals(source));
  });
}
