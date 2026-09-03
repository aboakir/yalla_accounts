import 'package:flutter/services.dart';

/// Normalizes Arabic-Indic and Persian digits to ASCII 0-9 without filtering
/// any other characters. This makes stored values and search keys consistent.
class YallaDigitNormalizer extends TextInputFormatter {
  const YallaDigitNormalizer();

  static String normalize(String value) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final a = arabicIndic.indexOf(char);
      if (a >= 0) {
        buffer.write(a);
        continue;
      }
      final p = persian.indexOf(char);
      if (p >= 0) {
        buffer.write(p);
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = normalize(newValue.text);
    if (normalized == newValue.text) return newValue;
    return newValue.copyWith(
      text: normalized,
      selection: TextSelection.collapsed(
        offset:
            newValue.selection.extentOffset.clamp(0, normalized.length).toInt(),
      ),
      composing: TextRange.empty,
    );
  }
}
