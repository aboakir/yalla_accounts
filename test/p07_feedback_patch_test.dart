import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/utils/yalla_digits.dart';

void main() {
  test('normalizes Arabic and Persian digits without changing letters', () {
    expect(YallaDigitNormalizer.normalize('٢٠٢٦'), '2026');
    expect(YallaDigitNormalizer.normalize('۱۲۳ABC٤٥'), '123ABC45');
    expect(YallaDigitNormalizer.normalize('A-٩٠٠٧٦٥٤'), 'A-9007654');
  });
}
